begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('public.sport_waitlist_entries') is not null,
  'la table de liste d’attente existe'
);
select ok(
  (
    select bool_and(c.relrowsecurity)
    from pg_class c
    where c.oid in (
      'public.sport_waitlist_entries'::regclass,
      'public.match_sport_workflows'::regclass,
      'public.match_sport_participants'::regclass
    )
  ),
  'RLS reste active sur les données sportives'
);
select ok(
  has_table_privilege('authenticated', 'public.sport_waitlist_entries', 'SELECT')
  and not has_table_privilege(
    'authenticated', 'public.sport_waitlist_entries', 'INSERT'
  ),
  'la liste est lisible sous RLS mais jamais modifiable directement'
);
select is(
  (
    select count(*)
    from unnest(array[
      'public.admin_get_sport_waitlist(uuid)',
      'public.admin_reorder_sport_waitlist(uuid,uuid[],text)',
      'public.admin_get_match_convocations(uuid)',
      'public.admin_set_match_convocation(uuid,uuid,text,boolean,text)',
      'public.admin_publish_match_convocations(uuid,text)',
      'public.admin_finalize_match_waitlist_turns(uuid)',
      'public.create_match_with_odds_and_sport_limit(uuid,uuid,date,time without time zone,text,numeric,numeric,numeric,integer)',
      'public.update_match_with_odds_and_sport_limit(uuid,uuid,uuid,date,time without time zone,text,text,numeric,numeric,numeric,integer)'
    ]::text[]) expected(signature)
    join pg_proc p on p.oid = to_regprocedure(expected.signature)
    where p.prosecdef
  ),
  0::bigint,
  'les RPC publiques restent SECURITY INVOKER'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '71000000-0000-0000-0000-000000000001',
    'waitlist-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Rotation"}'::jsonb
  ),
  (
    '71000000-0000-0000-0000-000000000002',
    'waitlist-alice@example.invalid',
    '{"first_name":"Alice","last_name":"Rotation"}'::jsonb
  ),
  (
    '71000000-0000-0000-0000-000000000003',
    'waitlist-bruno@example.invalid',
    '{"first_name":"Bruno","last_name":"Rotation"}'::jsonb
  ),
  (
    '71000000-0000-0000-0000-000000000004',
    'waitlist-chloe@example.invalid',
    '{"first_name":"Chloé","last_name":"Rotation"}'::jsonb
  );

update public.profiles
set role = case
      when id = '71000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  '71000000-0000-0000-0000-000000000001'
  and '71000000-0000-0000-0000-000000000004';

insert into public.seasons(id, name, status)
values
  ('72000000-0000-0000-0000-000000000001', '2094-2095', 'terminee'),
  ('72000000-0000-0000-0000-000000000002', '2095-2096', 'open');

insert into public.opponents(id, name)
values ('73000000-0000-0000-0000-000000000001', 'Rotation FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  ('74000000-0000-0000-0000-000000000011',
   '72000000-0000-0000-0000-000000000001',
   'Alice', 'Rotation', false, true, 1,
   '71000000-0000-0000-0000-000000000002'),
  ('74000000-0000-0000-0000-000000000012',
   '72000000-0000-0000-0000-000000000001',
   'Bruno', 'Rotation', false, true, 2,
   '71000000-0000-0000-0000-000000000003'),
  ('74000000-0000-0000-0000-000000000013',
   '72000000-0000-0000-0000-000000000001',
   'Chloé', 'Rotation', false, true, 3,
   '71000000-0000-0000-0000-000000000004'),
  ('74000000-0000-0000-0000-000000000021',
   '72000000-0000-0000-0000-000000000002',
   'Alice', 'Rotation', false, true, 1,
   '71000000-0000-0000-0000-000000000002'),
  ('74000000-0000-0000-0000-000000000022',
   '72000000-0000-0000-0000-000000000002',
   'Bruno', 'Rotation', false, true, 2,
   '71000000-0000-0000-0000-000000000003'),
  ('74000000-0000-0000-0000-000000000023',
   '72000000-0000-0000-0000-000000000002',
   'Chloé', 'Rotation', false, true, 3,
   '71000000-0000-0000-0000-000000000004');

insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, created_by, kickoff_at
)
values
  ('75000000-0000-0000-0000-000000000011',
   '72000000-0000-0000-0000-000000000001',
   '73000000-0000-0000-0000-000000000001',
   current_date - 20, time '20:00', 'domicile', 90, 'termine',
   '71000000-0000-0000-0000-000000000001', now() - interval '20 days'),
  ('75000000-0000-0000-0000-000000000012',
   '72000000-0000-0000-0000-000000000001',
   '73000000-0000-0000-0000-000000000001',
   current_date - 10, time '20:00', 'exterieur', 90, 'archive',
   '71000000-0000-0000-0000-000000000001', now() - interval '10 days');

insert into public.match_attendance(match_id, season_player_id)
values
  ('75000000-0000-0000-0000-000000000011',
   '74000000-0000-0000-0000-000000000012'),
  ('75000000-0000-0000-0000-000000000011',
   '74000000-0000-0000-0000-000000000013'),
  ('75000000-0000-0000-0000-000000000012',
   '74000000-0000-0000-0000-000000000013');

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '71000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.waitlist_match_early',
  public.create_match_with_odds_and_sport_limit(
    '72000000-0000-0000-0000-000000000002',
    '73000000-0000-0000-0000-000000000001',
    ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '3 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 2
  )::text,
  true
);

select is(
  (
    select squad_size_limit::integer
    from public.match_sport_workflows
    where match_id = current_setting('test.waitlist_match_early')::uuid
  ),
  2,
  'la limite choisie à la création est stockée atomiquement'
);

select is(
  (
    select array_agg(
      (entry ->> 'previous_season_attendance_count')::integer
      order by (entry ->> 'position')::integer
    )
    from jsonb_array_elements(
      public.admin_get_sport_waitlist(
        '72000000-0000-0000-0000-000000000002'
      ) -> 'entries'
    ) entry
  ),
  array[0, 1, 2],
  'l’ordre initial va du moins présent au plus présent'
);

select public.admin_override_match_availability(
  current_setting('test.waitlist_match_early')::uuid,
  '74000000-0000-0000-0000-000000000021',
  'available', null, 'Disponible'
);
select public.admin_override_match_availability(
  current_setting('test.waitlist_match_early')::uuid,
  '74000000-0000-0000-0000-000000000022',
  'available', null, 'Disponible'
);
select public.admin_override_match_availability(
  current_setting('test.waitlist_match_early')::uuid,
  '74000000-0000-0000-0000-000000000023',
  'available', null, 'Disponible'
);

select is(
  (
    select season_player_id
    from public.match_sport_participants
    where match_id = current_setting('test.waitlist_match_early')::uuid
      and convocation_status = 'not_convoked'
  ),
  '74000000-0000-0000-0000-000000000021'::uuid,
  'le premier de la liste est seulement proposé non convoqué'
);

select public.admin_reorder_sport_waitlist(
  '72000000-0000-0000-0000-000000000002',
  array[
    '74000000-0000-0000-0000-000000000023'::uuid,
    '74000000-0000-0000-0000-000000000022'::uuid,
    '74000000-0000-0000-0000-000000000021'::uuid
  ],
  'Ordre personnalisé'
);
select public.admin_recompute_match_convocations(
  current_setting('test.waitlist_match_early')::uuid,
  true
);

select is(
  (
    select season_player_id
    from public.match_sport_participants
    where match_id = current_setting('test.waitlist_match_early')::uuid
      and convocation_status = 'not_convoked'
  ),
  '74000000-0000-0000-0000-000000000023'::uuid,
  'l’ordre administrateur modifie la recommandation'
);

select public.admin_set_match_convocation(
  current_setting('test.waitlist_match_early')::uuid,
  '74000000-0000-0000-0000-000000000023',
  'convoked', false, 'Retour de blessure'
);
select public.admin_set_match_convocation(
  current_setting('test.waitlist_match_early')::uuid,
  '74000000-0000-0000-0000-000000000022',
  'not_convoked', true, 'Exception pour ce match'
);
select public.admin_publish_match_convocations(
  current_setting('test.waitlist_match_early')::uuid,
  'Publication initiale'
);

