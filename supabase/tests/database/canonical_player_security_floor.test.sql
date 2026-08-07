begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select is(
  (
    select count(*)
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = any (array[
        'players',
        'player_aliases',
        'historical_match_players',
        'historical_player_name_links'
      ])
      and policy.policyname = 'active_authenticated_profile_only'
      and policy.permissive = 'RESTRICTIVE'
      and policy.cmd = 'ALL'
      and policy.roles = array['authenticated']::name[]
  ),
  4::bigint,
  'les quatre tables canoniques appliquent le plancher de profil actif'
);

select is(
  (
    select count(*)
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = any (array[
        'players',
        'player_aliases',
        'historical_match_players',
        'historical_player_name_links'
      ])
      and policy.policyname = 'deny_client_access'
      and policy.permissive = 'RESTRICTIVE'
      and policy.cmd = 'ALL'
  ),
  4::bigint,
  'les quatre tables canoniques refusent tout accès direct client'
);

select ok(
  not has_table_privilege('anon', 'public.players', 'SELECT')
  and not has_table_privilege('authenticated', 'public.players', 'SELECT')
  and has_table_privilege('service_role', 'public.players', 'SELECT'),
  'players reste interne et accessible au service_role'
);

select * from finish();
rollback;
