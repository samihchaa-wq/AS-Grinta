-- Suppression du pari « Buteurs » (pronostic de saison).
--
-- Les joueurs ne s'en servaient pas : la compétition est retirée du produit,
-- avec tout ce qui en dépendait.
--
-- Ce qui disparaît :
--   * la saisie et le stockage des pronostics de saison ;
--   * le gel de l'effectif au verrouillage (la « photo » de l'équipe) ;
--   * le verrou de saison lui-même (seasons.season_predictions_locked_at) ;
--   * les trois vues de score (points, drapeaux, bonus d'ordre) ;
--   * les titres « meilleur prono joueurs » et « meilleur pronostiqueur
--     global », ainsi que leurs badges ;
--   * la métrique de badge « prono parfait sur ses propres buts ».
--
-- Ce qui reste : le pronostic de match, seule compétition de pronostic. Le
-- classement général devient donc son classement, et v_classement_general ne
-- publie plus de colonne de saison. Aucun titre ni badge de saison n'avait été
-- attribué, donc aucun palmarès n'est réécrit.
--
-- La protection contre la réouverture d'une saison archivée ne dépend plus des
-- pronostics de saison : elle s'appuie désormais sur le fait qu'un match ait
-- déjà commencé, sur les pronostics de match remplis et sur les titres déjà
-- décernés.

begin;

-- ---------------------------------------------------------------------------
-- 1. Écritures du module : déclencheurs et fonctions propres au pari saison
-- ---------------------------------------------------------------------------

drop trigger if exists trg_seed_season_predictions_for_player
  on public.season_players;
drop trigger if exists trg_guard_season_prediction_roster_member
  on public.season_players;
drop trigger if exists trg_validate_season_prediction_row
  on public.season_predictions;
drop trigger if exists trg_shared_data_change on public.season_predictions;

drop function if exists public.seed_season_predictions_for_player();
drop function if exists private.guard_season_prediction_roster_member();
drop function if exists public.validate_season_prediction_row();
drop function if exists public.save_my_season_predictions(uuid, jsonb);
drop function if exists private.save_my_season_predictions(uuid, jsonb);
drop function if exists public.set_season_predictions_lock(uuid, boolean);
drop function if exists private.sync_season_prediction_roster_snapshot();

-- ---------------------------------------------------------------------------
-- 2. Classement général : plus qu'une compétition, celle des matchs
-- ---------------------------------------------------------------------------

drop view if exists public.v_classement_general;

create view public.v_classement_general
with (security_invoker = true)
as
with match_totals as (
  select points.profile_id,
         coalesce(sum(points.points), 0::numeric) as match_points
  from public.v_match_prediction_points points
  group by points.profile_id
), match_flags as (
  select flags.profile_id,
         coalesce(sum(flags.bon_pari), 0::bigint) as match_bons,
         coalesce(sum(flags.exact), 0::bigint) as match_exacts
  from public.v_match_prediction_flags flags
  group by flags.profile_id
), eligible_profiles as (
  select profile.id, profile.first_name, profile.surnom
  from public.profiles profile
  where not profile.is_test_account
    and (
      profile.status = 'active'
      or (
        profile.status = 'archived'
        and exists (
          select 1
          from public.match_predictions prediction
          where prediction.profile_id = profile.id
            and prediction.is_filled
        )
      )
    )
)
select profile.id as profile_id,
       profile.first_name,
       profile.surnom,
       coalesce(match_total.match_points, 0::numeric) as match_points,
       coalesce(match_stat.match_bons, 0::bigint) as match_bons,
       coalesce(match_stat.match_exacts, 0::bigint) as match_exacts
from eligible_profiles profile
left join match_totals match_total on match_total.profile_id = profile.id
left join match_flags match_stat on match_stat.profile_id = profile.id;

grant select on public.v_classement_general to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Titres de fin de saison : le titre « prono joueurs » et le titre global
--    disparaissent, « meilleur prono match » reste
-- ---------------------------------------------------------------------------

create or replace function public.award_season_titles(p_season_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into public.season_awards(season_id, profile_id, award_type)
  with eligible_profiles as (
    select profile.id
    from public.profiles profile
    where not profile.is_test_account
  ),
  tot as (
    select count(*)::int as c
    from public.matches
    where season_id = p_season_id
      and status in ('termine', 'archive')
  ),
  sp_prof as (
    select player.id, player.profile_id
    from public.season_players player
    join eligible_profiles eligible on eligible.id = player.profile_id
    where player.season_id = p_season_id
      and player.profile_id is not null
  ),
  present as (
    select distinct spp.profile_id, u.match_id
    from sp_prof spp
    join lateral (
      select ma.match_id from public.match_attendance ma
        where ma.season_player_id = spp.id
      union
      select s.match_id from public.match_player_stats s
        where s.season_player_id = spp.id
      union
      select v.match_id from public.match_man_of_match v
        where v.season_player_id = spp.id
    ) u on true
    join public.matches m
      on m.id = u.match_id
     and m.season_id = p_season_id
     and m.status in ('termine', 'archive')
  ),
  played as (
    select pr.profile_id,
           count(*)::int as n,
           count(*) filter (where m.score_as_grinta > m.score_adverse)::int as w
    from present pr
    join public.matches m on m.id = pr.match_id
    group by pr.profile_id
  ),
  goals as (
    select spp.profile_id, sum(s.goals)::int as g
    from sp_prof spp
    join public.match_player_stats s on s.season_player_id = spp.id
    join public.matches m
      on m.id = s.match_id
     and m.season_id = p_season_id
     and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  assists as (
    select spp.profile_id, sum(s.assists)::int as a
    from sp_prof spp
    join public.match_player_stats s on s.season_player_id = spp.id
    join public.matches m
      on m.id = s.match_id
     and m.season_id = p_season_id
     and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  mvp as (
    select spp.profile_id, count(*)::int as c
    from sp_prof spp
    join public.match_man_of_match v on v.season_player_id = spp.id
    join public.matches m
      on m.id = v.match_id
     and m.season_id = p_season_id
     and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  pmatch_pts as (
    select vp.profile_id, sum(vp.points)::numeric as pts
    from public.v_match_prediction_points vp
    join eligible_profiles eligible on eligible.id = vp.profile_id
    join public.matches m on m.id = vp.match_id and m.season_id = p_season_id
    group by vp.profile_id
  ),
  pmatch_cnt as (
    select mp.profile_id, count(*) filter (where mp.is_filled) as cnt
    from public.match_predictions mp
    join eligible_profiles eligible on eligible.id = mp.profile_id
    join public.matches m
      on m.id = mp.match_id
     and m.season_id = p_season_id
     and m.status in ('termine', 'archive')
    group by mp.profile_id
  ),
  w_complete as (
    select p.profile_id, 'season_complete'::text as at
    from played p, tot
    where tot.c > 0 and p.n = tot.c
  ),
  w_present as (
    select profile_id, 'most_present'
    from (select profile_id, rank() over (order by n desc) rk from played where n > 0) z
    where rk = 1
  ),
  w_scorer as (
    select profile_id, 'top_scorer'
    from (select profile_id, rank() over (order by g desc) rk from goals where g > 0) z
    where rk = 1
  ),
  w_passer as (
    select profile_id, 'top_assists'
    from (select profile_id, rank() over (order by a desc) rk from assists where a > 0) z
    where rk = 1
  ),
  w_mvp as (
    select profile_id, 'mvp_king'
    from (select profile_id, rank() over (order by c desc) rk from mvp where c > 0) z
    where rk = 1
  ),
  w_winrate as (
    select profile_id, 'best_winrate'
    from (
      select profile_id, rank() over (order by (w::numeric / n) desc) rk
      from played where n >= 5
    ) z
    where rk = 1
  ),
  w_pred_match as (
    select profile_id, 'best_pred_match'
    from (
      select pm.profile_id, rank() over (order by pm.pts desc) rk
      from pmatch_pts pm
      join pmatch_cnt pc on pc.profile_id = pm.profile_id
      where pc.cnt >= 5 and pm.pts > 0
    ) z
    where rk = 1
  )
  select p_season_id, allw.profile_id, allw.at
  from (
    select * from w_complete
    union all select * from w_present
    union all select * from w_scorer
    union all select * from w_passer
    union all select * from w_mvp
    union all select * from w_winrate
    union all select * from w_pred_match
  ) allw
  where allw.profile_id is not null
  on conflict (season_id, profile_id, award_type) do nothing;

  perform public.recalculate_all_badges();
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Métriques de badges : retrait des trois métriques du pari saison
-- ---------------------------------------------------------------------------

drop function if exists public.profile_badge_metrics(uuid);
drop function if exists private.profile_badge_metrics(uuid);

create function private.profile_badge_metrics(p_profile_id uuid)
returns table(
  matches_played_season integer,
  wins_season integer,
  goals_season integer,
  clean_sheets_season integer,
  matches_played integer,
  wins integer,
  goals integer,
  doubles integer,
  max_match_goals integer,
  mvp integer,
  clean_sheets integer,
  pred_good_result integer,
  pred_exact_score integer,
  bet_against_grinta integer,
  seasons_complete integer,
  title_most_present integer,
  title_top_scorer integer,
  title_mvp_king integer,
  title_best_winrate integer,
  title_best_pred_match integer,
  assists_season integer,
  assists integer,
  max_match_assists integer,
  title_top_assists integer
)
language sql
security definer
set search_path to ''
as $function$
  with pm as (
    select
      m.season_id,
      (m.score_as_grinta > m.score_adverse) as win,
      coalesce(st.goals, 0) as g,
      coalesce(st.assists, 0) as a,
      (m.score_adverse = 0) as cs,
      (mv.season_player_id is not null) as is_mvp
    from public.season_players sp
    join public.matches m
      on m.season_id = sp.season_id
     and m.status in ('termine', 'archive')
    left join public.match_player_stats st
      on st.season_player_id = sp.id
     and st.match_id = m.id
    left join public.match_attendance att
      on att.season_player_id = sp.id
     and att.match_id = m.id
    left join public.match_man_of_match mv
      on mv.season_player_id = sp.id
     and mv.match_id = m.id
    where sp.profile_id = p_profile_id
      and (
        st.match_id is not null
        or att.match_id is not null
        or mv.match_id is not null
      )
  ),
  ps as (
    select
      season_id,
      count(*) as mp,
      count(*) filter (where win) as w,
      sum(g) as gg,
      sum(a) as aa,
      count(*) filter (where cs) as csn,
      count(*) filter (where is_mvp) as mvpn,
      count(*) filter (where g = 2) as dbl
    from pm
    group by season_id
  ),
  player as (
    select
      coalesce(max(ps.mp) filter (where s.status = 'open'), 0)::int as matches_played_season,
      coalesce(max(ps.w) filter (where s.status = 'open'), 0)::int as wins_season,
      coalesce(max(ps.gg) filter (where s.status = 'open'), 0)::int as goals_season,
      coalesce(max(ps.aa) filter (where s.status = 'open'), 0)::int as assists_season,
      coalesce(max(ps.csn) filter (where s.status = 'open'), 0)::int as clean_sheets_season,
      coalesce(sum(ps.mp), 0)::int as matches_played,
      coalesce(sum(ps.w), 0)::int as wins,
      coalesce(sum(ps.gg), 0)::int as goals,
      coalesce(sum(ps.aa), 0)::int as assists,
      coalesce(sum(ps.dbl), 0)::int as doubles,
      coalesce(sum(ps.mvpn), 0)::int as mvp,
      coalesce(sum(ps.csn), 0)::int as clean_sheets
    from ps
    left join public.seasons s on s.id = ps.season_id
  ),
  hist as (
    select
      coalesce(sum(h.matches_played), 0)::int as h_mp,
      coalesce(sum(h.wins), 0)::int as h_w,
      coalesce(sum(h.goals), 0)::int as h_g,
      coalesce(sum(h.team_clean_sheets), 0)::int as h_cs,
      coalesce(sum(h.hdm), 0)::int as h_mvp
    from public.historical_player_statistics h
    where h.scope = 'all_time'
      and (
        h.profile_id = p_profile_id
        or (
          h.profile_id is null
          and lower(btrim(h.player_name)) in (
            select distinct lower(
              btrim(concat_ws(' ', sp.first_name, nullif(sp.last_name, '')))
            )
            from public.season_players sp
            where sp.profile_id = p_profile_id
              and coalesce(btrim(sp.first_name), '') <> ''
          )
        )
      )
  ),
  pmax as (
    select
      coalesce(max(g), 0)::int as max_match_goals,
      coalesce(max(a), 0)::int as max_match_assists
    from pm
  ),
  mpred as (
    select
      (
        mp.is_filled
        and sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
          = sign((m.score_as_grinta - m.score_adverse)::numeric)
      )::int as bon,
      (
        mp.is_filled
        and mp.predicted_score_as_grinta = m.score_as_grinta
        and mp.predicted_score_adverse = m.score_adverse
      )::int as ex,
      (
        mp.is_filled
        and mp.predicted_score_as_grinta < mp.predicted_score_adverse
      )::int as against
    from public.match_predictions mp
    join public.matches m
      on m.id = mp.match_id
     and m.status in ('termine', 'archive')
    where mp.profile_id = p_profile_id
  ),
  mpred_a as (
    select
      coalesce(sum(bon), 0)::int as pred_good_result,
      coalesce(sum(ex), 0)::int as pred_exact_score,
      coalesce(sum(against), 0)::int as bet_against_grinta
    from mpred
  ),
  aw as (
    select
      count(*) filter (where award_type = 'season_complete')::int as seasons_complete,
      count(*) filter (where award_type = 'most_present')::int as title_most_present,
      count(*) filter (where award_type = 'top_scorer')::int as title_top_scorer,
      count(*) filter (where award_type = 'top_assists')::int as title_top_assists,
      count(*) filter (where award_type = 'mvp_king')::int as title_mvp_king,
      count(*) filter (where award_type = 'best_winrate')::int as title_best_winrate,
      count(*) filter (where award_type = 'best_pred_match')::int as title_best_pred_match
    from public.season_awards
    where profile_id = p_profile_id
  )
  select
    player.matches_played_season,
    player.wins_season,
    player.goals_season,
    player.clean_sheets_season,
    (player.matches_played + hist.h_mp)::int as matches_played,
    (player.wins + hist.h_w)::int as wins,
    (player.goals + hist.h_g)::int as goals,
    player.doubles,
    pmax.max_match_goals,
    (player.mvp + hist.h_mvp)::int as mvp,
    (player.clean_sheets + hist.h_cs)::int as clean_sheets,
    mpred_a.pred_good_result,
    mpred_a.pred_exact_score,
    mpred_a.bet_against_grinta,
    aw.seasons_complete,
    aw.title_most_present,
    aw.title_top_scorer,
    aw.title_mvp_king,
    aw.title_best_winrate,
    aw.title_best_pred_match,
    player.assists_season,
    player.assists,
    pmax.max_match_assists,
    aw.title_top_assists
  from player, hist, pmax, mpred_a, aw;
$function$;

alter function private.profile_badge_metrics(uuid) owner to postgres;
revoke all on function private.profile_badge_metrics(uuid)
  from public, anon, authenticated;
grant execute on function private.profile_badge_metrics(uuid) to service_role;

comment on function private.profile_badge_metrics(uuid) is
  'Implementation reelle des metriques de badges. Reservee aux appelants internes : passer par public.profile_badge_metrics() qui controle l''identite.';

create function public.profile_badge_metrics(p_profile_id uuid)
returns table(
  matches_played_season integer,
  wins_season integer,
  goals_season integer,
  clean_sheets_season integer,
  matches_played integer,
  wins integer,
  goals integer,
  doubles integer,
  max_match_goals integer,
  mvp integer,
  clean_sheets integer,
  pred_good_result integer,
  pred_exact_score integer,
  bet_against_grinta integer,
  seasons_complete integer,
  title_most_present integer,
  title_top_scorer integer,
  title_mvp_king integer,
  title_best_winrate integer,
  title_best_pred_match integer,
  assists_season integer,
  assists integer,
  max_match_assists integer,
  title_top_assists integer
)
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if p_profile_id is null then
    return;
  end if;

  if p_profile_id is distinct from (select auth.uid())
     and not public.is_match_staff() then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  return query select * from private.profile_badge_metrics(p_profile_id);
end;
$function$;

alter function public.profile_badge_metrics(uuid) owner to postgres;

-- ---------------------------------------------------------------------------
-- 5. Rapport d'intégrité : le contrôle des grilles de saison disparaît
-- ---------------------------------------------------------------------------

create or replace function public.staff_app_integrity_report()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_checks jsonb;
  v_total bigint;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  with checks as (
    select 'matches_without_odds'::text as check_name, count(*)::bigint as issue_count
    from public.matches m
    left join public.match_odds mo on mo.match_id = m.id
    where m.match_type <> 'entre_nous'
      and mo.match_id is null

    union all

    select 'finished_without_scores', count(*)::bigint
    from public.matches
    where status in ('termine', 'archive')
      and (score_as_grinta is null or score_adverse is null)

    union all

    select 'upcoming_with_scores', count(*)::bigint
    from public.matches
    where status = 'a_venir'
      and (score_as_grinta is not null or score_adverse is not null)

    union all

    select 'duplicate_match_datetime', count(*)::bigint
    from (
      select match_date, match_time
      from public.matches
      group by match_date, match_time
      having count(*) > 1
    ) duplicates

    union all

    select 'multiple_open_seasons', greatest(count(*) - 1, 0)::bigint
    from public.seasons
    where status = 'open'

    union all

    select 'orphan_match_predictions', count(*)::bigint
    from public.match_predictions mp
    left join public.matches m on m.id = mp.match_id
    left join public.profiles p on p.id = mp.profile_id
    where m.id is null or p.id is null

    union all

    select 'filled_predictions_missing_scores', count(*)::bigint
    from public.match_predictions
    where is_filled
      and (
        predicted_score_as_grinta is null
        or predicted_score_adverse is null
      )

    union all

    select 'missing_upcoming_prediction_seeds', count(*)::bigint
    from public.matches m
    cross join public.profiles p
    left join public.match_predictions mp
      on mp.match_id = m.id
     and mp.profile_id = p.id
    where m.status = 'a_venir'
      and m.match_type <> 'entre_nous'
      and p.status = 'active'
      and mp.id is null

    union all

    select 'kickoff_mismatch', count(*)::bigint
    from public.matches m
    where m.match_time is not null
      and m.kickoff_at is distinct from
        ((m.match_date + m.match_time) at time zone 'Europe/Paris')

    union all

    select 'historical_goals_exceed_team_score', count(*)::bigint
    from (
      select hms.id
      from public.historical_match_scores hms
      left join public.historical_match_players hmp on hmp.match_id = hms.id
      where hms.score_as_grinta is not null
      group by hms.id, hms.score_as_grinta
      having coalesce(sum(hmp.goals), 0) > hms.score_as_grinta
    ) matches_with_excess_goals

    union all

    select 'historical_matches_without_players', count(*)::bigint
    from public.historical_match_scores hms
    where not exists (
      select 1
      from public.historical_match_players hmp
      where hmp.match_id = hms.id
    )

    union all

    select 'historical_unattributed_goals', count(*)::bigint
    from (
      select hms.id
      from public.historical_match_scores hms
      left join public.historical_match_players hmp on hmp.match_id = hms.id
      where hms.score_as_grinta is not null
      group by hms.id, hms.score_as_grinta
      having coalesce(sum(hmp.goals), 0) < hms.score_as_grinta
    ) matches_with_unattributed_goals
  ), aggregated as (
    select
      coalesce(sum(issue_count), 0)::bigint as total_issues,
      jsonb_agg(
        jsonb_build_object(
          'check', check_name,
          'issues', issue_count
        )
        order by check_name
      ) as checks
    from checks
  )
  select total_issues, checks
  into v_total, v_checks
  from aggregated;

  return jsonb_build_object(
    'healthy', v_total = 0,
    'total_issues', v_total,
    'checked_at', now(),
    'checks', coalesce(v_checks, '[]'::jsonb)
  );
end;
$function$;
-- ---------------------------------------------------------------------------
-- 6. Amorçage : un nouveau membre actif ne reçoit plus de grille de saison
-- ---------------------------------------------------------------------------

create or replace function public.seed_predictions_for_active_profile()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.status <> 'active' then
    return new;
  end if;

  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled
  )
  select match.id, new.id, 0, 0, false
  from public.matches match
  where match.status = 'a_venir'
    and match.match_type <> 'entre_nous'
  on conflict (match_id, profile_id) do nothing;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 7. Signal de rafraîchissement : la table exclue n'existe plus
-- ---------------------------------------------------------------------------

create or replace function private.signal_shared_data_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_profile_increment bigint := 0;
  v_sports_increment bigint := 0;
begin
  if tg_table_schema = 'public' and tg_table_name = 'profiles' then
    v_profile_increment := 1;
  end if;

  if tg_table_schema = 'public' and tg_table_name = any (array[
    'guest_players',
    'match_compositions',
    'match_composition_entries',
    'match_composition_publications',
    'sport_waitlist_entries',
    'match_sport_participants',
    'match_sport_workflows'
  ]) then
    v_sports_increment := 1;
  end if;

  insert into public.shared_data_change_signals(
    key,
    revision,
    profile_revision,
    sports_revision,
    updated_at
  )
  values ('global', 1, 1, 1, now())
  on conflict (key) do update
  set revision = public.shared_data_change_signals.revision + 1,
      profile_revision =
        public.shared_data_change_signals.profile_revision
        + v_profile_increment,
      sports_revision =
        public.shared_data_change_signals.sports_revision
        + v_sports_increment,
      updated_at = excluded.updated_at;
  return null;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 8. Cycle de vie de la saison, sans le verrou de pari
-- ---------------------------------------------------------------------------

-- Une saison archivée reste irréversible dès qu'elle porte de la compétition.
-- Le pari saison n'en fait plus partie : restent un match déjà commencé, un
-- pronostic de match rempli, ou un titre déjà décerné.
create or replace function private.season_has_historical_competition(
  p_season_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    exists (
      select 1
      from public.matches match
      where match.season_id = p_season_id
        and match.status <> 'annule'
        and match.kickoff_at is not null
        and match.kickoff_at <= now()
    )
    or exists (
      select 1
      from public.match_predictions prediction
      join public.matches match on match.id = prediction.match_id
      where match.season_id = p_season_id
        and prediction.is_filled
    )
    or exists (
      select 1
      from public.season_awards award
      where award.season_id = p_season_id
    );
$function$;

revoke all on function private.season_has_historical_competition(uuid)
  from public, anon, authenticated;

create or replace function private.guard_season_competition_finality()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.status = 'archived'
     and old.status is distinct from 'archived' then
    perform private.assert_season_can_archive(new.id);
  end if;

  if old.status = 'archived'
     and new.status is distinct from old.status
     and private.season_has_historical_competition(old.id) then
    raise exception
      'Une saison archivée avec des données de compétition ne peut pas être rouverte.'
      using errcode = '22023';
  end if;

  return new;
end;
$function$;

create or replace function private.finalize_season_competition_transition()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_archiving boolean := false;
begin
  if tg_op = 'INSERT' then
    v_archiving := new.status = 'archived';

    -- INSERT does not pass through the UPDATE guard.
    if v_archiving then
      perform private.assert_season_can_archive(new.id);
    end if;
  else
    v_archiving := old.status is distinct from 'archived'
      and new.status = 'archived';
  end if;

  if v_archiving then
    -- Volontairement dans le même déclencheur : un échec de titre ou de badge
    -- annule le changement de statut avec lui.
    perform public.award_season_titles(new.id);
  end if;

  return new;
end;
$function$;

create or replace function public.open_or_create_season(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  season_name text := btrim(coalesce(p_name, ''));
  start_year integer;
  end_year integer;
  season_id uuid;
  season_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if season_name !~ '^[0-9]{4}-[0-9]{4}$' then
    raise exception 'Le nom doit respecter le format 2026-2027' using errcode = '22023';
  end if;

  start_year := substring(season_name from 1 for 4)::integer;
  end_year := substring(season_name from 6 for 4)::integer;
  if end_year <> start_year + 1 then
    raise exception 'La saison doit couvrir deux années consécutives' using errcode = '22023';
  end if;
  if start_year < 2000 or start_year > 2100 then
    raise exception 'Année de saison hors limites' using errcode = '22023';
  end if;

  select season.id, season.status
  into season_id, season_status
  from public.seasons season
  where season.name = season_name
  for update;

  if found then
    if season_status <> 'open'
       and private.season_has_historical_competition(season_id) then
      raise exception 'Une saison avec des données de compétition ne peut pas être rouverte.'
        using errcode = '22023';
    end if;

    update public.seasons
    set status = 'archived'
    where status = 'open'
      and id <> season_id;

    update public.seasons
    set status = 'open'
    where id = season_id;

    return season_id;
  end if;

  update public.seasons
  set status = 'archived'
  where status = 'open';

  insert into public.seasons(name, status)
  values (season_name, 'open')
  returning id into season_id;

  return season_id;
end;
$function$;

drop function if exists private.season_prediction_lock_is_committed(uuid);

-- ---------------------------------------------------------------------------
-- 9. Vues, tables et colonne du module
-- ---------------------------------------------------------------------------

drop view if exists public.v_season_prediction_points;
drop view if exists public.v_season_prediction_flags;
drop view if exists public.v_season_prediction_bonus;

drop table if exists public.season_prediction_roster_members;
drop table if exists public.season_prediction_roster_captures;
drop table if exists public.season_predictions;

-- Les deux déclencheurs de saison n'écoutaient que « status » et le verrou de
-- pari. Ils doivent être redéclarés sur le seul statut avant que la colonne
-- puisse disparaître.
drop trigger if exists trg_guard_season_competition_finality on public.seasons;
create trigger trg_guard_season_competition_finality
before update of status on public.seasons
for each row execute function private.guard_season_competition_finality();

drop trigger if exists trg_finalize_season_competition on public.seasons;
create trigger trg_finalize_season_competition
after insert or update of status on public.seasons
for each row execute function private.finalize_season_competition_transition();

alter table public.seasons
  drop column if exists season_predictions_locked_at;

-- ---------------------------------------------------------------------------
-- 10. Palmarès et badges adossés au pari saison
-- ---------------------------------------------------------------------------

delete from public.profile_badges
where badge_id in (
  select id
  from public.badges
  where metric in ('title_best_pred_player', 'title_best_pred_overall')
);

delete from public.badges
where metric in ('title_best_pred_player', 'title_best_pred_overall');

delete from public.season_awards
where award_type in ('best_pred_player', 'best_pred_overall');

commit;
