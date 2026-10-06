begin;

-- Badge « Traître » : la règle suit enfin sa description.
--
-- La description affichée est « Pronostiquer contre l’AS Grinta… et avoir
-- raison ». La métrique bet_against_grinta comptait pourtant tout pronostic
-- de défaite sur un match terminé, sans regarder le score réel : un
-- pronostic perdant contre l'AS Grinta suffisait. Elle exige désormais que
-- l'AS Grinta ait réellement perdu.
--
-- Le corps de private.profile_badge_metrics est repris à l'identique de
-- 20260921120000, à la seule ligne « against » près. Même signature : create
-- or replace conserve propriétaire et droits, et l'enveloppe publique, qui
-- relaie avec select *, n'a pas besoin d'être modifiée.
--
-- Le recalcul ne retire jamais un badge gagné. Un badge Traître attribué
-- automatiquement sous l'ancienne règle et que la nouvelle n'accorde plus est
-- donc retiré ici explicitement, avec son événement « revoke » dans le
-- journal. staff_revoke_badge n'est pas utilisé : il demande un compte
-- connecté. Un retrait n'envoie aucune notification. Une attribution
-- manuelle n'est pas touchée.

-- ---------------------------------------------------------------------------
-- 1. Règle corrigée
-- ---------------------------------------------------------------------------

create or replace function private.profile_badge_metrics(p_profile_id uuid)
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
      -- Traître : avoir prédit la défaite de l'AS Grinta ET qu'elle ait
      -- réellement perdu. Un match nul ou une victoire ne compte pas, ni un
      -- match sans score adverse (entre nous).
      coalesce(
        mp.is_filled
        and mp.predicted_score_as_grinta < mp.predicted_score_adverse
        and m.score_as_grinta < m.score_adverse,
        false
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

-- ---------------------------------------------------------------------------
-- 2. Retrait des badges attribués à tort
-- ---------------------------------------------------------------------------

with revoked as (
  delete from public.profile_badges owned
  using public.badges badge
  where badge.id = owned.badge_id
    and badge.code = 'bet_against_grinta__1'
    and owned.source = 'auto'
    and coalesce(
      (
        select metrics.bet_against_grinta
        from private.profile_badge_metrics(owned.profile_id) metrics
      ),
      0
    ) < badge.threshold
  returning
    owned.profile_id,
    owned.badge_id,
    badge.code,
    badge.name,
    badge.threshold,
    jsonb_build_object(
      'profile_id', owned.profile_id,
      'badge_id', owned.badge_id,
      'source', owned.source,
      'awarded_by', owned.awarded_by,
      'awarded_at', owned.awarded_at
    ) as state_before
)
insert into private.profile_badge_audit_log (
  event_type, profile_id, badge_id, badge_code, badge_name,
  actor_profile_id, occurred_at, source, metadata,
  state_before, state_after
)
select
  'revoke', revoked.profile_id, revoked.badge_id, revoked.code, revoked.name,
  null, now(), 'auto',
  jsonb_build_object(
    'reason', 'rule_correction',
    'metric', 'bet_against_grinta',
    'threshold', revoked.threshold,
    'value', 0
  ),
  revoked.state_before, null
from revoked;

commit;
