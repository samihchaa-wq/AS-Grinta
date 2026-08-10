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
;
