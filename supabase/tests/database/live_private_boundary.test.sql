begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

create temporary table pg_temp.live_private_targets(name text primary key) on commit drop;
insert into pg_temp.live_private_targets(name) values
  ('add_match_live_players'),
  ('confirm_start_match_live'),
  ('delete_match_live_event'),
  ('end_match_live'),
  ('get_match_live_add_player_options'),
  ('get_match_live_timeline'),
  ('match_live_snapshot'),
  ('open_match_live_workspace'),
  ('publish_match_live_recap'),
  ('reopen_match_live'),
  ('restart_match_live_session'),
  ('set_match_live_clock_state'),
  ('set_match_live_event_scorer');

create temporary table pg_temp.live_public_targets(name text primary key) on commit drop;
insert into pg_temp.live_public_targets(name) values
  ('coach_add_match_live_players'),
  ('confirm_start_match_live'),
  ('coach_delete_match_live_event'),
  ('coach_end_match_live'),
  ('get_match_live_add_player_options'),
  ('get_match_live_timeline'),
  ('get_match_live_state'),
  ('open_match_live_workspace'),
  ('coach_publish_match_live_recap'),
  ('coach_reopen_match_live'),
  ('coach_restart_match_live_session'),
  ('coach_set_match_live_clock_state'),
  ('coach_set_match_live_event_scorer');

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_temp.live_private_targets target on target.name = p.proname
    where n.nspname = 'private'
  ),
  13::bigint,
  'the thirteen Live private implementation functions exist'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_temp.live_private_targets target on target.name = p.proname
    where n.nspname = 'private'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ),
  0::bigint,
  'authenticated cannot execute Live private implementations directly'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_temp.live_public_targets target on target.name = p.proname
    where n.nspname = 'public'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  13::bigint,
  'authenticated keeps all thirteen public Live RPCs while anon cannot execute them'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_temp.live_public_targets target on target.name = p.proname
    where n.nspname = 'public'
      and p.prosecdef
      and coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""']
      and position('private.is_active_profile()' in pg_get_functiondef(p.oid)) > 0
  ),
  13::bigint,
  'all thirteen public Live boundaries are guarded SECURITY DEFINER functions with empty search_path'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_temp.live_private_targets target on target.name = p.proname
    where n.nspname = 'private'
      and position('private.is_match_coach_or_admin(p_match_id)' in pg_get_functiondef(p.oid)) > 0
  ),
  11::bigint,
  'eleven coach-mutating Live implementations retain match-specific coach/admin authorization'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in ('get_match_live_timeline', 'match_live_snapshot')
      and position('private.is_active_profile()' in pg_get_functiondef(p.oid)) > 0
  ),
  2::bigint,
  'the two player-readable Live implementations retain their active-profile authorization'
);

select * from finish();
rollback;