select ok(
  (
    select convocation_status = 'convoked'
      and not waitlist_turn_should_consume
    from public.match_sport_participants
    where match_id = current_setting('test.waitlist_match_early')::uuid
      and season_player_id = '74000000-0000-0000-0000-000000000023'
  ),
  'l’admin peut garder le joueur proposé sans lui faire consommer son tour'
);

select public.admin_override_match_availability(
  current_setting('test.waitlist_match_early')::uuid,
  '74000000-0000-0000-0000-000000000021',
  'absent', 'Désistement', 'Annulation avant la coupure'
);

select ok(
  (
    select convocation_status = 'convoked'
      and waitlist_turn_state = 'waived'
      and not waitlist_turn_should_consume
    from public.match_sport_participants
    where match_id = current_setting('test.waitlist_match_early')::uuid
      and season_player_id = '74000000-0000-0000-0000-000000000022'
  ),
  'avant J−1 12h, le remplaçant est promu sans consommer son tour'
);

select set_config(
  'test.waitlist_match_late',
  public.create_match_with_odds_and_sport_limit(
    '72000000-0000-0000-0000-000000000002',
    '73000000-0000-0000-0000-000000000001',
    ((now() + interval '2 hours') at time zone 'Europe/Paris')::date,
    ((now() + interval '2 hours') at time zone 'Europe/Paris')::time,
    'exterieur', 2.10, 3.20, 2.90, 2
  )::text,
  true
);

select public.admin_override_match_availability(
  current_setting('test.waitlist_match_late')::uuid,
  '74000000-0000-0000-0000-000000000021',
  'available', null, 'Disponible'
);
select public.admin_override_match_availability(
  current_setting('test.waitlist_match_late')::uuid,
  '74000000-0000-0000-0000-000000000022',
  'available', null, 'Disponible'
);
select public.admin_override_match_availability(
  current_setting('test.waitlist_match_late')::uuid,
  '74000000-0000-0000-0000-000000000023',
  'available', null, 'Disponible'
);
select public.admin_publish_match_convocations(
  current_setting('test.waitlist_match_late')::uuid,
  'Publication tardive'
);

select ok(
  (
    select late_withdrawal_cutoff_at < now()
    from public.match_sport_workflows
    where match_id = current_setting('test.waitlist_match_late')::uuid
  ),
  'la coupure de la veille à midi est déjà passée'
);

select public.admin_override_match_availability(
  current_setting('test.waitlist_match_late')::uuid,
  '74000000-0000-0000-0000-000000000021',
  'absent', 'Désistement tardif', 'Annulation après la coupure'
);

select ok(
  (
    select convocation_status = 'convoked'
      and waitlist_turn_state = 'consumed'
      and waitlist_turn_should_consume
    from public.match_sport_participants
    where match_id = current_setting('test.waitlist_match_late')::uuid
      and season_player_id = '74000000-0000-0000-0000-000000000023'
  ),
  'après J−1 12h, le remplaçant est promu mais son tour reste consommé'
);

reset role;
reset role;

select is(
  (
    select count(*)::integer
    from private.sport_admin_audit_log
    where action in (
      'reorder_waitlist',
      'override_convocation',
      'publish_convocations'
    )
  ),
  5,
  'les réordonnancements, dérogations et publications sont audités'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.admin_get_sport_waitlist(
    '72000000-0000-0000-0000-000000000002'
  )$$,
  '42501',
  'un joueur ne peut pas consulter la liste administrative'
);

reset role;
update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = '71000000-0000-0000-0000-000000000001'
where key = 'sports_management';
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.admin_get_sport_waitlist(
    '72000000-0000-0000-0000-000000000002'
  )$$,
  '42501',
  'le flag désactivé bloque les outils de rotation'
);

reset role;
select * from finish();
rollback;
