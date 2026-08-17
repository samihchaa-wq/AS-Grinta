begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_update_match_complete'
      and p.pronargs = 16
      and pg_get_function_arguments(p.oid) like '%p_expected_updated_at timestamp with time zone%'
  ),
  'la modification complète expose une version attendue'
);

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'update_internal_match'
      and p.pronargs = 6
      and pg_get_function_arguments(p.oid) like '%p_expected_updated_at timestamp with time zone%'
  ),
  'la modification entre nous expose une version attendue'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.admin_update_match_complete(uuid,uuid,uuid,date,time without time zone,text,text,numeric,numeric,numeric,timestamp with time zone,integer,text,boolean,text,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.admin_update_match_complete(uuid,uuid,uuid,date,time without time zone,text,text,numeric,numeric,numeric,timestamp with time zone,integer,text,boolean,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.admin_update_match_complete(uuid,uuid,uuid,date,time without time zone,text,text,numeric,numeric,numeric,timestamp with time zone,integer,text,boolean,text,text)',
    'EXECUTE'
  ),
  'la modification complète conserve les droits authenticated/service_role sans anon'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_internal_match(uuid,uuid,date,time without time zone,text,timestamp with time zone)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.update_internal_match(uuid,uuid,date,time without time zone,text,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.update_internal_match(uuid,uuid,date,time without time zone,text,timestamp with time zone)',
    'EXECUTE'
  ),
  'la modification entre nous conserve les droits authenticated/service_role sans anon'
);

insert into auth.users(id, email, raw_user_meta_data)
values (
  '44000000-0000-0000-0000-000000000001',
  'match-lock-admin@example.invalid',
  '{"first_name":"Match","last_name":"Lock"}'::jsonb
);

update public.profiles
set role = 'admin', status = 'active', updated_at = now()
where id = '44000000-0000-0000-0000-000000000001';

insert into public.seasons(id, name, status)
values ('44000000-0000-0000-0000-000000000010', '2097-2098', 'open');

insert into public.opponents(id, name)
values ('44000000-0000-0000-0000-000000000011', 'Adversaire verrou test');

insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, match_type, address, created_by, updated_at
)
values (
  '44000000-0000-0000-0000-000000000020',
  '44000000-0000-0000-0000-000000000010',
  '44000000-0000-0000-0000-000000000011',
  date '2097-09-01', '20:00'::time, 'domicile', 90, 'a_venir',
  'championnat', 'Adresse initiale',
  '44000000-0000-0000-0000-000000000001',
  timestamptz '2026-01-01 00:00:00+00'
), (
  '44000000-0000-0000-0000-000000000021',
  '44000000-0000-0000-0000-000000000010',
  null,
  date '2097-09-02', '20:00'::time, 'domicile', 90, 'a_venir',
  'entre_nous', 'Adresse interne initiale',
  '44000000-0000-0000-0000-000000000001',
  timestamptz '2026-01-02 00:00:00+00'
);

set local role authenticated;
set local request.jwt.claim.sub = '44000000-0000-0000-0000-000000000001';

select is(
  public.admin_update_match_complete(
    '44000000-0000-0000-0000-000000000020',
    '44000000-0000-0000-0000-000000000010',
    '44000000-0000-0000-0000-000000000011',
    date '2097-09-03', '21:00'::time, 'domicile', 'a_venir',
    2.00, 3.00, 4.00,
    timestamptz '2026-01-01 00:00:00+00',
    null, 'Première sauvegarde', false, 'championnat', null
  ),
  true,
  'la première édition normale basée sur la bonne version passe'
);

select throws_ok(
  $$select public.admin_update_match_complete(
    '44000000-0000-0000-0000-000000000020',
    '44000000-0000-0000-0000-000000000010',
    '44000000-0000-0000-0000-000000000011',
    date '2097-09-04', '22:00'::time, 'exterieur', 'a_venir',
    2.10, 3.10, 4.10,
    timestamptz '2026-01-01 00:00:00+00',
    null, 'Écrasement interdit', false, 'championnat', null
  )$$,
  '40001',
  'une édition normale basée sur une ancienne version est refusée'
);

select is(
  (select concat_ws('|', match_date::text, match_time::text, location, address)
   from public.matches where id = '44000000-0000-0000-0000-000000000020'),
  '2097-09-03|21:00:00|domicile|Première sauvegarde',
  'le conflit normal ne modifie rien'
);

select is(
  public.update_internal_match(
    '44000000-0000-0000-0000-000000000021',
    '44000000-0000-0000-0000-000000000010',
    date '2097-09-05', '19:30'::time, 'Première interne',
    timestamptz '2026-01-02 00:00:00+00'
  ),
  true,
  'la première édition entre nous basée sur la bonne version passe'
);

select throws_ok(
  $$select public.update_internal_match(
    '44000000-0000-0000-0000-000000000021',
    '44000000-0000-0000-0000-000000000010',
    date '2097-09-06', '18:00'::time, 'Écrasement interne interdit',
    timestamptz '2026-01-02 00:00:00+00'
  )$$,
  '40001',
  'une édition entre nous basée sur une ancienne version est refusée'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (select concat_ws('|', match_date::text, match_time::text, address)
   from public.matches where id = '44000000-0000-0000-0000-000000000021'),
  '2097-09-05|19:30:00|Première interne',
  'le conflit entre nous ne modifie rien'
);

select * from finish();
rollback;
