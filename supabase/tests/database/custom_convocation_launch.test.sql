begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'match_sport_workflows'
      and column_name = 'availability_schedule_mode'
  ),
  'le mode de lancement est persisté sur le workflow'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.admin_create_match_complete_v2(uuid,uuid,date,time without time zone,text,numeric,numeric,numeric,integer,text,boolean,text,text,text,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.admin_create_match_complete_v2(uuid,uuid,date,time without time zone,text,numeric,numeric,numeric,integer,text,boolean,text,text,text,timestamp with time zone)',
    'EXECUTE'
  ),
  'la création planifiée est réservée aux utilisateurs authentifiés'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  '91000000-0000-0000-0000-000000000001',
  'convocation-admin@example.invalid',
  '{"first_name":"Admin","last_name":"Convocation"}'::jsonb
);

update public.profiles
set role = 'admin', status = 'active', updated_at = now()
where id = '91000000-0000-0000-0000-000000000001';

insert into public.seasons(id, name, status)
values ('92000000-0000-0000-0000-000000000001', '2098-2099', 'open');

insert into public.opponents(id, name)
values ('93000000-0000-0000-0000-000000000001', 'Convocation FC');

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '91000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.convocation_auto',
  public.admin_create_match_complete_v2(
    '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001',
    date '2099-06-20', time '18:00', 'domicile',
    2, 3, 4, 14, null, false, 'championnat', null,
    'automatic', null
  )::text,
  true
);

select set_config(
  'test.convocation_custom',
  public.admin_create_match_complete_v2(
    '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001',
    date '2099-06-21', time '18:00', 'exterieur',
    2, 3, 4, 14, null, false, 'amical', null,
    'custom', timestamptz '2099-06-10 17:30:00+00'
  )::text,
  true
);

select set_config(
  'test.convocation_now',
  public.create_internal_match_v2(
    '92000000-0000-0000-0000-000000000001',
    date '2099-06-22', time '20:00', null,
    'now', null
  )::text,
  true
);

select public.admin_sync_match_sport_workflow(
  current_setting('test.convocation_custom')::uuid
);

reset role;

select is(
  (
    select availability_schedule_mode
    from public.match_sport_workflows
    where match_id = current_setting('test.convocation_auto')::uuid
  ),
  'automatic',
  'le championnat conserve le mode automatique par défaut'
);

select is(
  (
    select availability_opens_at
    from public.match_sport_workflows
    where match_id = current_setting('test.convocation_auto')::uuid
  ),
  private.match_features_open_at(
    (select kickoff_at from public.matches where id = current_setting('test.convocation_auto')::uuid)
  ),
  'le mode automatique reste exactement J-6 à 12h Europe/Paris'
);

select ok(
  (
    select match.match_type = 'amical'
      and workflow.availability_schedule_mode = 'custom'
      and workflow.availability_opens_at = timestamptz '2099-06-10 17:30:00+00'
    from public.matches match
    join public.match_sport_workflows workflow on workflow.match_id = match.id
    where match.id = current_setting('test.convocation_custom')::uuid
  ),
  'un amical conserve son lancement personnalisé même après resynchronisation'
);

select ok(
  (
    select match.match_type = 'entre_nous'
      and workflow.availability_schedule_mode = 'now'
      and workflow.availability_state = 'open'
      and workflow.availability_opened_at is not null
    from public.matches match
    join public.match_sport_workflows workflow on workflow.match_id = match.id
    where match.id = current_setting('test.convocation_now')::uuid
  ),
  'un match entre nous lancé maintenant ouvre immédiatement les disponibilités'
);

select * from finish();
rollback;
