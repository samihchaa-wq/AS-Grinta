-- Freeze the season-prediction roster at lock/archive time so later roster
-- changes cannot invalidate or expand a completed prediction grid.

create table if not exists public.season_prediction_roster_captures (
  season_id uuid primary key
    references public.seasons(id) on delete cascade,
  captured_at timestamptz not null default now(),
  capture_reason text not null
    check (capture_reason in ('lock', 'archive', 'backfill'))
);

create table if not exists public.season_prediction_roster_members (
  season_id uuid not null
    references public.season_prediction_roster_captures(season_id)
    on delete cascade,
  season_player_id uuid not null
    references public.season_players(id) on delete cascade,
  category text not null
    check (category in ('buts', 'clean_sheets')),
  primary key (season_id, season_player_id)
);

alter table public.season_prediction_roster_captures enable row level security;
alter table public.season_prediction_roster_members enable row level security;

drop policy if exists season_prediction_roster_captures_read
  on public.season_prediction_roster_captures;
create policy season_prediction_roster_captures_read
  on public.season_prediction_roster_captures
  for select to authenticated
  using (public.is_active_profile());

drop policy if exists season_prediction_roster_members_read
  on public.season_prediction_roster_members;
create policy season_prediction_roster_members_read
  on public.season_prediction_roster_members
  for select to authenticated
  using (public.is_active_profile());

revoke all on table public.season_prediction_roster_captures
  from public, anon, authenticated;
revoke all on table public.season_prediction_roster_members
  from public, anon, authenticated;
grant select on table public.season_prediction_roster_captures to authenticated;
grant select on table public.season_prediction_roster_members to authenticated;
grant all on table public.season_prediction_roster_captures to service_role;
grant all on table public.season_prediction_roster_members to service_role;

-- Existing locked/archived seasons did not have a snapshot. Preserve the
-- current contract without inventing roster members: active members are kept,
-- and an inactive member is kept only when a filled season prediction proves
-- they previously belonged to an actual submitted grid.
insert into public.season_prediction_roster_captures(
  season_id, captured_at, capture_reason
)
select
  season.id,
  coalesce(season.season_predictions_locked_at, now()),
  'backfill'
from public.seasons season
where season.season_predictions_locked_at is not null
   or season.status = 'archived'
on conflict (season_id) do nothing;

insert into public.season_prediction_roster_members(
  season_id, season_player_id, category
)
select
  player.season_id,
  player.id,
  case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
from public.season_players player
join public.season_prediction_roster_captures capture
  on capture.season_id = player.season_id
where player.is_active
   or exists (
     select 1
     from public.season_predictions prediction
     where prediction.season_id = player.season_id
       and prediction.season_player_id = player.id
       and prediction.is_filled
       and prediction.category =
         case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
   )
on conflict (season_id, season_player_id) do nothing;

create or replace function private.sync_season_prediction_roster_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- Unlocking or reopening clears the previous contract so the next lock can
  -- capture the then-current active roster.
  if new.season_predictions_locked_at is null
     and new.status <> 'archived'
     and (
       old.season_predictions_locked_at is not null
       or old.status = 'archived'
     )
  then
    delete from public.season_prediction_roster_captures
    where season_id = new.id;
    return new;
  end if;

  -- First lock of an open season captures exactly the active roster.
  if old.season_predictions_locked_at is null
     and new.season_predictions_locked_at is not null
  then
    delete from public.season_prediction_roster_captures
    where season_id = new.id;

    insert into public.season_prediction_roster_captures(
      season_id, captured_at, capture_reason
    )
    values (new.id, new.season_predictions_locked_at, 'lock');

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

  -- A season can also be archived without an explicit prediction lock. In
  -- that case capture the active roster once, and never recapture if a prior
  -- lock already created the historical contract.
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
    )
    values (new.id, now(), 'archive');

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

drop trigger if exists trg_sync_season_prediction_roster_snapshot
  on public.seasons;
create trigger trg_sync_season_prediction_roster_snapshot
after update of status, season_predictions_locked_at
on public.seasons
for each row
execute function private.sync_season_prediction_roster_snapshot();

revoke execute on function private.sync_season_prediction_roster_snapshot()
  from public, anon, authenticated;

create or replace function private.guard_season_prediction_roster_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    -- Direct roster deletion would rewrite the prediction contract. Cascading
    -- deletion of the whole season is still allowed.
    if pg_trigger_depth() = 1
       and exists (
         select 1
         from public.season_prediction_roster_members member
         where member.season_player_id = old.id
       )
    then
      raise exception
        'Season prediction roster is frozen; archived prediction members cannot be deleted'
        using errcode = '23514';
    end if;
    return old;
  end if;

  if exists (
    select 1
    from public.season_prediction_roster_members member
    where member.season_player_id = old.id
  )
  and (
    new.season_id is distinct from old.season_id
    or new.is_goalkeeper is distinct from old.is_goalkeeper
  )
  then
    raise exception
      'Season prediction roster is frozen; season/category cannot be changed'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_guard_season_prediction_roster_member
  on public.season_players;
