-- Sports-management waitlist rotation, convocation recommendations and late withdrawals.
-- Additive and inert while the sports_management feature flag is disabled.

create type public.sport_convocation_state as enum ('draft', 'published', 'closed');
create type public.sport_convocation_status as enum ('not_applicable', 'convoked', 'not_convoked');
create type public.sport_waitlist_turn_state as enum ('not_applicable', 'pending', 'consumed', 'waived');

alter table public.match_sport_workflows
  add column convocation_state public.sport_convocation_state not null default 'draft',
  add column convocation_version integer not null default 0 check (convocation_version >= 0),
  add column convocation_generated_at timestamptz,
  add column convocation_published_at timestamptz,
  add column late_withdrawal_cutoff_at timestamptz;

alter table public.match_sport_participants
  add column convocation_status public.sport_convocation_status not null default 'not_applicable',
  add column convocation_manual_override boolean not null default false,
  add column waitlist_position_snapshot integer check (waitlist_position_snapshot is null or waitlist_position_snapshot >= 1),
  add column waitlist_recommended_not_convoked boolean not null default false,
  add column waitlist_turn_should_consume boolean not null default false,
  add column waitlist_turn_state public.sport_waitlist_turn_state not null default 'not_applicable',
  add column waitlist_turn_updated_at timestamptz,
  add column promoted_after_withdrawal_at timestamptz,
  add column promoted_from_participant_id uuid references public.match_sport_participants(id) on delete restrict;

create unique index if not exists season_players_id_season_id_uidx
  on public.season_players(id, season_id);

