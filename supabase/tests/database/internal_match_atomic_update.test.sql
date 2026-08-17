begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'update_internal_match'
      and proc.pronargs = 6
      and pg_get_function_arguments(proc.oid) like '%p_address text%'
      and pg_get_function_arguments(proc.oid) like '%p_expected_updated_at timestamp with time zone%'
  ),
  'la RPC atomique et verrouillée de modification d’un match entre nous existe'
);

select ok(
  not exists (
    select 1
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'update_internal_match'
      and proc.pronargs in (4, 5)
  ),
  'les anciennes RPC de modification d’un match entre nous sont supprimées'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_internal_match(uuid,uuid,date,time without time zone,text,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.update_internal_match(uuid,uuid,date,time without time zone,text,timestamp with time zone)',
    'EXECUTE'
  ),
  'la RPC atomique et verrouillée est réservée aux clients authentifiés'
);

insert into auth.users(id, email, raw_user_meta_data)
values (
  '43000000-0000-0000-0000-000000000001',
  'internal-atomic-admin@example.invalid',
  '{"first_name":"Internal","last_name":"Atomic"}'::jsonb
);

update public.profiles
set role = 'admin',
    status = 'active',
    updated_at = now()
where id = '43000000-0000-0000-0000-000000000001';

insert into public.seasons(id, name, status)
values
  ('43000000-0000-0000-0000-000000000010', '2095-2096', 'open'),
  ('43000000-0000-0000-0000-000000000011', '2096-2097', 'terminee');

insert into public.matches(
  id,
  season_id,
  match_date,
  match_time,
  location,
  address,
  planned_duration_minutes,
  status,
  match_type,
  created_by,
  updated_at
)
values (
  '43000000-0000-0000-0000-000000000020',
  '43000000-0000-0000-0000-000000000010',
  date '2096-06-01',
  '20:00'::time,
  'domicile',
  'Adresse initiale',
  90,
  'a_venir',
  'entre_nous',
  '43000000-0000-0000-0000-000000000001',
  timestamptz '2026-02-01 00:00:00+00'
);

set local role authenticated;
set local request.jwt.claim.sub = '43000000-0000-0000-0000-000000000001';

select is(
  public.update_internal_match(
    '43000000-0000-0000-0000-000000000020',
    '43000000-0000-0000-0000-000000000011',
    date '2096-06-08',
    '21:15'::time,
    'Nouvelle adresse',
    timestamptz '2026-02-01 00:00:00+00'
  ),
  true,
  'la date, l’heure, la saison et l’adresse sont enregistrées par un seul appel'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select concat_ws('|', season_id::text, match_date::text, match_time::text, address)
    from public.matches
    where id = '43000000-0000-0000-0000-000000000020'
  ),
  '43000000-0000-0000-0000-000000000011|2096-06-08|21:15:00|Nouvelle adresse',
  'les quatre valeurs ont été modifiées ensemble'
);

set local role authenticated;
set local request.jwt.claim.sub = '43000000-0000-0000-0000-000000000001';

select throws_ok(
  format(
    'select public.update_internal_match(%L::uuid,%L::uuid,%L::date,%L::time,%L,%L::timestamptz)',
    '43000000-0000-0000-0000-000000000020',
    '43000000-0000-0000-0000-000000000010',
    '2096-06-15',
    '22:30',
    repeat('x', 301),
    (select updated_at::text from public.matches where id = '43000000-0000-0000-0000-000000000020')
  ),
  '22023',
  'une adresse invalide fait échouer toute la sauvegarde'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select concat_ws('|', season_id::text, match_date::text, match_time::text, address)
    from public.matches
    where id = '43000000-0000-0000-0000-000000000020'
  ),
  '43000000-0000-0000-0000-000000000011|2096-06-08|21:15:00|Nouvelle adresse',
  'après un échec, aucune partie du match n’a été modifiée'
);

select * from finish();
rollback;
