begin;

create index if not exists match_live_sessions_pilot_profile_id_idx
  on public.match_live_sessions (pilot_profile_id);

commit;