create table public.sport_waitlist_entries (
  season_id uuid not null references public.seasons(id) on delete restrict,
  season_player_id uuid primary key,
  position integer not null check (position >= 1),
  previous_season_attendance_count integer not null default 0
    check (previous_season_attendance_count >= 0),
  previous_season_match_count integer not null default 0
    check (previous_season_match_count >= 0),
  source text not null default 'previous_season_attendance'
    check (source in ('previous_season_attendance', 'new_player', 'manual')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (season_id, position),
  foreign key (season_player_id, season_id)
    references public.season_players(id, season_id) on delete restrict
);

comment on table public.sport_waitlist_entries is
  'Admin-managed permanent waitlist order for one season. Lower position is proposed first for non-convocation.';
comment on column public.sport_waitlist_entries.previous_season_attendance_count is
  'Snapshot used only to initialize the order; administrators retain full manual control.';
comment on column public.match_sport_workflows.late_withdrawal_cutoff_at is
  'Noon Europe/Paris on the calendar day before kickoff. Strictly later withdrawals preserve the promoted player turn consumption.';
comment on column public.match_sport_participants.waitlist_turn_should_consume is
  'Administrator-controlled decision. It may remain true even when the player is finally convoked.';

create index sport_waitlist_entries_season_order_idx
  on public.sport_waitlist_entries(season_id, position);
create index match_sport_participants_convocation_idx
  on public.match_sport_participants(match_id, convocation_status, availability_status)
  where is_eligible;
create index match_sport_participants_pending_turn_idx
  on public.match_sport_participants(match_id, waitlist_turn_state)
  where waitlist_turn_state = 'pending';

alter table public.sport_waitlist_entries enable row level security;

revoke all on table public.sport_waitlist_entries from public, anon, authenticated;
grant select on table public.sport_waitlist_entries to authenticated;
grant select, insert, update on table public.sport_waitlist_entries to service_role;

create policy sport_waitlist_entries_admin_select
on public.sport_waitlist_entries for select to authenticated
using (
  (select private.is_feature_enabled('sports_management'))
  and (select private.is_admin())
);

create or replace function private.resolve_open_sport_season(p_season_id uuid default null)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_season_id uuid;
begin
  perform private.require_sports_management_enabled();

  if p_season_id is not null then
    select season.id into v_season_id
    from public.seasons season
    where season.id = p_season_id;
  else
    select season.id into v_season_id
    from public.seasons season
    where season.status = 'open'
    order by season.name desc, season.created_at desc
    limit 1;
  end if;

  if v_season_id is null then
    raise exception 'Sport season not found' using errcode = 'P0002';
  end if;
  return v_season_id;
end;
$function$;

create or replace function private.ensure_sport_waitlist(
  p_season_id uuid,
  p_actor uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := coalesce(p_actor, (select auth.uid()));
  v_previous_season_id uuid;
  v_previous_match_count integer := 0;
  v_max_position integer := 0;
begin
  perform private.require_sports_management_enabled();

  if v_actor is null or not exists (
    select 1 from public.profiles profile
    where profile.id = v_actor and profile.status = 'active'
  ) then
    select profile.id into v_actor
    from public.profiles profile
    where profile.role = 'admin' and profile.status = 'active'
    order by profile.created_at
    limit 1;
  end if;
  if v_actor is null then
    raise exception 'Active administrator profile required' using errcode = '42501';
  end if;

  perform 1 from public.seasons season where season.id = p_season_id for update;
  if not found then
    raise exception 'Sport season not found' using errcode = 'P0002';
  end if;

  select previous.id into v_previous_season_id
  from public.seasons current
  join public.seasons previous on previous.name < current.name
  where current.id = p_season_id
  order by previous.name desc, previous.created_at desc
  limit 1;

  if v_previous_season_id is not null then
    select count(*)::integer into v_previous_match_count
    from public.matches match
    where match.season_id = v_previous_season_id
      and match.status in ('termine', 'archive');
  end if;

  select coalesce(max(entry.position), 0) into v_max_position
  from public.sport_waitlist_entries entry
  where entry.season_id = p_season_id;

  insert into public.sport_waitlist_entries (
    season_id,
    season_player_id,
    position,
    previous_season_attendance_count,
    previous_season_match_count,
    source,
    created_by,
    updated_by
  )
  select
    p_season_id,
    player.id,
    v_max_position + row_number() over (
      order by
        coalesce(previous_stats.attendance_count, 0) asc,
        player.position asc nulls last,
        lower(player.first_name),
        lower(player.last_name),
        player.id
    )::integer,
    coalesce(previous_stats.attendance_count, 0),
    v_previous_match_count,
    case
      when v_max_position = 0 then 'previous_season_attendance'
      else 'new_player'
    end,
    v_actor,
    v_actor
  from public.season_players player
  join public.profiles profile
    on profile.id = player.profile_id
   and profile.status = 'active'
  left join lateral (
    select count(distinct attendance.match_id)::integer as attendance_count
    from public.season_players previous_player
    join public.match_attendance attendance
      on attendance.season_player_id = previous_player.id
    join public.matches previous_match
      on previous_match.id = attendance.match_id
     and previous_match.status in ('termine', 'archive')
    where v_previous_season_id is not null
      and previous_player.season_id = v_previous_season_id
      and previous_player.profile_id = player.profile_id
  ) previous_stats on true
  where player.season_id = p_season_id
    and player.is_active
    and not exists (
      select 1
      from public.sport_waitlist_entries existing
      where existing.season_player_id = player.id
    )
  order by
    coalesce(previous_stats.attendance_count, 0) asc,
    player.position asc nulls last,
    lower(player.first_name),
    lower(player.last_name),
    player.id;
end;
$function$;

create or replace function private.resequence_sport_waitlist(
  p_season_id uuid,
  p_actor uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  create temporary table if not exists pg_temp.sport_waitlist_ranked (
    season_player_id uuid primary key,
    new_position integer not null
  ) on commit drop;
  truncate table pg_temp.sport_waitlist_ranked;

  insert into pg_temp.sport_waitlist_ranked(season_player_id, new_position)
  select entry.season_player_id,
    row_number() over (order by entry.position, entry.season_player_id)::integer
  from public.sport_waitlist_entries entry
  where entry.season_id = p_season_id;

  update public.sport_waitlist_entries entry
  set position = entry.position + 10000
  where entry.season_id = p_season_id;

  update public.sport_waitlist_entries entry
  set position = ranked.new_position,
      updated_by = p_actor,
      updated_at = now()
  from pg_temp.sport_waitlist_ranked ranked
  where entry.season_player_id = ranked.season_player_id;
end;
$function$;

create or replace function private.finalize_match_waitlist_turns_internal(
  p_match_id uuid,
  p_force boolean default false
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_cutoff timestamptz;
  v_match_status text;
  v_entry record;
  v_max_position integer;
  v_consumed integer := 0;
begin
  perform private.require_sports_management_enabled();

  select match.season_id, workflow.late_withdrawal_cutoff_at, match.status
  into v_season_id, v_cutoff, v_match_status
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of workflow;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  if not p_force
     and v_match_status = 'a_venir'
     and (v_cutoff is null or now() <= v_cutoff) then
    return 0;
  end if;

  perform private.ensure_sport_waitlist(v_season_id, v_actor);

  for v_entry in
    select participant.id as participant_id,
      participant.season_player_id,
      waitlist.position
    from public.match_sport_participants participant
    join public.sport_waitlist_entries waitlist
      on waitlist.season_player_id = participant.season_player_id
    where participant.match_id = p_match_id
      and participant.waitlist_turn_state = 'pending'
      and participant.waitlist_turn_should_consume
    order by waitlist.position, participant.id
    for update of participant, waitlist
  loop
    select coalesce(max(entry.position), 0) + 1
    into v_max_position
    from public.sport_waitlist_entries entry
    where entry.season_id = v_season_id;

    update public.sport_waitlist_entries
    set position = v_max_position,
        source = 'manual',
        updated_by = coalesce(v_actor, updated_by),
        updated_at = now()
    where season_player_id = v_entry.season_player_id;

    update public.match_sport_participants
    set waitlist_turn_state = 'consumed',
        waitlist_turn_updated_at = now(),
        updated_at = now()
    where id = v_entry.participant_id;

    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_entry.participant_id, p_match_id, 'waitlist_turn_consumed',
      jsonb_build_object('position', v_entry.position),
      jsonb_build_object('moved_to_end', true),
      v_actor, case when v_actor is null then 'system' else 'staff' end
    );
    v_consumed := v_consumed + 1;
  end loop;

  if v_consumed > 0 then
    perform private.resequence_sport_waitlist(
      v_season_id,
      coalesce(v_actor, (
        select workflow.updated_by
        from public.match_sport_workflows workflow
        where workflow.match_id = p_match_id
      ))
    );
  end if;

  return v_consumed;
end;
$function$;

create or replace function private.finalize_due_waitlist_turns_for_season(
  p_season_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match record;
  v_total integer := 0;
begin
  perform private.require_sports_management_enabled();

  for v_match in
    select workflow.match_id
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    where match.season_id = p_season_id
      and workflow.convocation_state = 'published'
      and exists (
        select 1 from public.match_sport_participants participant
        where participant.match_id = workflow.match_id
          and participant.waitlist_turn_state = 'pending'
          and participant.waitlist_turn_should_consume
      )
      and (
        match.status <> 'a_venir'
        or (
          workflow.late_withdrawal_cutoff_at is not null
          and now() > workflow.late_withdrawal_cutoff_at
        )
      )
    order by workflow.late_withdrawal_cutoff_at, workflow.match_id
  loop
    v_total := v_total
      + private.finalize_match_waitlist_turns_internal(v_match.match_id, false);
  end loop;
  return v_total;
end;
$function$;

create or replace function private.recompute_match_convocations_internal(
  p_match_id uuid,
  p_reset_overrides boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_limit integer;
  v_available integer;
  v_manual_not_convoked integer;
  v_remaining_exclusions integer;
  v_convoked integer;
  v_not_convoked integer;
  v_over_limit integer;
begin
  perform private.require_sports_management_enabled();

  select match.season_id, workflow.squad_size_limit
  into v_season_id, v_limit
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of workflow;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;

  perform private.finalize_due_waitlist_turns_for_season(v_season_id);
  perform private.ensure_sport_waitlist(v_season_id, v_actor);

  update public.match_sport_participants participant
  set convocation_manual_override = false,
      updated_at = now()
  where participant.match_id = p_match_id
    and p_reset_overrides;

  update public.match_sport_participants participant
  set convocation_status = 'not_applicable',
      convocation_manual_override = false,
      waitlist_position_snapshot = waitlist.position,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = case
        when participant.waitlist_turn_state in ('consumed', 'waived')
          then participant.waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      updated_at = now()
  from public.sport_waitlist_entries waitlist
  where participant.match_id = p_match_id
    and participant.season_player_id = waitlist.season_player_id
    and (
      not participant.is_eligible
      or participant.availability_status <> 'available'
    );

  select count(*)::integer into v_available
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.availability_status = 'available';

  select count(*)::integer into v_manual_not_convoked
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.availability_status = 'available'
    and participant.convocation_manual_override
    and participant.convocation_status = 'not_convoked';

  v_remaining_exclusions := greatest(
    0,
    greatest(0, v_available - v_limit) - v_manual_not_convoked
  );

  with candidates as (
    select participant.id,
      waitlist.position,
      row_number() over (
        order by waitlist.position, participant.id
      ) as wait_rank
    from public.match_sport_participants participant
    join public.sport_waitlist_entries waitlist
      on waitlist.season_player_id = participant.season_player_id
    where participant.match_id = p_match_id
      and participant.is_eligible
      and participant.availability_status = 'available'
      and not participant.convocation_manual_override
  )
  update public.match_sport_participants participant
  set convocation_status = case
        when candidates.wait_rank <= v_remaining_exclusions
          then 'not_convoked'::public.sport_convocation_status
        else 'convoked'::public.sport_convocation_status
      end,
      waitlist_position_snapshot = candidates.position,
      waitlist_recommended_not_convoked =
        candidates.wait_rank <= v_remaining_exclusions,
      waitlist_turn_should_consume =
        candidates.wait_rank <= v_remaining_exclusions,
      waitlist_turn_state = case
        when candidates.wait_rank <= v_remaining_exclusions
          then 'pending'::public.sport_waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      updated_at = now()
  from candidates
  where participant.id = candidates.id;

  update public.match_sport_participants participant
  set waitlist_position_snapshot = waitlist.position,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_state = case
        when participant.waitlist_turn_should_consume
          and participant.waitlist_turn_state not in ('consumed', 'waived')
          then 'pending'::public.sport_waitlist_turn_state
        when not participant.waitlist_turn_should_consume
          and participant.waitlist_turn_state = 'pending'
          then 'waived'::public.sport_waitlist_turn_state
        else participant.waitlist_turn_state
      end,
      updated_at = now()
  from public.sport_waitlist_entries waitlist
  where participant.match_id = p_match_id
    and participant.season_player_id = waitlist.season_player_id
    and participant.is_eligible
    and participant.availability_status = 'available'
    and participant.convocation_manual_override;

  update public.match_sport_workflows
  set convocation_generated_at = now(),
      updated_by = coalesce(v_actor, updated_by),
      updated_at = now()
  where match_id = p_match_id;

  select
    count(*) filter (where participant.convocation_status = 'convoked')::integer,
    count(*) filter (where participant.convocation_status = 'not_convoked')::integer
  into v_convoked, v_not_convoked
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.availability_status = 'available';

  v_over_limit := greatest(0, v_convoked - v_limit);

  return jsonb_build_object(
    'match_id', p_match_id,
    'squad_size_limit', v_limit,
    'available_count', v_available,
    'convoked_count', v_convoked,
    'not_convoked_count', v_not_convoked,
    'over_limit_count', v_over_limit
  );
end;
$function$;

create or replace function private.configure_match_sport_workflow(
  p_match_id uuid,
  p_squad_size_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_kickoff_at timestamptz;
  v_cutoff timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_squad_size_limit is null or p_squad_size_limit < 1 or p_squad_size_limit > 30 then
    raise exception 'Squad size limit must be between 1 and 30' using errcode = '22023';
  end if;

  perform private.sync_match_sport_workflow(p_match_id);

  select match.season_id, match.kickoff_at
  into v_season_id, v_kickoff_at
  from public.matches match
  where match.id = p_match_id
  for update;

  v_cutoff := (
    (
      (v_kickoff_at at time zone 'Europe/Paris')::date - 1
    ) + time '12:00'
  ) at time zone 'Europe/Paris';

  update public.match_sport_workflows
  set squad_size_limit = p_squad_size_limit,
      late_withdrawal_cutoff_at = v_cutoff,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  perform private.ensure_sport_waitlist(v_season_id, v_actor);
  return private.recompute_match_convocations_internal(p_match_id, false);
end;
$function$;

create or replace function private.get_sport_waitlist(p_season_id uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_season_id uuid;
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_season_id := private.resolve_open_sport_season(p_season_id);
  perform private.ensure_sport_waitlist(v_season_id, (select auth.uid()));
  perform private.finalize_due_waitlist_turns_for_season(v_season_id);

  select jsonb_build_object(
    'season_id', season.id,
    'season_name', season.name,
    'entries', coalesce(jsonb_agg(
      jsonb_build_object(
        'season_player_id', player.id,
        'first_name', player.first_name,
        'last_name', player.last_name,
        'position', entry.position,
        'previous_season_attendance_count', entry.previous_season_attendance_count,
        'previous_season_match_count', entry.previous_season_match_count,
        'source', entry.source,
        'updated_at', entry.updated_at
      )
      order by entry.position
    ), '[]'::jsonb)
  )
  into v_result
  from public.seasons season
  left join public.sport_waitlist_entries entry on entry.season_id = season.id
  left join public.season_players player on player.id = entry.season_player_id
  where season.id = v_season_id
  group by season.id, season.name;

  return v_result;
end;
$function$;

create or replace function private.reorder_sport_waitlist(
  p_season_id uuid,
  p_ordered_player_ids uuid[],
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_expected integer;
  v_given integer;
  v_distinct integer;
  v_old_order uuid[];
  v_reason text := nullif(btrim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  v_season_id := private.resolve_open_sport_season(p_season_id);
  perform private.ensure_sport_waitlist(v_season_id, v_actor);

  select count(*)::integer into v_expected
  from public.sport_waitlist_entries entry
  where entry.season_id = v_season_id;

  v_given := coalesce(cardinality(p_ordered_player_ids), 0);
  select count(distinct item)::integer into v_distinct
  from unnest(coalesce(p_ordered_player_ids, '{}'::uuid[])) item;

  if v_given <> v_expected or v_distinct <> v_expected then
    raise exception 'The complete waitlist must be supplied without duplicates'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(p_ordered_player_ids) item
    where not exists (
      select 1 from public.sport_waitlist_entries entry
      where entry.season_id = v_season_id
        and entry.season_player_id = item
    )
  ) then
    raise exception 'Waitlist contains an unknown player' using errcode = '22023';
  end if;

  select array_agg(entry.season_player_id order by entry.position)
  into v_old_order
  from public.sport_waitlist_entries entry
  where entry.season_id = v_season_id;

  update public.sport_waitlist_entries
  set position = position + 10000
  where season_id = v_season_id;

  update public.sport_waitlist_entries entry
  set position = ordered.ordinality::integer,
      source = 'manual',
      updated_by = v_actor,
      updated_at = now()
  from unnest(p_ordered_player_ids) with ordinality
    as ordered(season_player_id, ordinality)
  where entry.season_id = v_season_id
    and entry.season_player_id = ordered.season_player_id;

  insert into private.sport_admin_audit_log (
    action, actor_profile_id, reason, metadata
  ) values (
    'reorder_waitlist', v_actor, v_reason,
    jsonb_build_object(
      'season_id', v_season_id,
      'old_order', to_jsonb(v_old_order),
      'new_order', to_jsonb(p_ordered_player_ids)
    )
  );

  return private.get_sport_waitlist(v_season_id);
end;
$function$;

create or replace function private.get_match_convocations(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.match_sport_workflows workflow
    where workflow.match_id = p_match_id
      and workflow.convocation_state = 'draft'
  ) then
    perform private.recompute_match_convocations_internal(p_match_id, false);
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', opponent.name,
    'kickoff_at', match.kickoff_at,
    'season_id', match.season_id,
    'squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'late_withdrawal_cutoff_at', workflow.late_withdrawal_cutoff_at,
    'available_count', count(*) filter (
      where participant.is_eligible
        and participant.availability_status = 'available'
    ),
    'convoked_count', count(*) filter (
      where participant.is_eligible
        and participant.availability_status = 'available'
        and participant.convocation_status = 'convoked'
    ),
    'not_convoked_count', count(*) filter (
      where participant.is_eligible
        and participant.availability_status = 'available'
        and participant.convocation_status = 'not_convoked'
    ),
    'players', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', player.id,
        'first_name', player.first_name,
        'last_name', player.last_name,
        'availability_status', participant.availability_status,
        'availability_updated_at', participant.availability_updated_at,
        'convocation_status', participant.convocation_status,
        'manual_override', participant.convocation_manual_override,
        'waitlist_position', waitlist.position,
        'waitlist_position_snapshot', participant.waitlist_position_snapshot,
        'recommended_not_convoked', participant.waitlist_recommended_not_convoked,
        'turn_should_consume', participant.waitlist_turn_should_consume,
        'turn_state', participant.waitlist_turn_state,
        'promoted_after_withdrawal_at', participant.promoted_after_withdrawal_at
      )
      order by
        case participant.availability_status
          when 'available' then 0
          when 'no_response' then 1
          when 'absent' then 2
          else 3
        end,
        waitlist.position,
        lower(player.first_name),
        lower(player.last_name)
    ) filter (where participant.id is not null), '[]'::jsonb)
  )
  into v_result
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_participants participant
    on participant.match_id = match.id
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = participant.season_player_id
  where match.id = p_match_id
  group by match.id, opponent.name, workflow.match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

create or replace function private.set_match_convocation(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_turn_should_consume boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_old_status public.sport_convocation_status;
  v_old_consume boolean;
  v_new_status public.sport_convocation_status;
  v_reason text := nullif(btrim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_status not in ('convoked', 'not_convoked') then
    raise exception 'Invalid convocation status' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;
  v_new_status := p_status::public.sport_convocation_status;

  select participant.id, participant.convocation_status,
    participant.waitlist_turn_should_consume
  into v_participant_id, v_old_status, v_old_consume
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.season_player_id = p_season_player_id
    and participant.is_eligible
    and participant.availability_status = 'available'
  for update;

  if not found then
    raise exception 'Available participant not found' using errcode = 'P0002';
  end if;

  update public.match_sport_participants
  set convocation_status = v_new_status,
      convocation_manual_override = true,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = p_turn_should_consume,
      waitlist_turn_state = case
        when p_turn_should_consume then
          case
            when waitlist_turn_state = 'consumed'
              then 'consumed'::public.sport_waitlist_turn_state
            else 'pending'::public.sport_waitlist_turn_state
          end
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where id = v_participant_id;

  update public.match_sport_workflows
  set convocation_version = convocation_version + 1,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into public.match_sport_participant_events (
    participant_id, match_id, event_type, old_value, new_value,
    actor_profile_id, actor_kind
  ) values (
    v_participant_id, p_match_id, 'convocation_overridden',
    jsonb_build_object(
      'status', v_old_status,
      'turn_should_consume', v_old_consume
    ),
    jsonb_build_object(
      'status', v_new_status,
      'turn_should_consume', p_turn_should_consume
    ),
    v_actor, 'staff'
  );

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'override_convocation', v_actor, v_reason,
    jsonb_build_object(
      'season_player_id', p_season_player_id,
      'old_status', v_old_status,
      'new_status', v_new_status,
      'old_turn_should_consume', v_old_consume,
      'new_turn_should_consume', p_turn_should_consume
    )
  );

  return private.get_match_convocations(p_match_id);
end;
$function$;

create or replace function private.publish_match_convocations(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_summary jsonb;
  v_over_limit integer;
  v_unresolved integer;
  v_reason text := nullif(btrim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  v_summary := private.recompute_match_convocations_internal(p_match_id, false);
  v_over_limit := coalesce((v_summary ->> 'over_limit_count')::integer, 0);

  select count(*)::integer into v_unresolved
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.availability_status = 'available'
    and participant.convocation_status = 'not_applicable';

  if v_over_limit > 0 then
    raise exception 'Too many convoked players for the configured limit'
      using errcode = '22023';
  end if;
  if v_unresolved > 0 then
    raise exception 'Every available player needs a convocation decision'
      using errcode = '22023';
  end if;

  update public.match_sport_workflows
  set convocation_state = 'published',
      convocation_version = convocation_version + 1,
      convocation_published_at = coalesce(convocation_published_at, now()),
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  update public.match_sport_participants
  set waitlist_turn_state = case
        when waitlist_turn_should_consume then
          case
            when waitlist_turn_state = 'consumed'
              then 'consumed'::public.sport_waitlist_turn_state
            else 'pending'::public.sport_waitlist_turn_state
          end
        else
          case
            when waitlist_turn_state = 'consumed'
              then 'consumed'::public.sport_waitlist_turn_state
            else 'waived'::public.sport_waitlist_turn_state
          end
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where match_id = p_match_id
    and is_eligible
    and availability_status = 'available';

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'publish_convocations', v_actor, v_reason, v_summary
  );

  return private.get_match_convocations(p_match_id);
end;
$function$;

create or replace function private.handle_convoked_withdrawal(
  p_match_id uuid,
  p_participant_id uuid,
  p_actor uuid,
  p_actor_kind text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_cutoff timestamptz;
  v_convocation_state public.sport_convocation_state;
  v_old_convocation public.sport_convocation_status;
  v_candidate_id uuid;
  v_candidate_season_player_id uuid;
  v_late boolean;
begin
  select workflow.late_withdrawal_cutoff_at,
    workflow.convocation_state,
    participant.convocation_status
  into v_cutoff, v_convocation_state, v_old_convocation
  from public.match_sport_workflows workflow
  join public.match_sport_participants participant
    on participant.match_id = workflow.match_id
  where workflow.match_id = p_match_id
    and participant.id = p_participant_id
  for update of workflow, participant;

  if not found
     or v_convocation_state <> 'published'
     or v_old_convocation <> 'convoked' then
    return null;
  end if;

  v_late := v_cutoff is not null and now() > v_cutoff;
  if v_late then
    perform private.finalize_match_waitlist_turns_internal(p_match_id, false);
  end if;

  update public.match_sport_participants
  set convocation_status = 'not_applicable',
      convocation_manual_override = false,
      updated_at = now()
  where id = p_participant_id;

  select candidate.id, candidate.season_player_id
  into v_candidate_id, v_candidate_season_player_id
  from public.match_sport_participants candidate
  join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = candidate.season_player_id
  where candidate.match_id = p_match_id
    and candidate.is_eligible
    and candidate.availability_status = 'available'
    and candidate.convocation_status = 'not_convoked'
  order by waitlist.position, candidate.id
  limit 1
  for update of candidate;

  if v_candidate_id is null then
    return null;
  end if;

  update public.match_sport_participants
  set convocation_status = 'convoked',
      convocation_manual_override = true,
      promoted_after_withdrawal_at = now(),
      promoted_from_participant_id = p_participant_id,
      waitlist_turn_should_consume = case
        when v_late then waitlist_turn_should_consume
        else false
      end,
      waitlist_turn_state = case
        when v_late then waitlist_turn_state
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where id = v_candidate_id;

  update public.match_sport_workflows
  set convocation_version = convocation_version + 1,
      updated_by = coalesce(p_actor, updated_by),
      updated_at = now()
  where match_id = p_match_id;

  insert into public.match_sport_participant_events (
    participant_id, match_id, event_type, old_value, new_value,
    actor_profile_id, actor_kind
  ) values
  (
    p_participant_id, p_match_id, 'convoked_player_withdrew',
    jsonb_build_object('convocation_status', 'convoked'),
    jsonb_build_object('convocation_status', 'not_applicable'),
    p_actor, p_actor_kind
  ),
  (
    v_candidate_id, p_match_id, 'waitlisted_player_promoted',
    jsonb_build_object('convocation_status', 'not_convoked'),
    jsonb_build_object(
      'convocation_status', 'convoked',
      'late_withdrawal', v_late,
      'turn_still_consumed', v_late
    ),
    p_actor, p_actor_kind
  );

  return v_candidate_season_player_id;
end;
$function$;

create or replace function private.set_my_match_availability(
  p_match_id uuid,
  p_status text,
  p_private_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_old_status public.sport_availability_status;
  v_old_comment text;
  v_new_status public.sport_availability_status;
  v_new_comment text := nullif(btrim(p_private_comment), '');
  v_workflow_state public.sport_availability_state;
  v_opens_at timestamptz;
  v_kickoff_at timestamptz;
  v_composition_state public.sport_composition_state;
  v_convocation_state public.sport_convocation_state;
  v_changed boolean;
  v_promoted_player_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('available', 'absent') then
    raise exception 'Availability status must be available or absent' using errcode = '22023';
  end if;

  v_new_status := p_status::public.sport_availability_status;
  if v_new_status = 'available' then v_new_comment := null; end if;
  if v_new_comment is not null and char_length(v_new_comment) > 500 then
    raise exception 'Availability comment cannot exceed 500 characters' using errcode = '22023';
  end if;

  select participant.id, participant.availability_status,
    participant.availability_comment_private, workflow.availability_state,
    workflow.availability_opens_at, workflow.composition_state,
    workflow.convocation_state, match.kickoff_at
  into v_participant_id, v_old_status, v_old_comment, v_workflow_state,
    v_opens_at, v_composition_state, v_convocation_state, v_kickoff_at
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id
    and participant.is_eligible
    and player.profile_id = v_actor
  for update of participant, workflow;

  if not found then
    raise exception 'Eligible match participant not found' using errcode = 'P0002';
  end if;
  if now() < v_opens_at then
    raise exception 'Availability window is not open yet' using errcode = '22023';
  end if;
  if now() >= v_kickoff_at then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  if v_workflow_state = 'pending' then
    update public.match_sport_workflows workflow
    set availability_state = 'open',
        availability_opened_at = coalesce(workflow.availability_opened_at, now()),
        updated_by = v_actor,
        updated_at = now()
    where workflow.match_id = p_match_id;
  elsif v_workflow_state <> 'open' then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  v_changed := v_old_status is distinct from v_new_status
    or v_old_comment is distinct from v_new_comment;

  if v_changed then
    update public.match_sport_participants participant
    set availability_status = v_new_status,
        availability_comment_private = v_new_comment,
        availability_updated_at = now(),
        availability_updated_by = v_actor,
        updated_at = now()
    where participant.id = v_participant_id;

    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_participant_id, p_match_id, 'availability_changed',
      jsonb_build_object('status', v_old_status, 'private_comment', v_old_comment),
      jsonb_build_object('status', v_new_status, 'private_comment', v_new_comment),
      v_actor, 'player'
    );

    if v_convocation_state = 'published'
       and v_old_status = 'available'
       and v_new_status = 'absent' then
      v_promoted_player_id := private.handle_convoked_withdrawal(
        p_match_id, v_participant_id, v_actor, 'player'
      );
    elsif v_convocation_state = 'published'
       and v_old_status = 'absent'
       and v_new_status = 'available' then
      update public.match_sport_participants
      set convocation_status = 'not_convoked',
          convocation_manual_override = false,
          waitlist_turn_should_consume = false,
          waitlist_turn_state = 'waived',
          waitlist_turn_updated_at = now(),
          updated_at = now()
      where id = v_participant_id;
    else
      perform private.recompute_match_convocations_internal(p_match_id, false);
    end if;
  end if;

  return jsonb_build_object(
    'match_id', p_match_id,
    'participant_id', v_participant_id,
    'availability_status', v_new_status,
    'private_comment', v_new_comment,
    'changed', v_changed,
    'promoted_season_player_id', v_promoted_player_id,
    'composition_already_published',
      v_composition_state in ('published', 'updated', 'closed')
  );
end;
$function$;

create or replace function private.override_match_availability(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_private_comment text default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_old_status public.sport_availability_status;
  v_old_comment text;
  v_new_status public.sport_availability_status;
  v_new_comment text := nullif(btrim(p_private_comment), '');
  v_reason text := nullif(btrim(p_reason), '');
  v_workflow_state public.sport_availability_state;
  v_opens_at timestamptz;
  v_kickoff_at timestamptz;
  v_convocation_state public.sport_convocation_state;
  v_changed boolean;
  v_promoted_player_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('no_response', 'available', 'absent') then
    raise exception 'Invalid availability override status' using errcode = '22023';
  end if;
  if v_reason is null then
    raise exception 'Override reason is required' using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'Override reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  v_new_status := p_status::public.sport_availability_status;
  if v_new_status <> 'absent' then v_new_comment := null; end if;
  if v_new_comment is not null and char_length(v_new_comment) > 500 then
    raise exception 'Availability comment cannot exceed 500 characters' using errcode = '22023';
  end if;

  select participant.id, participant.availability_status,
    participant.availability_comment_private, workflow.availability_state,
    workflow.availability_opens_at, workflow.convocation_state, match.kickoff_at
  into v_participant_id, v_old_status, v_old_comment, v_workflow_state,
    v_opens_at, v_convocation_state, v_kickoff_at
  from public.match_sport_participants participant
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id
    and participant.season_player_id = p_season_player_id
    and participant.is_eligible
  for update of participant, workflow;

  if not found then
    raise exception 'Eligible match participant not found' using errcode = 'P0002';
  end if;
  if now() < v_opens_at then
    raise exception 'Availability window is not open yet' using errcode = '22023';
  end if;
  if now() >= v_kickoff_at then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  if v_workflow_state = 'pending' then
    update public.match_sport_workflows workflow
    set availability_state = 'open',
        availability_opened_at = coalesce(workflow.availability_opened_at, now()),
        updated_by = v_actor,
        updated_at = now()
    where workflow.match_id = p_match_id;
  elsif v_workflow_state <> 'open' then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  v_changed := v_old_status is distinct from v_new_status
    or v_old_comment is distinct from v_new_comment;

  if v_changed then
    update public.match_sport_participants participant
    set availability_status = v_new_status,
        availability_comment_private = v_new_comment,
        availability_updated_at = now(),
        availability_updated_by = v_actor,
        updated_at = now()
    where participant.id = v_participant_id;

    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_participant_id, p_match_id, 'availability_changed',
      jsonb_build_object('status', v_old_status, 'private_comment', v_old_comment),
      jsonb_build_object('status', v_new_status, 'private_comment', v_new_comment),
      v_actor, 'staff'
    );

    if v_convocation_state = 'published'
       and v_old_status = 'available'
       and v_new_status = 'absent' then
      v_promoted_player_id := private.handle_convoked_withdrawal(
        p_match_id, v_participant_id, v_actor, 'staff'
      );
    elsif v_convocation_state = 'published'
       and v_old_status = 'absent'
       and v_new_status = 'available' then
      update public.match_sport_participants
      set convocation_status = 'not_convoked',
          convocation_manual_override = false,
          waitlist_turn_should_consume = false,
          waitlist_turn_state = 'waived',
          waitlist_turn_updated_at = now(),
          updated_at = now()
      where id = v_participant_id;
    else
      perform private.recompute_match_convocations_internal(p_match_id, false);
    end if;

    insert into private.sport_admin_audit_log (
      match_id, action, actor_profile_id, reason, metadata
    ) values (
      p_match_id, 'override_availability', v_actor, v_reason,
      jsonb_build_object(
        'participant_id', v_participant_id,
        'season_player_id', p_season_player_id,
        'old_status', v_old_status,
        'new_status', v_new_status,
        'promoted_season_player_id', v_promoted_player_id
      )
    );
  end if;

  return jsonb_build_object(
    'match_id', p_match_id,
    'participant_id', v_participant_id,
    'availability_status', v_new_status,
    'private_comment', v_new_comment,
    'changed', v_changed,
    'promoted_season_player_id', v_promoted_player_id
  );
end;
$function$;

create or replace function private.get_my_match_availability(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', participant.match_id,
    'participant_id', participant.id,
    'season_player_id', participant.season_player_id,
    'is_eligible', participant.is_eligible,
    'availability_status', participant.availability_status,
    'private_comment', participant.availability_comment_private,
    'availability_updated_at', participant.availability_updated_at,
    'availability_state', case
      when now() >= match.kickoff_at then 'closed'
      when now() >= workflow.availability_opens_at
        and workflow.availability_state = 'pending' then 'open'
      else workflow.availability_state::text
    end,
    'availability_opens_at', workflow.availability_opens_at,
    'kickoff_at', match.kickoff_at,
    'can_respond', participant.is_eligible
      and now() >= workflow.availability_opens_at
      and now() < match.kickoff_at
      and workflow.availability_state <> 'closed',
    'composition_state', workflow.composition_state,
    'convocation_state', workflow.convocation_state,
    'convocation_status', case
      when workflow.convocation_state = 'published'
        then participant.convocation_status::text
      else null
    end
  ) into v_result
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id and player.profile_id = v_actor;

  if v_result is null then
    raise exception 'Match participant not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

create or replace function private.create_match_with_sport_limit(
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_squad_size_limit integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_match_id := public.create_match_with_odds(
    p_season_id, p_opponent_id, p_match_date, p_match_time,
    p_location, p_win, p_draw, p_loss
  );
  perform private.configure_match_sport_workflow(v_match_id, p_squad_size_limit);
  return v_match_id;
end;
$function$;

create or replace function private.update_match_with_sport_limit(
  p_match_id uuid,
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_status text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_squad_size_limit integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  perform public.update_match_with_odds(
    p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
    p_location, p_status, p_win, p_draw, p_loss
  );
  if p_status = 'a_venir' then
    perform private.configure_match_sport_workflow(p_match_id, p_squad_size_limit);
  else
    update public.match_sport_workflows
    set availability_state = 'closed',
        convocation_state = 'closed',
        updated_by = (select auth.uid()),
        updated_at = now()
    where match_id = p_match_id;
    perform private.finalize_match_waitlist_turns_internal(p_match_id, true);
  end if;
  return true;
end;
$function$;

create or replace function public.admin_get_sport_waitlist(p_season_id uuid default null)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.get_sport_waitlist(p_season_id); $function$;

create or replace function public.admin_reorder_sport_waitlist(
  p_season_id uuid,
  p_ordered_player_ids uuid[],
  p_reason text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.reorder_sport_waitlist(
    p_season_id, p_ordered_player_ids, p_reason
  );
$function$;

create or replace function public.admin_configure_match_sport_workflow(
  p_match_id uuid,
  p_squad_size_limit integer
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.configure_match_sport_workflow(
    p_match_id, p_squad_size_limit
  );
$function$;

create or replace function public.admin_get_match_convocations(p_match_id uuid)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.get_match_convocations(p_match_id); $function$;

create or replace function public.admin_recompute_match_convocations(
  p_match_id uuid,
  p_reset_overrides boolean default false
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.recompute_match_convocations_internal(
    p_match_id, p_reset_overrides
  );
$function$;

create or replace function public.admin_set_match_convocation(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_turn_should_consume boolean,
  p_reason text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.set_match_convocation(
    p_match_id, p_season_player_id, p_status,
    p_turn_should_consume, p_reason
  );
$function$;

create or replace function public.admin_publish_match_convocations(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.publish_match_convocations(p_match_id, p_reason);
$function$;

create or replace function public.admin_finalize_match_waitlist_turns(
  p_match_id uuid
)
returns integer language plpgsql volatile security invoker set search_path = ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.finalize_match_waitlist_turns_internal(p_match_id, false);
end;
$function$;

create or replace function public.create_match_with_odds_and_sport_limit(
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_squad_size_limit integer
)
returns uuid language sql volatile security invoker set search_path = ''
as $function$
  select private.create_match_with_sport_limit(
    p_season_id, p_opponent_id, p_match_date, p_match_time,
    p_location, p_win, p_draw, p_loss, p_squad_size_limit
  );
$function$;

create or replace function public.update_match_with_odds_and_sport_limit(
  p_match_id uuid,
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_status text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_squad_size_limit integer
)
returns boolean language sql volatile security invoker set search_path = ''
as $function$
  select private.update_match_with_sport_limit(
    p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
    p_location, p_status, p_win, p_draw, p_loss, p_squad_size_limit
  );
$function$;

revoke execute on function private.resolve_open_sport_season(uuid) from public, anon;
revoke execute on function private.ensure_sport_waitlist(uuid, uuid) from public, anon;
revoke execute on function private.resequence_sport_waitlist(uuid, uuid) from public, anon;
revoke execute on function private.finalize_match_waitlist_turns_internal(uuid, boolean) from public, anon;
revoke execute on function private.finalize_due_waitlist_turns_for_season(uuid) from public, anon;
revoke execute on function private.recompute_match_convocations_internal(uuid, boolean) from public, anon;
revoke execute on function private.configure_match_sport_workflow(uuid, integer) from public, anon;
revoke execute on function private.get_sport_waitlist(uuid) from public, anon;
revoke execute on function private.reorder_sport_waitlist(uuid, uuid[], text) from public, anon;
revoke execute on function private.get_match_convocations(uuid) from public, anon;
revoke execute on function private.set_match_convocation(uuid, uuid, text, boolean, text) from public, anon;
revoke execute on function private.publish_match_convocations(uuid, text) from public, anon;
revoke execute on function private.handle_convoked_withdrawal(uuid, uuid, uuid, text) from public, anon;
revoke execute on function private.create_match_with_sport_limit(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric, integer) from public, anon;
revoke execute on function private.update_match_with_sport_limit(uuid, uuid, uuid, date, time without time zone, text, text, numeric, numeric, numeric, integer) from public, anon;

grant execute on function private.resolve_open_sport_season(uuid) to authenticated, service_role;
grant execute on function private.ensure_sport_waitlist(uuid, uuid) to authenticated, service_role;
grant execute on function private.resequence_sport_waitlist(uuid, uuid) to authenticated, service_role;
grant execute on function private.finalize_match_waitlist_turns_internal(uuid, boolean) to authenticated, service_role;
grant execute on function private.finalize_due_waitlist_turns_for_season(uuid) to authenticated, service_role;
grant execute on function private.recompute_match_convocations_internal(uuid, boolean) to authenticated, service_role;
grant execute on function private.configure_match_sport_workflow(uuid, integer) to authenticated, service_role;
grant execute on function private.get_sport_waitlist(uuid) to authenticated, service_role;
grant execute on function private.reorder_sport_waitlist(uuid, uuid[], text) to authenticated, service_role;
grant execute on function private.get_match_convocations(uuid) to authenticated, service_role;
grant execute on function private.set_match_convocation(uuid, uuid, text, boolean, text) to authenticated, service_role;
grant execute on function private.publish_match_convocations(uuid, text) to authenticated, service_role;
grant execute on function private.handle_convoked_withdrawal(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function private.create_match_with_sport_limit(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric, integer) to authenticated, service_role;
grant execute on function private.update_match_with_sport_limit(uuid, uuid, uuid, date, time without time zone, text, text, numeric, numeric, numeric, integer) to authenticated, service_role;

revoke execute on function public.admin_get_sport_waitlist(uuid) from public, anon;
revoke execute on function public.admin_reorder_sport_waitlist(uuid, uuid[], text) from public, anon;
revoke execute on function public.admin_configure_match_sport_workflow(uuid, integer) from public, anon;
revoke execute on function public.admin_get_match_convocations(uuid) from public, anon;
revoke execute on function public.admin_recompute_match_convocations(uuid, boolean) from public, anon;
revoke execute on function public.admin_set_match_convocation(uuid, uuid, text, boolean, text) from public, anon;
revoke execute on function public.admin_publish_match_convocations(uuid, text) from public, anon;
revoke execute on function public.admin_finalize_match_waitlist_turns(uuid) from public, anon;
revoke execute on function public.create_match_with_odds_and_sport_limit(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric, integer) from public, anon;
revoke execute on function public.update_match_with_odds_and_sport_limit(uuid, uuid, uuid, date, time without time zone, text, text, numeric, numeric, numeric, integer) from public, anon;

grant execute on function public.admin_get_sport_waitlist(uuid) to authenticated, service_role;
grant execute on function public.admin_reorder_sport_waitlist(uuid, uuid[], text) to authenticated, service_role;
grant execute on function public.admin_configure_match_sport_workflow(uuid, integer) to authenticated, service_role;
grant execute on function public.admin_get_match_convocations(uuid) to authenticated, service_role;
grant execute on function public.admin_recompute_match_convocations(uuid, boolean) to authenticated, service_role;
grant execute on function public.admin_set_match_convocation(uuid, uuid, text, boolean, text) to authenticated, service_role;
grant execute on function public.admin_publish_match_convocations(uuid, text) to authenticated, service_role;
grant execute on function public.admin_finalize_match_waitlist_turns(uuid) to authenticated, service_role;
grant execute on function public.create_match_with_odds_and_sport_limit(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric, integer) to authenticated, service_role;
grant execute on function public.update_match_with_odds_and_sport_limit(uuid, uuid, uuid, date, time without time zone, text, text, numeric, numeric, numeric, integer) to authenticated, service_role;

comment on function public.admin_get_sport_waitlist(uuid) is
  'Returns the administrator-managed waitlist initialized from previous-season attendance.';
comment on function public.admin_reorder_sport_waitlist(uuid, uuid[], text) is
  'Atomically replaces the complete waitlist order and writes an administrator audit record.';
comment on function public.admin_get_match_convocations(uuid) is
  'Returns the live recommendation and every administrator override for one match.';
comment on function public.admin_publish_match_convocations(uuid, text) is
  'Publishes the current convocation list without rotating pending waitlist turns before the cutoff.';
comment on function public.admin_finalize_match_waitlist_turns(uuid) is
  'Consumes pending turns only strictly after the previous-day noon Europe/Paris cutoff.';
