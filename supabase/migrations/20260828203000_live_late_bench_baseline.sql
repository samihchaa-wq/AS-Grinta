-- A player added to an already-started Live session enters through the bench.
-- Keep that first bench presence in the same baseline used by
-- private.match_live_snapshot(), otherwise substitute_counts starts at 0 until
-- the player is substituted out for the first time.

create or replace function private.capture_match_live_bench_baseline()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.match_live_state;
begin
  if new.zone <> 'bench' then
    return new;
  end if;

  -- A field -> bench transition is a normal substitution. It is already
  -- counted from match_live_events.player_out_participant_id and must not be
  -- added to the baseline a second time. The same applies to a bench rewrite.
  if tg_op = 'UPDATE' then
    if old.zone in ('field', 'bench') then
      return new;
    end if;
  end if;

  select session.state
  into v_state
  from public.match_live_sessions session
  where session.match_id = new.match_id;

  if v_state not in ('running', 'paused', 'halftime') then
    return new;
  end if;

  update public.match_live_sessions session
  set starting_lineup_snapshot =
        coalesce(session.starting_lineup_snapshot, '{}'::jsonb)
        || jsonb_build_object(new.participant_id::text, 'bench'),
      updated_at = now()
  where session.match_id = new.match_id
    and not (
      coalesce(session.starting_lineup_snapshot, '{}'::jsonb)
      ? new.participant_id::text
    );

  return new;
end;
$$;

comment on function private.capture_match_live_bench_baseline() is
  'Records the first bench presence of a player introduced after Live kickoff; regular field-to-bench substitutions remain event-counted.';

revoke all on function private.capture_match_live_bench_baseline()
from public, anon, authenticated;

drop trigger if exists capture_match_live_bench_baseline
on public.match_composition_entries;

create trigger capture_match_live_bench_baseline
after insert or update of zone on public.match_composition_entries
for each row
execute function private.capture_match_live_bench_baseline();

-- Repair any already-open session created before this migration. A missing
-- baseline key is safe to infer as "bench" when the player is currently on the
-- bench or has already appeared as player_in. Starters keep their existing
-- "field" key, so a normal substitution cannot be double-counted.
with inferred_bench as (
  select distinct candidate.match_id, candidate.participant_id
  from (
    select entry.match_id, entry.participant_id
    from public.match_composition_entries entry
    join public.match_live_sessions session
      on session.match_id = entry.match_id
    where session.state in ('running', 'paused', 'halftime', 'finished')
      and entry.zone = 'bench'

    union

    select event.match_id, event.player_in_participant_id
    from public.match_live_events event
    join public.match_live_sessions session
      on session.match_id = event.match_id
    where session.state in ('running', 'paused', 'halftime', 'finished')
      and event.event_type = 'substitution'
      and event.player_in_participant_id is not null
  ) candidate
), missing_by_match as (
  select
    session.match_id,
    jsonb_object_agg(inferred.participant_id::text, 'bench'::text) as baseline
  from public.match_live_sessions session
  join inferred_bench inferred on inferred.match_id = session.match_id
  where not (
    coalesce(session.starting_lineup_snapshot, '{}'::jsonb)
    ? inferred.participant_id::text
  )
  group by session.match_id
)
update public.match_live_sessions session
set starting_lineup_snapshot =
      coalesce(session.starting_lineup_snapshot, '{}'::jsonb)
      || missing.baseline,
    updated_at = now()
from missing_by_match missing
where session.match_id = missing.match_id;
