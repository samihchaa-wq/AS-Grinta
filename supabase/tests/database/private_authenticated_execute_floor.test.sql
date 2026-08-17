begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select is(
  (
    select count(*)
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'private'
      and function.prokind = 'f'
      and function.proname = any (array[
        'adjust_match_live_score',
        'composition_snapshot',
        'ensure_sport_waitlist',
        'finalize_due_waitlist_turns_for_season',
        'get_notifications_paused',
        'handle_convoked_withdrawal',
        'is_match_coach_or_admin',
        'is_moderator',
        'match_sport_finalization_snapshot',
        'require_sports_management_enabled',
        'resequence_sport_waitlist',
        'resolve_open_sport_season',
        'save_match_effectif',
        'save_match_live_lineup'
      ])
      and has_function_privilege('authenticated', function.oid, 'EXECUTE')
  ),
  0::bigint,
  'authenticated ne peut plus executer directement les helpers private internes durcis'
);

select is(
  (
    select count(*)
    from pg_proc private_function
    join pg_namespace private_namespace
      on private_namespace.oid = private_function.pronamespace
    where private_namespace.nspname = 'private'
      and private_function.prokind = 'f'
      and private_function.prosecdef
      and private_function.provolatile = 'v'
      and has_function_privilege('authenticated', private_function.oid, 'EXECUTE')
      and not exists (
        select 1
        from pg_proc public_function
        join pg_namespace public_namespace
          on public_namespace.oid = public_function.pronamespace
        where public_namespace.nspname = 'public'
          and public_function.prokind = 'f'
          and not public_function.prosecdef
          and pg_get_functiondef(public_function.oid) ilike
              ('%private.' || private_function.proname || '(%')
      )
      and not exists (
        select 1
        from pg_policies policy
        where (coalesce(policy.qual, '') || ' ' || coalesce(policy.with_check, '')) ilike
              ('%private.' || private_function.proname || '(%')
      )
  ),
  0::bigint,
  'aucune fonction private mutatrice SECURITY DEFINER orpheline n est executable par authenticated'
);

select * from finish();
rollback;
