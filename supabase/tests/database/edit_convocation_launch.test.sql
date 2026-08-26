begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  has_function_privilege(
    'authenticated',
    'public.admin_update_match_complete_v3(uuid,uuid,uuid,date,time without time zone,text,text,numeric,numeric,numeric,timestamp with time zone,integer,text,boolean,text,text,timestamp with time zone,text,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.admin_update_match_complete_v3(uuid,uuid,uuid,date,time without time zone,text,text,numeric,numeric,numeric,timestamp with time zone,integer,text,boolean,text,text,timestamp with time zone,text,timestamp with time zone)',
    'EXECUTE'
  ),
  'la modification planifiée reste réservée aux utilisateurs authentifiés'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_internal_match_v3(uuid,uuid,date,time without time zone,text,timestamp with time zone,timestamp with time zone,text,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.update_internal_match_v3(uuid,uuid,date,time without time zone,text,timestamp with time zone,timestamp with time zone,text,timestamp with time zone)',
    'EXECUTE'
  ),
  'la modification planifiée d’un match entre nous est protégée de la même façon'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  '94000000-0000-0000-0000-000000000001',
  'edit-convocation-admin@example.invalid',
  '{"first_name":"Admin","last_name":"Edit Convocation"}'::jsonb
);

update public.profiles
set role = 'admin', status = 'active', updated_at = now()
where id = '94000000-0000-0000-0000-000000000001';

insert into public.seasons(id, name, status)
values ('95000000-0000-0000-0000-000000000001', '2097-2098', 'open');

insert into public.opponents(id, name)
values ('96000000-0000-0000-0000-000000000001', 'Edit Convocation FC');

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
  'test.edit_convocation_match',
  public.admin_create_match_complete_v3(
    '95000000-0000-0000-0000-000000000001',
    '96000000-0000-0000-0000-000000000001',
    date '2098-06-20', time '18:00', 'domicile',
    2, 3, 4, 14, null, false, 'championnat', null,
    'automatic', null, null
  )::text,
  true
);

select set_config(
  'test.edit_convocation_updated_at',
  (
    select updated_at::text
    from public.matches
    where id = current_setting('test.edit_convocation_match')::uuid
  ),
  true
);

select ok(
  public.admin_update_match_complete_v3(
    current_setting('test.edit_convocation_match')::uuid,
    '95000000-0000-0000-0000-000000000001',
    '96000000-0000-0000-0000-000000000001',
    date '2098-06-20', time '18:00', 'domicile', 'a_venir',
    2, 3, 4,
    current_setting('test.edit_convocation_updated_at')::timestamptz,
    14, null, false, 'championnat', null, null,
    'custom', timestamptz '2098-06-12 16:45:00+00'
  ),
  'un match existant accepte une nouvelle date et heure personnalisées de convocation'
);

select set_config(
  'test.edit_convocation_updated_at',
  (
    select updated_at::text
    from public.matches
    where id = current_setting('test.edit_convocation_match')::uuid
  ),
  true
);

select ok(
  (
    select availability_schedule_mode = 'custom'
      and availability_opens_at = timestamptz '2098-06-12 16:45:00+00'
    from public.match_sport_workflows
    where match_id = current_setting('test.edit_convocation_match')::uuid
  ),
  'le nouveau lancement personnalisé est réellement persisté'
);

select ok(
  public.admin_update_match_complete_v3(
    current_setting('test.edit_convocation_match')::uuid,
    '95000000-0000-0000-0000-000000000001',
    '96000000-0000-0000-0000-000000000001',
    date '2098-06-20', time '18:00', 'domicile', 'a_venir',
    2, 3, 4,
    current_setting('test.edit_convocation_updated_at')::timestamptz,
    14, null, false, 'championnat', null, null,
    'automatic', null
  ),
  'le même match peut ensuite repasser en lancement automatique J-6'
);

select is(
  (
    select availability_schedule_mode
    from public.match_sport_workflows
    where match_id = current_setting('test.edit_convocation_match')::uuid
  ),
  'automatic',
  'le second changement de mode est persisté'
);

select is(
  (
    select availability_opens_at
    from public.match_sport_workflows
    where match_id = current_setting('test.edit_convocation_match')::uuid
  ),
  private.match_features_open_at(
    (
      select kickoff_at
      from public.matches
      where id = current_setting('test.edit_convocation_match')::uuid
    )
  ),
  'le retour en automatique recalcule exactement J-6 à 12h Europe/Paris'
);

select set_config(
  'test.edit_internal_match',
  public.create_internal_match_v3(
    '95000000-0000-0000-0000-000000000001',
    date '2098-06-21', time '20:00', null,
    'automatic', null, null
  )::text,
  true
);

select set_config(
  'test.edit_internal_updated_at',
  (
    select updated_at::text
    from public.matches
    where id = current_setting('test.edit_internal_match')::uuid
  ),
  true
);

select ok(
  public.update_internal_match_v3(
    current_setting('test.edit_internal_match')::uuid,
    '95000000-0000-0000-0000-000000000001',
    date '2098-06-21', time '20:00', null,
    current_setting('test.edit_internal_updated_at')::timestamptz,
    null,
    'custom', timestamptz '2098-06-13 17:15:00+00'
  ),
  'un match entre nous peut lui aussi modifier son lancement de convocation'
);

reset role;

select ok(
  (
    select availability_schedule_mode = 'custom'
      and availability_opens_at = timestamptz '2098-06-13 17:15:00+00'
    from public.match_sport_workflows
    where match_id = current_setting('test.edit_internal_match')::uuid
  ),
  'le lancement personnalisé du match entre nous est persisté'
);

select * from finish();
rollback;
