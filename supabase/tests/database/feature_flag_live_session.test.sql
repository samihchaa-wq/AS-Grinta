begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('public.feature_flag_change_signals') is not null,
  'la table de signal des feature flags existe'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.feature_flag_change_signals'::regclass
  ),
  'la RLS est active sur la table de signal'
);

select ok(
  not has_table_privilege(
    'anon', 'public.feature_flag_change_signals', 'SELECT'
  )
  and has_table_privilege(
    'authenticated', 'public.feature_flag_change_signals', 'SELECT'
  )
  and not has_table_privilege(
    'authenticated', 'public.feature_flag_change_signals', 'INSERT'
  )
  and not has_table_privilege(
    'authenticated', 'public.feature_flag_change_signals', 'UPDATE'
  )
  and not has_table_privilege(
    'authenticated', 'public.feature_flag_change_signals', 'DELETE'
  ),
  'les clients authentifiés peuvent uniquement lire le signal'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'feature_flag_change_signals'
      and policyname = 'active_authenticated_profile_only'
      and permissive = 'RESTRICTIVE'
      and cmd = 'ALL'
      and roles = array['authenticated']::name[]
  ),
  'le signal exige un profil actif'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'private.app_feature_flags'::regclass
      and tgname = 'trg_signal_feature_flag_change'
      and not tgisinternal
  ),
  'une modification du flag déclenche le signal'
);

select ok(
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'feature_flag_change_signals'
  ),
  'le signal est publié dans Supabase Realtime'
);

select ok(
  not has_function_privilege(
    'anon', 'private.signal_feature_flag_change()', 'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated', 'private.signal_feature_flag_change()', 'EXECUTE'
  ),
  'la fonction de trigger ne peut pas être appelée par un client'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'fa000000-0000-0000-0000-000000000001',
    'flag-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Flag"}'::jsonb
  ),
  (
    'fa000000-0000-0000-0000-000000000002',
    'flag-pending@example.invalid',
    '{"first_name":"Pending","last_name":"Flag"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'fa000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = case
      when id = 'fa000000-0000-0000-0000-000000000001' then 'active'
      else 'pending'
    end,
    updated_at = now()
where id in (
  'fa000000-0000-0000-0000-000000000001',
  'fa000000-0000-0000-0000-000000000002'
);

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = null
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"fa000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from public.feature_flag_change_signals),
  0::bigint,
  'un compte en attente ne reçoit aucun signal de feature flag'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from public.feature_flag_change_signals),
  1::bigint,
  'un administrateur actif peut écouter le signal'
);

select set_config(
  'test.feature_flag_revision_before',
  (
    select revision::text
    from public.feature_flag_change_signals
    where key = 'sports_management'
  ),
  true
);

select is(
  public.set_sports_management_enabled(
    true,
    'Test de transition en session'
  ) #>> '{sports_management,enabled}',
  'true',
  'la RPC active le module sportif'
);

reset role;

select is(
  (
    select revision
    from public.feature_flag_change_signals
    where key = 'sports_management'
  ),
  current_setting('test.feature_flag_revision_before')::bigint + 1,
  'la transition incrémente exactement une fois la révision'
);

select is(
  (
    select signal.updated_at
    from public.feature_flag_change_signals signal
    where signal.key = 'sports_management'
  ),
  (
    select flag.updated_at
    from private.app_feature_flags flag
    where flag.key = 'sports_management'
  ),
  'le signal porte la date de la valeur autoritaire'
);

select ok(
  exists (
    select 1
    from private.app_feature_flag_audit
    where feature_key = 'sports_management'
      and old_enabled = false
      and new_enabled = true
      and actor_profile_id = 'fa000000-0000-0000-0000-000000000001'
      and justification = 'Test de transition en session'
  ),
  'la transition temps réel reste auditée'
);

select * from finish();
rollback;
