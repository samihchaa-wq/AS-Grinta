begin;

set local search_path = public, extensions, pg_catalog;
select plan(8);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'notify_admin_availability_change'
      and is_nullable = 'NO'
  ),
  'la préférence admin de changement de disponibilité existe et est non nullable'
);

select is(
  (
    select column_default
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'notify_admin_availability_change'
  ),
  'true',
  'la préférence est active par défaut'
);

select ok(
  to_regprocedure('public.update_my_admin_availability_notification(boolean)') is not null,
  'la RPC de préférence admin existe'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_my_admin_availability_notification(boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.update_my_admin_availability_notification(boolean)',
    'EXECUTE'
  ),
  'la RPC est disponible uniquement aux clients authentifiés côté ACL'
);

select ok(
  position(
    'notify_admin_availability_change'
    in pg_get_functiondef(
      to_regprocedure('private.notify_admin_player_availability_change()')
    )
  ) > 0,
  'le trigger filtre les admins ayant désactivé cette notification'
);

select ok(
  position(
    'admin_availability_change'
    in pg_get_functiondef(to_regprocedure('public.send_test_push_kind(text)'))
  ) > 0,
  'le test typé de changement de disponibilité est disponible'
);

select ok(
  position(
    'not public.is_admin()'
    in pg_get_functiondef(to_regprocedure('public.send_test_push_kind(text)'))
  ) > 0,
  'les tests réservés aux admins sont protégés côté serveur'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.notify_admin_player_availability_change()',
    'EXECUTE'
  ),
  'la fonction interne du trigger reste inaccessible aux clients'
);

select * from finish();
rollback;