create trigger trg_guard_season_prediction_roster_member
before update of season_id, is_goalkeeper or delete
on public.season_players
for each row
execute function private.guard_season_prediction_roster_member();

revoke execute on function private.guard_season_prediction_roster_member()
  from public, anon, authenticated;

create or replace view public.v_season_prediction_points
with (security_invoker = true)
as
with eligible_seasons as (
  select
    season.id,
    season.status,
    exists (
      select 1
      from public.season_prediction_roster_captures capture
      where capture.season_id = season.id
    ) as has_roster_snapshot
  from public.seasons season
  where season.season_predictions_locked_at is not null
     or season.status = 'archived'
),
prediction_roster as (
  select
    member.season_id,
    member.season_player_id,
    member.category
  from public.season_prediction_roster_members member
  join eligible_seasons season
    on season.id = member.season_id
   and season.has_roster_snapshot

  union all

  -- Legacy fallback only for an eligible season that predates snapshot
  -- capture. New locks/archives always create a capture header, including an
  -- intentionally empty roster.
  select
    player.season_id,
    player.id as season_player_id,
    case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
  from public.season_players player
  join eligible_seasons season
    on season.id = player.season_id
   and not season.has_roster_snapshot
),
expected_predictions as (
  select roster.season_id, count(*) as expected_count
  from prediction_roster roster
  group by roster.season_id
),
predictor_completion as (
  select
    prediction.season_id,
    prediction.predictor_profile_id,
    count(*) filter (
      where prediction.is_filled
        and prediction.category = roster.category
    ) as filled_count
  from public.season_predictions prediction
  join prediction_roster roster
    on roster.season_id = prediction.season_id
   and roster.season_player_id = prediction.season_player_id
   and roster.category = prediction.category
  group by prediction.season_id, prediction.predictor_profile_id
),
eligible_predictors as (
  select completion.season_id, completion.predictor_profile_id
  from predictor_completion completion
  join expected_predictions expected
    on expected.season_id = completion.season_id
  where expected.expected_count > 0
    and completion.filled_count = expected.expected_count
),
base as (
  select
    prediction.id,
    prediction.season_id,
    prediction.predictor_profile_id,
    prediction.season_player_id,
    prediction.category,
    prediction.predicted_value_30,
    case prediction.category
      when 'buts' then stats.goals
      when 'clean_sheets' then stats.clean_sheets
      else 0
    end as metric,
    season.status as season_status,
    match_count.matches_played
  from public.season_predictions prediction
  join eligible_predictors eligible
    on eligible.season_id = prediction.season_id
   and eligible.predictor_profile_id = prediction.predictor_profile_id
  join prediction_roster roster
    on roster.season_id = prediction.season_id
   and roster.season_player_id = prediction.season_player_id
   and roster.category = prediction.category
  join eligible_seasons season
    on season.id = prediction.season_id
  join public.v_player_season_stats stats
    on stats.season_player_id = prediction.season_player_id
  left join public.v_season_match_count match_count
    on match_count.season_id = prediction.season_id
  where prediction.is_filled
),
targeted as (
  select
    base.*,
    case
      when base.season_status = 'archived' then base.metric::numeric
      when coalesce(base.matches_played, 0) > 0
        then round(base.metric::numeric * 30.0 / base.matches_played::numeric)
      else null::numeric
    end as target
  from base
),
ranked as (
  select
    targeted.id,
    targeted.season_id,
    targeted.predictor_profile_id,
    targeted.season_player_id,
    targeted.category,
    targeted.predicted_value_30,
    targeted.target,
    count(*) over (
      partition by targeted.season_id,
                   targeted.season_player_id,
                   targeted.category
    ) as participant_count,
    rank() over (
      partition by targeted.season_id,
                   targeted.season_player_id,
                   targeted.category
      order by abs(targeted.predicted_value_30::numeric - targeted.target)
    ) as proximity_rank
  from targeted
  where targeted.target is not null
)
select
  id,
  season_id,
  predictor_profile_id,
  season_player_id,
  category,
  (
    (participant_count - proximity_rank + 1)
    * 3
    * case when predicted_value_30::numeric = target then 2 else 1 end
  )::integer as points
from ranked;

grant select on public.v_season_prediction_points to authenticated;
