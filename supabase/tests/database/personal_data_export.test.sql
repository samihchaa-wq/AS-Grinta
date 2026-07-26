begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  not has_function_privilege('anon', 'public.export_my_personal_data()', 'EXECUTE')
  and has_function_privilege(
    'authenticated',
    'public.export_my_personal_data()',
    'EXECUTE'
  ),
  'l’export personnel est authentifié uniquement'
);

select ok(
  (
    select p.prosecdef
    from pg_proc p
    where p.oid = 'public.export_my_personal_data()'::regprocedure
  ),
  'l’export utilise les droits serveur avec une identité imposée par auth.uid'
);

insert into auth.users(id, email, raw_user_meta_data)
values (
  'e1000000-0000-0000-0000-000000000001',
  'export-personal@example.invalid',
  '{"first_name":"Export","last_name":"Personnel"}'::jsonb
);

update public.profiles
set username = 'exportp',
    status = 'active',
    notify_match_reminders = true,
    updated_at = now()
where id = 'e1000000-0000-0000-0000-000000000001';

select set_config(
  'request.jwt.claims',
  '{"sub":"e1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.export_my_personal_data() #>> '{profile,id}',
  'e1000000-0000-0000-0000-000000000001',
  'le profil exporté est toujours celui de l’utilisateur courant'
);

select is(
  jsonb_typeof(public.export_my_personal_data() -> 'match_predictions'),
  'array',
  'les collections vides restent représentées par des tableaux JSON'
);

select ok(
  public.export_my_personal_data()::text !~* '(p256dh|"auth"|"endpoint")',
  'aucun secret d’abonnement push ne quitte la base'
);

reset role;
select * from finish();
rollback;
