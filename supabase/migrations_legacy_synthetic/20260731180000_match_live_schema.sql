-- Tableau Blanc (live coach whiteboard): schema for live match tracking.
-- Never touches matches.status: the live session's own state machine tracks
-- "is this match being tracked live right now"; matches.status only becomes
-- 'termine' at export time, via the existing unmodified finalize RPC.

create type public.match_live_state as enum (
  'not_started', 'running', 'paused', 'halftime', 'finished'
);

create table public.match_live_sessions (
  match_id uuid primary key references public.matches(id) on delete restrict,
  state public.match_live_state not null default 'not_started',
  planned_duration_minutes integer not null check (planned_duration_minutes between 1 and 200),
  half smallint not null default 1 check (half in (1, 2)),
  -- Stopwatch model: elapsed_seconds accumulates completed running spans;
  -- while state = 'running', true elapsed = elapsed_seconds + (now() - running_since).
  -- Only state transitions are written/synced; the ticking display is computed
  -- client-side from this pair, never via a per-second write.
  elapsed_seconds integer not null default 0 check (elapsed_seconds >= 0),
  running_since timestamptz,
  score_as_grinta integer not null default 0 check (score_as_grinta between 0 and 99),
  score_adverse integer not null default 0 check (score_adverse between 0 and 99),
  starting_composition_version integer,
  -- {participant_id: 'field'|'bench'} captured at confirm_start_match_live, used
  -- to seed the "times benched" counter (starts at 1 for a bench starter).
  starting_lineup_snapshot jsonb,
  -- Bumped by save_match_live_lineup on every lineup write. Viewers watch
  -- match_live_sessions for realtime anyway (clock/score); reusing it as the
  -- lineup-changed signal avoids granting authenticated SELECT on
  -- match_compositions, whose pre-publication draft must stay admin-only.
  lineup_revision integer not null default 0,
  started_at timestamptz,
  finished_at timestamptz,
  exported boolean not null default false,
  exported_at timestamptz,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  check (state <> 'running' or running_since is not null),
  check (state = 'running' or running_since is null)
);

comment on table public.match_live_sessions is
  'One row per match tracked live via the Tableau Blanc. Independent of matches.status.';
comment on column public.match_live_sessions.exported is
  'True once publish_match_live_recap successfully called finalize_match_sport_postgame. Immutable afterwards.';

create table public.match_live_events (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete restrict,
  event_type text not null check (event_type in ('goal_us', 'goal_them', 'substitution')),
  minute integer not null check (minute >= 0),
  half smallint not null check (half in (1, 2)),
  scorer_participant_id uuid,
  score_as_grinta_after integer,
  score_adverse_after integer,
  player_in_participant_id uuid,
  player_out_participant_id uuid,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (scorer_participant_id, match_id)
    references public.match_sport_participants(id, match_id) on delete restrict,
  foreign key (player_in_participant_id, match_id)
    references public.match_sport_participants(id, match_id) on delete restrict,
  foreign key (player_out_participant_id, match_id)
    references public.match_sport_participants(id, match_id) on delete restrict,
  check (
    (
      event_type = 'goal_us' and score_as_grinta_after is not null
      and score_adverse_after is null and scorer_participant_id is not null
      and player_in_participant_id is null and player_out_participant_id is null
    )
    or (
      event_type = 'goal_them' and score_adverse_after is not null
      and score_as_grinta_after is null and scorer_participant_id is null
      and player_in_participant_id is null and player_out_participant_id is null
    )
    or (
      event_type = 'substitution' and player_in_participant_id is not null
      and player_out_participant_id is not null and scorer_participant_id is null
      and score_as_grinta_after is null and score_adverse_after is null
    )
  )
);

comment on table public.match_live_events is
  'Append-only timeline of goals and substitutions. Never deleted at export time: it is the permanent source for the "Faits du match" tab.';

create index match_live_events_match_id_created_idx
  on public.match_live_events(match_id, created_at);

alter table public.match_live_sessions enable row level security;
alter table public.match_live_events enable row level security;

revoke all on table public.match_live_sessions from public, anon, authenticated;
revoke all on table public.match_live_events from public, anon, authenticated;

grant select on table public.match_live_sessions to authenticated;
grant select on table public.match_live_events to authenticated;
grant select, insert, update on table public.match_live_sessions to service_role;
grant select, insert, update, delete on table public.match_live_events to service_role;

create policy match_live_sessions_active_profile_select
on public.match_live_sessions for select to authenticated
using (
  (select private.is_feature_enabled('sports_management'))
  and (select private.is_active_profile())
);

create policy match_live_events_active_profile_select
on public.match_live_events for select to authenticated
using (
  (select private.is_feature_enabled('sports_management'))
  and (select private.is_active_profile())
);

alter table public.match_live_sessions replica identity full;
alter table public.match_live_events replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'match_live_sessions'
    ) then
      alter publication supabase_realtime add table public.match_live_sessions;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'match_live_events'
    ) then
      alter publication supabase_realtime add table public.match_live_events;
    end if;
  end if;
end $$;
