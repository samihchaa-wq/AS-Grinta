-- A player added after kickoff enters the Live lineup through the bench.
-- private.match_live_snapshot() uses starting_lineup_snapshot as the baseline
-- for the "times on bench" counter, so those late additions must be added to
-- that snapshot exactly once.
--
-- Do this at the public add-player boundary instead of with a generic trigger
-- on match_composition_entries: save_match_live_lineup rewrites every entry on
-- each save, and a generic INSERT trigger could therefore double-count a
-- normal substitution.

create or replace function public.coach_add_match_live_players(
  p_match_id uuid,
  p_players jsonb,
  p_reason text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_state public.match_live_state;
  v_before_selected uuid[];
  v_added_bench_baseline jsonb;
  v_result jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  -- Lock the session before taking the before/after lineup snapshot so another
  -- Live action cannot interleave between the two observations.
  select session.state
  into v_state
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  select coalesce(
    array_agg(entry.participant_id),
    array[]::uuid[]
  )
  into v_before_selected
  from public.match_composition_entries entry
  where entry.match_id = p_match_id
    and entry.zone in ('field', 'bench');

  v_result := private.add_match_live_players(p_match_id, p_players, p_reason);

  -- Before kickoff confirm_start_match_live snapshots the whole starting bench.
  -- Once the clock has started, only participants newly selected by THIS call
  -- receive the extra baseline entry. A normal field -> bench substitution is
  -- therefore still counted solely by its match_live_event.
  if v_state in ('running', 'paused', 'halftime') then
    select coalesce(
      jsonb_object_agg(entry.participant_id::text, 'bench'::text),
      '{}'::jsonb
    )
    into v_added_bench_baseline
    from public.match_composition_entries entry
    where entry.match_id = p_match_id
      and entry.zone = 'bench'
      and not (entry.participant_id = any(v_before_selected));

    if v_added_bench_baseline <> '{}'::jsonb then
      update public.match_live_sessions session
      set starting_lineup_snapshot =
            coalesce(session.starting_lineup_snapshot, '{}'::jsonb)
            || v_added_bench_baseline,
          updated_at = now()
      where session.match_id = p_match_id;

      -- private.add_match_live_players returned the snapshot from immediately
      -- before the baseline repair. Return the refreshed snapshot to the UI so
      -- the new player's badge is visible without an extra manual reload.
      v_result := private.match_live_snapshot(p_match_id);
    end if;
  end if;

  return v_result;
end;
$function$;

comment on function public.coach_add_match_live_players(uuid, jsonb, text) is
  'Adds players to an open Live lineup. Players introduced after kickoff enter through the bench and immediately receive one bench-presence baseline.';

-- Conservative repair for sessions created before this fix: a currently
-- benched participant missing from the kickoff snapshot can safely receive the
-- baseline only when they have no substitution event at all. This repairs the
-- observed late-add/no-badge case without turning a normal player_out event
-- into a double count.
with missing_bench as (
  select
    session.match_id,
    jsonb_object_agg(entry.participant_id::text, 'bench'::text) as baseline
  from public.match_live_sessions session
  join public.match_composition_entries entry
    on entry.match_id = session.match_id
   and entry.zone = 'bench'
  where session.state in ('running', 'paused', 'halftime', 'finished')
    and not (
      coalesce(session.starting_lineup_snapshot, '{}'::jsonb)
      ? entry.participant_id::text
    )
    and not exists (
      select 1
      from public.match_live_events event
      where event.match_id = session.match_id
        and event.event_type = 'substitution'
        and (
          event.player_in_participant_id = entry.participant_id
          or event.player_out_participant_id = entry.participant_id
        )
    )
  group by session.match_id
)
update public.match_live_sessions session
set starting_lineup_snapshot =
      coalesce(session.starting_lineup_snapshot, '{}'::jsonb)
      || missing.baseline,
    updated_at = now()
from missing_bench missing
where session.match_id = missing.match_id;
