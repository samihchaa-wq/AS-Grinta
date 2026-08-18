-- Close the remaining competition-integrity gaps found by the authenticated
-- Prono end-to-end audit.
--
-- - all match-prediction writes go through the guarded RPC;
-- - an internal match can never receive a filled prediction;
-- - rescheduling clears a stale manual prediction close only when kickoff moves;
-- - revealing season predictions is irreversible;
-- - archived seasons are terminal and cannot be reopened/unlocked;
-- - prediction roster snapshots are immutable once captured;
-- - archived real participants keep their historical leaderboard presence;
-- - test accounts can never receive season awards.

revoke insert, update on table public.match_predictions from authenticated;

drop policy if exists match_predictions_owner_insert on public.match_predictions;
drop policy if exists match_predictions_owner_update_window on public.match_predictions;

create or replace function public.guard_match_prediction_window()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_kickoff timestamptz;
  v_match_status text;
  v_closed_at timestamptz;
  v_match_type text;
begin
  if (select auth.uid()) is not null and pg_trigger_depth() <= 1 then
    if tg_op = 'UPDATE' and new.match_id is distinct from old.match_id then
      raise exception 'Le match d’un pronostic ne peut pas être modifié.'
        using errcode = '22023';
    end if;
    new.profile_id := (select auth.uid());
  end if;

  if new.is_filled then
    select
      match.kickoff_at,
      match.status,
      match.predictions_closed_at,
      match.match_type
    into v_kickoff, v_match_status, v_closed_at, v_match_type
    from public.matches match
    where match.id = new.match_id;

    if not found then
      raise exception 'Match introuvable.' using errcode = 'P0002';
    end if;

    if v_match_type = 'entre_nous' then
      raise exception 'Les matchs entre nous ne sont pas ouverts aux pronostics.'
        using errcode = '22023';
    end if;

    if v_kickoff is null
       or v_match_status <> 'a_venir'
       or now() < private.match_features_open_at(v_kickoff)
       or now() >= private.match_prediction_closes_at(v_kickoff)
       or (v_closed_at is not null and now() >= v_closed_at) then
      raise exception 'Pronostic fermé' using errcode = '22023';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.update_match_with_odds(
  p_match_id uuid,
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_status text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match_id uuid;
  v_old_match_date date;
  v_old_match_time time without time zone;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null or p_season_id is null or p_opponent_id is null
     or p_match_date is null or p_match_time is null then
    raise exception 'Match, saison, adversaire, date et heure requis.'
      using errcode = '22023';
  end if;
  if p_location not in ('domicile', 'exterieur') then
    raise exception 'Lieu invalide.' using errcode = '22023';
  end if;
  if p_status is distinct from 'a_venir' then
    raise exception 'Le statut se modifie via le workflow dédié du match.'
      using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Date de match hors limites.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.seasons s where s.id = p_season_id) then
    raise exception 'Saison introuvable.' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.opponents o where o.id = p_opponent_id) then
    raise exception 'Adversaire introuvable.' using errcode = 'P0002';
  end if;
  if p_win is null or p_draw is null or p_loss is null
     or p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
     or p_win > 100 or p_draw > 100 or p_loss > 100 then
    raise exception 'Cotes invalides.' using errcode = '22023';
  end if;

  select match.id, match.match_date, match.match_time
  into v_match_id, v_old_match_date, v_old_match_time
  from public.matches match
  where match.id = p_match_id
  for update;

  if v_match_id is null then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  update public.matches
  set season_id = p_season_id,
      opponent_id = p_opponent_id,
      match_date = p_match_date,
      match_time = p_match_time,
      location = p_location,
      status = 'a_venir',
      predictions_closed_at = case
        when v_old_match_date is distinct from p_match_date
          or v_old_match_time is distinct from p_match_time
          then null
        else predictions_closed_at
      end,
      updated_at = now()
  where id = p_match_id;

  insert into public.match_odds (
    match_id,
    odds_victoire_as_grinta,
    odds_nul,
    odds_victoire_adverse,
    computed_at
  ) values (
    p_match_id,
    round(p_win, 2),
    round(p_draw, 2),
    round(p_loss, 2),
    now()
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      computed_at = now();

  return true;
end;
$function$;

create or replace function private.guard_season_competition_finality()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.status = 'archived' and new.status is distinct from old.status then
    raise exception 'Une saison archivée ne peut pas être rouverte.'
      using errcode = '22023';
  end if;

  if old.season_predictions_locked_at is not null
     and new.season_predictions_locked_at is distinct from old.season_predictions_locked_at then
    raise exception 'Les pronostics de saison révélés sont définitivement figés.'
      using errcode = '22023';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_guard_season_competition_finality on public.seasons;
create trigger trg_guard_season_competition_finality
before update of status, season_predictions_locked_at on public.seasons
for each row execute function private.guard_season_competition_finality();

create or replace function public.set_season_predictions_lock(
  p_season_id uuid,
  p_locked boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_locked_at timestamptz;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null or p_locked is null then
    raise exception 'Season id and lock value are required' using errcode = '22023';
  end if;

  select season.season_predictions_locked_at
  into v_locked_at
  from public.seasons season
  where season.id = p_season_id
    and season.status = 'open'
  for update;

  if not found then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;

  if v_locked_at is not null then
    if p_locked then
      return true;
    end if;
    raise exception 'Les pronostics de saison révélés sont définitivement figés.'
      using errcode = '22023';
  end if;

  if not p_locked then
    return true;
  end if;

  update public.seasons
  set season_predictions_locked_at = now()
  where id = p_season_id;

  return true;
end;
$function$;

create or replace function private.sync_season_prediction_roster_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- Once a prediction roster is revealed, its historical contract is never
  -- deleted or recaptured. The write guard makes the lock one-way.
  if old.season_predictions_locked_at is null
     and new.season_predictions_locked_at is not null
     and not exists (
       select 1
       from public.season_prediction_roster_captures capture
       where capture.season_id = new.id
     )
  then
    insert into public.season_prediction_roster_captures(
      season_id, captured_at, capture_reason
    ) values (new.id, new.season_predictions_locked_at, 'lock');

    insert into public.season_prediction_roster_members(
      season_id, season_player_id, category
    )
    select
      player.season_id,
      player.id,
      case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
    from public.season_players player
    where player.season_id = new.id
      and player.is_active;

    return new;
  end if;

  -- Archiving without an explicit prior lock captures the final active roster
  -- once. A prior lock always wins and remains immutable.
  if old.status is distinct from 'archived'
     and new.status = 'archived'
     and not exists (
       select 1
       from public.season_prediction_roster_captures capture
       where capture.season_id = new.id
     )
  then
    insert into public.season_prediction_roster_captures(
      season_id, captured_at, capture_reason
    ) values (new.id, now(), 'archive');

    insert into public.season_prediction_roster_members(
      season_id, season_player_id, category
    )
    select
      player.season_id,
      player.id,
      case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
    from public.season_players player
    where player.season_id = new.id
      and player.is_active;
  end if;

  return new;
end;
$function$;

create or replace function public.set_season_status(
  p_season_id uuid,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null then
    raise exception 'Season id is required' using errcode = '22023';
  end if;
  if p_status is null or p_status not in ('open', 'terminee', 'archived') then
    raise exception 'Statut de saison invalide' using errcode = '22023';
  end if;

  select season.status
  into v_current_status
  from public.seasons season
  where season.id = p_season_id
  for update;

  if not found then
    raise exception 'Season not found' using errcode = 'P0002';
  end if;

  if v_current_status = p_status then
    return true;
  end if;

  if v_current_status = 'archived' then
    raise exception 'Une saison archivée est définitive.' using errcode = '22023';
  end if;

  if v_current_status = 'terminee' and p_status = 'open' then
    raise exception 'Une saison terminée ne peut pas être rouverte.'
      using errcode = '22023';
  end if;

  update public.seasons
  set status = p_status
  where id = p_season_id;

  return true;
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
    if season_status = 'open' then
      return season_id;
    end if;
    raise exception 'Une saison terminée ou archivée ne peut pas être rouverte.'
      using errcode = '22023';
  end if;

  if exists (select 1 from public.seasons season where season.status = 'open') then
    raise exception 'Une saison est déjà ouverte. Termine-la avant d’en créer une nouvelle.'
      using errcode = '22023';
  end if;

  insert into public.seasons(name, status)
  values (season_name, 'open')
  returning id into season_id;

  return season_id;
end;
$function$;

create or replace view public.v_classement_general
with (security_invoker = true)
as
with match_totals as (
  select points.profile_id, coalesce(sum(points.points), 0::numeric) as match_points
  from public.v_match_prediction_points points
  group by points.profile_id
), match_flags as (
  select flags.profile_id,
         coalesce(sum(flags.bon_pari), 0::bigint) as match_bons,
         coalesce(sum(flags.exact), 0::bigint) as match_exacts
  from public.v_match_prediction_flags flags
  group by flags.profile_id
), season_totals as (
  select points.predictor_profile_id as profile_id,
         coalesce(sum(points.points), 0::bigint)::numeric as season_points
  from public.v_season_prediction_points points
  group by points.predictor_profile_id
), season_bonus as (
  select bonus.predictor_profile_id as profile_id,
         coalesce(sum(bonus.bonus_points), 0::bigint)::numeric as bonus_points
  from public.v_season_prediction_bonus bonus
  group by bonus.predictor_profile_id
), season_flags as (
  select flags.predictor_profile_id as profile_id,
         coalesce(sum(flags.bon_pari), 0::bigint) as season_bons,
         coalesce(sum(flags.exact), 0::bigint) as season_exacts
  from public.v_season_prediction_flags flags
  group by flags.predictor_profile_id
), eligible_profiles as (
  select profile.id, profile.first_name, profile.surnom
  from public.profiles profile
  where not profile.is_test_account
    and (
      profile.status = 'active'
      or (
        profile.status = 'archived'
        and (
          exists (
            select 1
            from public.match_predictions prediction
            where prediction.profile_id = profile.id
              and prediction.is_filled
          )
          or exists (
            select 1
            from public.season_predictions prediction
            where prediction.predictor_profile_id = profile.id
              and prediction.is_filled
          )
        )
      )
    )
), totals as (
  select profile.id as profile_id,
         profile.first_name,
         profile.surnom,
         coalesce(match_total.match_points, 0::numeric) as match_points,
         coalesce(season_total.season_points, 0::numeric)
           + coalesce(season_extra.bonus_points, 0::numeric) as season_points,
         coalesce(match_stat.match_bons, 0::bigint) as match_bons,
         coalesce(match_stat.match_exacts, 0::bigint) as match_exacts,
         coalesce(season_stat.season_bons, 0::bigint) as season_bons,
         coalesce(season_stat.season_exacts, 0::bigint) as season_exacts
  from eligible_profiles profile
  left join match_totals match_total on match_total.profile_id = profile.id
  left join match_flags match_stat on match_stat.profile_id = profile.id
  left join season_totals season_total on season_total.profile_id = profile.id
  left join season_bonus season_extra on season_extra.profile_id = profile.id
  left join season_flags season_stat on season_stat.profile_id = profile.id
)
select profile_id,
       first_name,
       surnom,
       match_points,
       season_points,
       match_points * 100::numeric + season_points as total_points,
       match_bons,
       match_exacts,
       season_bons,
       season_exacts
from totals;

create or replace function public.award_season_titles(p_season_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $function$
begin
  insert into public.season_awards(season_id, profile_id, award_type)
  with tot as (
    select count(*)::int as c from public.matches
    where season_id = p_season_id and status in ('termine', 'archive')
  ),
  sp_prof as (
    select id, profile_id from public.season_players
    where season_id = p_season_id and profile_id is not null
  ),
  present as (
    select distinct spp.profile_id, u.match_id
    from sp_prof spp
    join lateral (
      select ma.match_id from public.match_attendance ma where ma.season_player_id = spp.id
      union select s.match_id from public.match_player_stats s where s.season_player_id = spp.id
      union select v.match_id from public.match_man_of_match v where v.season_player_id = spp.id
    ) u on true
    join public.matches m on m.id = u.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
  ),
  played as (
    select pr.profile_id, count(*)::int as n,
           count(*) filter (where m.score_as_grinta > m.score_adverse)::int as w
    from present pr join public.matches m on m.id = pr.match_id
    group by pr.profile_id
  ),
  goals as (
    select spp.profile_id, sum(s.goals)::int as g
    from sp_prof spp
    join public.match_player_stats s on s.season_player_id = spp.id
    join public.matches m on m.id = s.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  mvp as (
    select spp.profile_id, count(*)::int as c
    from sp_prof spp
    join public.match_man_of_match v on v.season_player_id = spp.id
    join public.matches m on m.id = v.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  pmatch_pts as (
    select vp.profile_id, sum(vp.points) as pts
    from public.v_match_prediction_points vp
    join public.matches m on m.id = vp.match_id and m.season_id = p_season_id
    group by vp.profile_id
  ),
  pmatch_cnt as (
    select mp.profile_id, count(*) filter (where mp.is_filled) as cnt
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by mp.profile_id
  ),
  pplayer_pts as (
    select predictor_profile_id as profile_id, sum(points)::numeric as pts
    from public.v_season_prediction_points where season_id = p_season_id
    group by predictor_profile_id
  ),
  poverall as (
    select coalesce(pm.profile_id, pp.profile_id) as profile_id,
           coalesce(pm.pts, 0) + coalesce(pp.pts, 0) as total
    from pmatch_pts pm
    full outer join pplayer_pts pp on pp.profile_id = pm.profile_id
  ),
  w_complete as (
    select p.profile_id, 'season_complete'::text as at
    from played p, tot where tot.c > 0 and p.n = tot.c
  ),
  w_present as (
    select profile_id, 'most_present' from (
      select profile_id, rank() over (order by n desc) rk from played where n > 0
    ) z where rk = 1
  ),
  w_scorer as (
    select profile_id, 'top_scorer' from (
      select profile_id, rank() over (order by g desc) rk from goals where g > 0
    ) z where rk = 1
  ),
  w_mvp as (
    select profile_id, 'mvp_king' from (
      select profile_id, rank() over (order by c desc) rk from mvp where c > 0
    ) z where rk = 1
  ),
  w_winrate as (
    select profile_id, 'best_winrate' from (
      select profile_id, rank() over (order by (w::numeric / n) desc) rk
      from played where n >= 5
    ) z where rk = 1
  ),
  w_pred_match as (
    select profile_id, 'best_pred_match' from (
      select pm.profile_id, rank() over (order by pm.pts desc) rk
      from pmatch_pts pm join pmatch_cnt pc on pc.profile_id = pm.profile_id
      where pc.cnt >= 5 and pm.pts > 0
    ) z where rk = 1
  ),
  w_pred_player as (
    select profile_id, 'best_pred_player' from (
      select profile_id, rank() over (order by pts desc) rk from pplayer_pts where pts > 0
    ) z where rk = 1
  ),
  w_pred_overall as (
    select profile_id, 'best_pred_overall' from (
      select profile_id, rank() over (order by total desc) rk from poverall where total > 0
    ) z where rk = 1
  )
  select p_season_id, allw.profile_id, allw.at
  from (
    select * from w_complete
    union all select * from w_present
    union all select * from w_scorer
    union all select * from w_mvp
    union all select * from w_winrate
    union all select * from w_pred_match
    union all select * from w_pred_player
    union all select * from w_pred_overall
  ) allw
  join public.profiles profile on profile.id = allw.profile_id
  where allw.profile_id is not null
    and not profile.is_test_account
  on conflict (season_id, profile_id, award_type) do nothing;

  perform public.recalculate_all_badges();
end;
$function$;
