begin;

-- Les membres marqués Coach restent des utilisateurs du produit (dispo, prono,
-- HDM, Live selon leurs droits), mais ne sont jamais des joueurs statistiques
-- ni des cibles du pari Buteurs/Clean sheets.

-- Nettoyage uniquement de la saison ouverte tant que le pari n'est pas figé.
delete from public.season_predictions prediction
using public.season_players player, public.seasons season
where prediction.season_player_id = player.id
  and prediction.season_id = player.season_id
  and season.id = player.season_id
  and season.status = 'open'
  and season.season_predictions_locked_at is null
  and player.is_coach;

-- ---------------------------------------------------------------------------
-- 1. Saisie du pari saison : effectif actif hors coachs
-- ---------------------------------------------------------------------------

create or replace function private.save_my_season_predictions(
  p_season_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_locked_at timestamptz;
  v_count integer;
  v_expected integer;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_season_id is null then
    raise exception 'Season is required' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Predictions must be an array' using errcode = '22023';
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
    raise exception 'Season predictions are locked' using errcode = '22023';
  end if;

  select count(*)::integer
  into v_count
  from jsonb_array_elements(p_items);

  if v_count < 1 or v_count > 100 then
    raise exception 'Invalid prediction item count' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as item(
      season_player_id uuid,
      category text,
      predicted_value_30 integer
    )
    where item.season_player_id is null
      or item.category not in ('buts', 'clean_sheets')
      or item.predicted_value_30 is null
      or item.predicted_value_30 < 0
      or item.predicted_value_30 > 99
  ) then
    raise exception 'Invalid season prediction value' using errcode = '22023';
  end if;

  if (
    select count(*)
    from (
      select item.season_player_id, item.category
      from jsonb_to_recordset(p_items) as item(
        season_player_id uuid,
        category text,
        predicted_value_30 integer
      )
      group by item.season_player_id, item.category
    ) unique_items
  ) <> v_count then
    raise exception 'Duplicate season prediction item' using errcode = '22023';
  end if;

  select count(*)::integer
  into v_expected
  from public.season_players player
  where player.season_id = p_season_id
    and player.is_active
    and not player.is_coach;

  if v_count <> v_expected then
    raise exception 'The complete active player roster must be submitted'
      using errcode = '22023';
  end if;

  if (
    select count(*)
    from jsonb_to_recordset(p_items) as item(
      season_player_id uuid,
      category text,
      predicted_value_30 integer
    )
    join public.season_players player
      on player.id = item.season_player_id
     and player.season_id = p_season_id
     and player.is_active
     and not player.is_coach
    where (player.is_goalkeeper and item.category = 'clean_sheets')
       or (not player.is_goalkeeper and item.category = 'buts')
  ) <> v_count then
    raise exception 'Prediction items do not match the active player roster'
      using errcode = '22023';
  end if;

  insert into public.season_predictions(
    season_id,
    predictor_profile_id,
    season_player_id,
    category,
    predicted_value_30,
    is_filled,
    updated_at
  )
  select
    p_season_id,
    v_actor,
    item.season_player_id,
    item.category,
    item.predicted_value_30,
    true,
    now()
  from jsonb_to_recordset(p_items) as item(
    season_player_id uuid,
    category text,
    predicted_value_30 integer
  )
  on conflict (
    season_id,
    predictor_profile_id,
    season_player_id,
    category
  )
  do update set
    predicted_value_30 = excluded.predicted_value_30,
    is_filled = true,
    updated_at = now();

  return jsonb_build_object(
    'season_id', p_season_id,
    'saved', v_count
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Snapshot du pari saison : ne jamais figer un coach comme cible
-- ---------------------------------------------------------------------------

create or replace function private.sync_season_prediction_roster_snapshot()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if old.season_predictions_locked_at is not null
     and new.season_predictions_locked_at is null then
    if private.season_prediction_lock_is_committed(new.id) then
      raise exception 'Les pronostics de saison révélés sont définitivement figés.'
        using errcode = '22023';
    end if;
    delete from public.season_prediction_roster_captures
    where season_id = new.id;
    return new;
  end if;

  if old.season_predictions_locked_at is null
     and new.season_predictions_locked_at is not null
     and not exists (
       select 1
       from public.season_prediction_roster_captures capture
       where capture.season_id = new.id
     ) then
    insert into public.season_prediction_roster_captures(
      season_id,
      captured_at,
      capture_reason
    ) values (
      new.id,
      new.season_predictions_locked_at,
      'lock'
    );

    insert into public.season_prediction_roster_members(
      season_id,
      season_player_id,
      category
    )
    select
      player.season_id,
      player.id,
      case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
    from public.season_players player
    where player.season_id = new.id
      and player.is_active
      and not player.is_coach;

    return new;
  end if;

  if old.status is distinct from 'archived'
     and new.status = 'archived'
     and not exists (
       select 1
       from public.season_prediction_roster_captures capture
       where capture.season_id = new.id
     ) then
    insert into public.season_prediction_roster_captures(
      season_id,
      captured_at,
      capture_reason
    ) values (
      new.id,
      now(),
      'archive'
    );

    insert into public.season_prediction_roster_members(
      season_id,
      season_player_id,
      category
    )
    select
      player.season_id,
      player.id,
      case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
    from public.season_players player
    where player.season_id = new.id
      and player.is_active
      and not player.is_coach;
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Classement Buteurs / Clean sheets : effectif actif hors coachs
-- ---------------------------------------------------------------------------

create or replace view public.v_scorer_standings
with (security_invoker = true)
as
select
  stats.season_id,
  stats.season_player_id,
  stats.first_name,
  stats.last_name,
  stats.is_goalkeeper,
  stats.goals,
  stats.clean_sheets
from public.v_player_season_stats stats
join public.season_players player
  on player.id = stats.season_player_id
where stats.is_active
  and not player.is_coach;

-- ---------------------------------------------------------------------------
-- 4. Statistiques joueurs : un coach n'est jamais une ligne joueur
-- ---------------------------------------------------------------------------

create or replace view public.v_statistics_players
with (security_invoker = true)
as
with open_season as (
  select id, name
  from public.seasons
  where status = 'open'
  order by created_at desc
  limit 1
),
prev_ref as (
  select s.id, s.name
  from public.seasons s
  cross join open_season o
  where s.name < o.name
  order by s.name desc
  limit 1
),
app_present as (
  select present.match_id,
         present.season_player_id,
         m.season_id,
         m.score_as_grinta,
         m.score_adverse
  from (
    select match_id, season_player_id from public.match_attendance
    union
    select match_id, season_player_id from public.match_player_stats
    union
    select match_id, season_player_id from public.match_man_of_match
  ) present
  join public.matches m
    on m.id = present.match_id
   and m.status in ('termine', 'archive')
),
app_results as (
  select
    app_present.season_player_id,
    count(*)::integer as matches_played,
    count(*) filter (where app_present.score_as_grinta > app_present.score_adverse)::integer as wins,
    count(*) filter (where app_present.score_as_grinta = app_present.score_adverse)::integer as draws,
    count(*) filter (where app_present.score_as_grinta < app_present.score_adverse)::integer as losses,
    count(*) filter (where app_present.score_adverse = 0)::integer as team_clean_sheets
  from app_present
  group by app_present.season_player_id
),
app_pstats as (
  select
    st.season_player_id,
    coalesce(sum(st.goals), 0::bigint)::integer as goals,
    coalesce(sum(st.assists), 0::bigint)::integer as assists,
    count(*) filter (where st.clean_sheet)::integer as clean_sheets
  from public.match_player_stats st
  join public.matches m
    on m.id = st.match_id
   and m.status in ('termine', 'archive')
  group by st.season_player_id
),
app_mvp as (
  select
    mvp.season_player_id,
    count(distinct mvp.match_id)::integer as hdm
  from public.match_man_of_match mvp
  join public.matches m
    on m.id = mvp.match_id
   and m.status in ('termine', 'archive')
  group by mvp.season_player_id
),
app_season_player as (
  select
    sp.season_id,
    sp.profile_id,
    sp.position as display_order,
    concat_ws(' ', sp.first_name, nullif(sp.last_name, '')) as full_name,
    sp.is_goalkeeper,
    sp.is_active,
    coalesce(r.matches_played, 0) as matches_played,
    coalesce(r.wins, 0) as wins,
    coalesce(r.draws, 0) as draws,
    coalesce(r.losses, 0) as losses,
    coalesce(g.goals, 0) as goals,
    coalesce(g.assists, 0) as assists,
    coalesce(mv.hdm, 0) as hdm,
    coalesce(g.clean_sheets, 0) as clean_sheets,
    coalesce(r.team_clean_sheets, 0) as team_clean_sheets,
    case
      when sp.is_goalkeeper then coalesce(g.clean_sheets, 0)
      else coalesce(g.goals, 0)
    end as ranking_metric
  from public.season_players sp
  left join app_results r on r.season_player_id = sp.id
  left join app_pstats g on g.season_player_id = sp.id
  left join app_mvp mv on mv.season_player_id = sp.id
  where not sp.is_coach
),
prev_has_app as (
  select exists (
    select 1
    from app_season_player asp
    join prev_ref pr on pr.id = asp.season_id
  ) as has_app
),
current_ranked as (
  select
    'current'::text as period_key,
    os.name as period_label,
    rank() over (
      partition by asp.is_goalkeeper
      order by asp.ranking_metric desc
    )::integer as display_rank,
    coalesce(asp.display_order, 9999) as display_order,
    asp.full_name as player_name,
    asp.is_goalkeeper,
    asp.matches_played,
    asp.wins,
    asp.draws,
    asp.losses,
    asp.goals,
    asp.assists,
    asp.hdm,
    asp.clean_sheets,
    asp.profile_id,
    asp.team_clean_sheets
  from app_season_player asp
  join open_season os on os.id = asp.season_id
  where asp.is_active
),
previous_from_app as (
  select
    'previous'::text as period_key,
    pr.name as period_label,
    rank() over (
      partition by asp.is_goalkeeper
      order by asp.ranking_metric desc
    )::integer as display_rank,
    coalesce(asp.display_order, 9999) as display_order,
    asp.full_name as player_name,
    asp.is_goalkeeper,
    asp.matches_played,
    asp.wins,
    asp.draws,
    asp.losses,
    asp.goals,
    asp.assists,
    asp.hdm,
    asp.clean_sheets,
    asp.profile_id,
    asp.team_clean_sheets
  from app_season_player asp
  join prev_ref pr on pr.id = asp.season_id
  cross join prev_has_app ph
  where ph.has_app
),
previous_from_import as (
  select
    'previous'::text as period_key,
    h.season_name as period_label,
    h.display_rank,
    h.display_rank as display_order,
    h.player_name,
    h.is_goalkeeper,
    h.matches_played,
    h.wins,
    h.draws,
    h.losses,
    h.goals,
    0 as assists,
    h.hdm,
    coalesce(h.clean_sheets, 0) as clean_sheets,
    h.profile_id,
    coalesce(h.team_clean_sheets, 0) as team_clean_sheets
  from public.historical_player_statistics h
  cross join prev_has_app ph
  where h.scope = 'previous'
    and not ph.has_app
),
historical_all_time as (
  select
    h.player_name,
    h.profile_id,
    h.is_goalkeeper,
    h.matches_played,
    h.wins,
    h.draws,
    h.losses,
    h.goals,
    h.hdm,
    coalesce(h.clean_sheets, 0) as clean_sheets,
    coalesce(h.team_clean_sheets, 0) as team_clean_sheets
  from public.historical_player_statistics h
  where h.scope = 'all_time'
),
app_all as (
  select
    app_season_player.full_name,
    app_season_player.is_goalkeeper,
    max(app_season_player.profile_id::text)::uuid as profile_id,
    sum(app_season_player.matches_played)::integer as matches_played,
    sum(app_season_player.wins)::integer as wins,
    sum(app_season_player.draws)::integer as draws,
    sum(app_season_player.losses)::integer as losses,
    sum(app_season_player.goals)::integer as goals,
    sum(app_season_player.assists)::integer as assists,
    sum(app_season_player.hdm)::integer as hdm,
    sum(app_season_player.clean_sheets)::integer as clean_sheets,
    sum(app_season_player.team_clean_sheets)::integer as team_clean_sheets
  from app_season_player
  group by app_season_player.full_name, app_season_player.is_goalkeeper
  having sum(app_season_player.matches_played) > 0
),
all_time_combined as (
  select
    coalesce(history.player_name, app.full_name) as player_name,
    coalesce(history.profile_id, app.profile_id) as profile_id,
    coalesce(history.is_goalkeeper, app.is_goalkeeper) as is_goalkeeper,
    coalesce(history.matches_played, 0) + coalesce(app.matches_played, 0) as matches_played,
    coalesce(history.wins, 0) + coalesce(app.wins, 0) as wins,
    coalesce(history.draws, 0) + coalesce(app.draws, 0) as draws,
    coalesce(history.losses, 0) + coalesce(app.losses, 0) as losses,
    coalesce(history.goals, 0) + coalesce(app.goals, 0) as goals,
    coalesce(app.assists, 0) as assists,
    coalesce(history.hdm, 0) + coalesce(app.hdm, 0) as hdm,
    coalesce(history.clean_sheets, 0) + coalesce(app.clean_sheets, 0) as clean_sheets,
    coalesce(history.team_clean_sheets, 0) + coalesce(app.team_clean_sheets, 0) as team_clean_sheets
  from historical_all_time history
  full join app_all app
    on lower(btrim(history.player_name)) = lower(btrim(app.full_name))
   and history.is_goalkeeper = app.is_goalkeeper
),
all_time_ranked as (
  select
    'all_time'::text as period_key,
    'Toutes saisons'::text as period_label,
    rank() over (
      partition by all_time_combined.is_goalkeeper
      order by all_time_combined.matches_played desc,
               all_time_combined.goals desc,
               all_time_combined.player_name
    )::integer as display_rank,
    rank() over (
      partition by all_time_combined.is_goalkeeper
      order by all_time_combined.matches_played desc,
               all_time_combined.goals desc,
               all_time_combined.player_name
    )::integer as display_order,
    all_time_combined.player_name,
    all_time_combined.is_goalkeeper,
    all_time_combined.matches_played,
    all_time_combined.wins,
    all_time_combined.draws,
    all_time_combined.losses,
    all_time_combined.goals,
    all_time_combined.assists,
    all_time_combined.hdm,
    all_time_combined.clean_sheets,
    all_time_combined.profile_id,
    all_time_combined.team_clean_sheets
  from all_time_combined
)
select
  current_ranked.period_key,
  current_ranked.period_label,
  current_ranked.display_rank,
  current_ranked.display_order,
  current_ranked.player_name,
  current_ranked.is_goalkeeper,
  current_ranked.matches_played,
  current_ranked.wins,
  current_ranked.draws,
  current_ranked.losses,
  current_ranked.goals,
  current_ranked.hdm,
  current_ranked.clean_sheets,
  current_ranked.profile_id,
  current_ranked.team_clean_sheets,
  current_ranked.assists
from current_ranked
union all
select
  previous_from_app.period_key,
  previous_from_app.period_label,
  previous_from_app.display_rank,
  previous_from_app.display_order,
  previous_from_app.player_name,
  previous_from_app.is_goalkeeper,
  previous_from_app.matches_played,
  previous_from_app.wins,
  previous_from_app.draws,
  previous_from_app.losses,
  previous_from_app.goals,
  previous_from_app.hdm,
  previous_from_app.clean_sheets,
  previous_from_app.profile_id,
  previous_from_app.team_clean_sheets,
  previous_from_app.assists
from previous_from_app
union all
select
  previous_from_import.period_key,
  previous_from_import.period_label,
  previous_from_import.display_rank,
  previous_from_import.display_order,
  previous_from_import.player_name,
  previous_from_import.is_goalkeeper,
  previous_from_import.matches_played,
  previous_from_import.wins,
  previous_from_import.draws,
  previous_from_import.losses,
  previous_from_import.goals,
  previous_from_import.hdm,
  previous_from_import.clean_sheets,
  previous_from_import.profile_id,
  previous_from_import.team_clean_sheets,
  previous_from_import.assists
from previous_from_import
union all
select
  all_time_ranked.period_key,
  all_time_ranked.period_label,
  all_time_ranked.display_rank,
  all_time_ranked.display_order,
  all_time_ranked.player_name,
  all_time_ranked.is_goalkeeper,
  all_time_ranked.matches_played,
  all_time_ranked.wins,
  all_time_ranked.draws,
  all_time_ranked.losses,
  all_time_ranked.goals,
  all_time_ranked.hdm,
  all_time_ranked.clean_sheets,
  all_time_ranked.profile_id,
  all_time_ranked.team_clean_sheets,
  all_time_ranked.assists
from all_time_ranked;

comment on view public.v_statistics_players is
  'Statistiques joueurs Actuelle/Précédente/Toutes : les membres marqués Coach sont exclus de toutes les statistiques joueur ; la saison courante masque aussi les effectifs inactifs, les périodes historiques conservent toute adhésion joueur ayant participé à un match.';

commit;
