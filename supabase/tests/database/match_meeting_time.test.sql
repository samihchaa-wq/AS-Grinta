begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'matches'
      and column_name = 'meeting_at'
      and is_nullable = 'YES'
  ),
  'l heure de rendez-vous explicite est persistable et facultative'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.admin_create_match_complete_v3(uuid,uuid,date,time without time zone,text,numeric,numeric,numeric,integer,text,boolean,text,text,text,timestamp with time zone,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.admin_create_match_complete_v3(uuid,uuid,date,time without time zone,text,numeric,numeric,numeric,integer,text,boolean,text,text,text,timestamp with time zone,timestamp with time zone)',
    'EXECUTE'
  ),
  'la creation avec heure de rendez-vous reste reservee aux utilisateurs authentifies'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  '94000000-0000-0000-0000-000000000001',
  'meeting-admin@example.invalid',
  '{"first_name":"Admin","last_name":"Meeting"}'::jsonb
);

update public.profiles
set role = 'admin', status = 'active', updated_at = now()
where id = '94000000-0000-0000-0000-000000000001';

insert into public.seasons(id, name, status)
values ('95000000-0000-0000-0000-000000000001', '2097-2098', 'open');

insert into public.opponents(id, name)
values ('96000000-0000-0000-0000-000000000001', 'Meeting FC');

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '94000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"94000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.meeting_auto',
  public.admin_create_match_complete_v3(
    '95000000-0000-0000-0000-000000000001',
    '96000000-0000-0000-0000-000000000001',
    date '2097-06-20', time '18:00', 'domicile',
    2, 3, 4, 14, null, false, 'championnat', null,
    'automatic', null, null
  )::text,
  true
);

select set_config(
  'test.meeting_custom',
  public.admin_create_match_complete_v3(
    '95000000-0000-0000-0000-000000000001',
    '96000000-0000-0000-0000-000000000001',
    date '2097-06-21', time '18:00', 'exterieur',
    2, 3, 4, 14, null, false, 'amical', null,
    'automatic', null, timestamptz '2097-06-21 15:15:00+00'
  )::text,
  true
);

select throws_ok(
  $sql$
    select public.admin_create_match_complete_v3(
      '95000000-0000-0000-0000-000000000001',
      '96000000-0000-0000-0000-000000000001',
      date '2097-06-22', time '18:00', 'domicile',
      2, 3, 4, 14, null, false, 'championnat', null,
      'automatic', null, timestamptz '2097-06-22 17:00:00+00'
    )
  $sql$,
  '22023',
  'Meeting time must be before kickoff',
  'une heure de rendez-vous apres le coup d envoi est rejetee atomiquement'
);

reset role;

select is(
  (
    select meeting_at
    from public.matches
    where id = current_setting('test.meeting_auto')::uuid
  ),
  null::timestamptz,
  'le mode par defaut ne fige aucune heure et reste relatif au coup d envoi'
);

select is(
  (
    select coalesce(meeting_at, kickoff_at - interval '30 minutes')
    from public.matches
    where id = current_setting('test.meeting_auto')::uuid
  ),
  (
    select kickoff_at - interval '30 minutes'
    from public.matches
    where id = current_setting('test.meeting_auto')::uuid
  ),
  'le rendez-vous automatique est exactement H-30'
);

select is(
  (
    select meeting_at
    from public.matches
    where id = current_setting('test.meeting_custom')::uuid
  ),
  timestamptz '2097-06-21 15:15:00+00',
  'une heure de rendez-vous personnalisee est conservee'
);

select is(
  (
    select count(*)::integer
    from public.matches
    where match_date = date '2097-06-22'
  ),
  0,
  'la creation invalide ne laisse aucun match partiel'
);

select * from finish();
rollback;
