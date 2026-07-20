begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('public.match_sport_workflows') is not null,
  'la table des workflows sportifs existe'
);
select ok(
  to_regclass('public.match_sport_participants') is not null,
  'la table des participants sportifs existe'
);
select ok(
  to_regclass('public.match_sport_participant_events') is not null,
  'la table append-only des événements existe'
);
select ok(
  to_regclass('private.sport_admin_audit_log') is not null,
  'la table privée d’audit administratif existe'
);

select ok(
  (
    select bool_and(c.relrowsecurity)
    from pg_class c
    where c.oid in (
      'public.match_sport_workflows'::regclass,
      'public.match_sport_participants'::regclass,
      'public.match_sport_participant_events'::regclass,
      'private.sport_admin_audit_log'::regclass
    )
  ),
  'RLS est activée sur toutes les nouvelles tables'
);

select ok(
  has_table_privilege(
    'authenticated',
    'public.match_sport_workflows',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.match_sport_workflows',
    'INSERT'
  )
  and has_table_privilege(
    'authenticated',
    'public.match_sport_participants',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.match_sport_participants',
    'UPDATE'
  ),
  'les clients disposent uniquement des lectures soumises à RLS'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'private.sport_admin_audit_log',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'private.sport_admin_audit_log',
    'INSERT'
  ),
  'l’audit administratif reste inaccessible directement aux clients'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_sync_match_sport_workflow(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.set_my_match_availability(uuid,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.admin_override_match_availability(uuid,uuid,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_my_match_availability(uuid)',
    'EXECUTE'
  ),
  'aucune RPC de disponibilité n’est exposée au rôle anonyme'
);

select is(
  (
    select count(*)
    from unnest(array[
      'public.admin_sync_match_sport_workflow(uuid)',
      'public.set_my_match_availability(uuid,text,text)',
      'public.admin_override_match_availability(uuid,uuid,text,text,text)',
      'public.get_my_match_availability(uuid)'
    ]::text[]) as expected(signature)
    join pg_proc p on p.oid = to_regprocedure(expected.signature)
    where p.prosecdef
  ),
  0::bigint,
  'les RPC publiques restent SECURITY INVOKER'
);

select is(
  (
    select count(*)
    from unnest(array[
      'private.require_sports_management_enabled()',
      'private.can_read_sport_workflow(uuid)',
      'private.can_read_sport_participant(uuid)',
      'private.sync_match_sport_workflow(uuid)',
      'private.set_my_match_availability(uuid,text,text)',
      'private.override_match_availability(uuid,uuid,text,text,text)',
      'private.get_my_match_availability(uuid)'
    ]::text[]) as expected(signature)
    join pg_proc p on p.oid = to_regprocedure(expected.signature)
    where not p.prosecdef
      or not coalesce(p.proconfig, '{}'::text[])
        @> array['search_path=""']
  ),
  0::bigint,
  'les helpers privilégiés sont privés, SECURITY DEFINER et à search_path vide'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '61000000-0000-0000-0000-000000000001',
    'sport-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Sport"}'::jsonb
  ),
  (
    '61000000-0000-0000-0000-000000000002',
    'sport-alice@example.invalid',
    '{"first_name":"Alice","last_name":"Sport"}'::jsonb
  ),
  (
    '61000000-0000-0000-0000-000000000003',
    'sport-bruno@example.invalid',
    '{"first_name":"Bruno","last_name":"Sport"}'::jsonb
  ),
  (
    '61000000-0000-0000-0000-000000000004',
    'sport-inactive@example.invalid',
    '{"first_name":"Inactif","last_name":"Sport"}'::jsonb
  );

update public.profiles
set role = case
      when id = '61000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = case
      when id = '61000000-0000-0000-0000-000000000004' then 'pending'
      else 'active'
    end,
    updated_at = now()
where id between
  '61000000-0000-0000-0000-000000000001'
  and '61000000-0000-0000-0000-000000000004';

insert into public.seasons (id, name, status)
values ('62000000-0000-0000-0000-000000000001', '2096-2097', 'open');

insert into public.opponents (id, name)
values ('63000000-0000-0000-0000-000000000001', 'Adversaire Sport');

insert into public.season_players (
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position,
  profile_id
)
values
  (
    '64000000-0000-0000-0000-000000000001',
    '62000000-0000-0000-0000-000000000001',
    'Alice',
    'Sport',
    false,
    true,
    1,
    '61000000-0000-0000-0000-000000000002'
  ),
  (
    '64000000-0000-0000-0000-000000000002',
    '62000000-0000-0000-0000-000000000001',
    'Bruno',
    'Sport',
    true,
    true,
    2,
    '61000000-0000-0000-0000-000000000003'
  ),
  (
    '64000000-0000-0000-0000-000000000003',
    '62000000-0000-0000-0000-000000000001',
    'Inactif',
    'Sport',
    false,
    true,
    3,
    '61000000-0000-0000-0000-000000000004'
  ),
  (
    '64000000-0000-0000-0000-000000000004',
    '62000000-0000-0000-0000-000000000001',
    'Sans',
    'Compte',
    false,
    true,
    4,
    null
  );

insert into public.matches (
  id,
  season_id,
  opponent_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  status,
  created_by,
  kickoff_at
)
select
  '65000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',
  '63000000-0000-0000-0000-000000000001',
  ((now() + interval '48 hours') at time zone 'Europe/Paris')::date,
  ((now() + interval '48 hours') at time zone 'Europe/Paris')::time,
  'domicile',
  90,
  'a_venir',
  '61000000-0000-0000-0000-000000000001',
  now() + interval '48 hours';

insert into public.matches (
  id,
  season_id,
  opponent_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  status,
  created_by,
  kickoff_at
)
select
  '65000000-0000-0000-0000-000000000002',
  '62000000-0000-0000-0000-000000000001',
  '63000000-0000-0000-0000-000000000001',
  ((now() + interval '10 days') at time zone 'Europe/Paris')::date,
  ((now() + interval '10 days') at time zone 'Europe/Paris')::time,
  'exterieur',
  90,
  'a_venir',
  '61000000-0000-0000-0000-000000000001',
  now() + interval '10 days';

select set_config(
  'request.jwt.claims',
  '{"sub":"61000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_sync_match_sport_workflow('65000000-0000-0000-0000-000000000001')$$,
  '42501',
  'le flag désactivé bloque la création de tout workflow'
);

reset role;
select is(
  (
    select count(*)
    from public.match_sport_workflows
    where match_id = '65000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'aucune donnée sportive n’est créée lorsque le flag est désactivé'
);

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '61000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"61000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_sync_match_sport_workflow(
    '65000000-0000-0000-0000-000000000001'
  ) #>> '{availability_state}',
  'open',
  'un match créé à moins de 144 heures est ouvert immédiatement'
);

select is(
  public.admin_sync_match_sport_workflow(
    '65000000-0000-0000-0000-000000000002'
  ) #>> '{availability_state}',
  'pending',
  'un match plus éloigné reste en attente'
);

reset role;
select is(
  (
    select availability_opens_at
    from public.match_sport_workflows
    where match_id = '65000000-0000-0000-0000-000000000001'
  ),
  (
    select kickoff_at - interval '144 hours'
    from public.matches
    where id = '65000000-0000-0000-0000-000000000001'
  ),
  'l’ouverture est calculée exactement 144 heures avant le coup d’envoi'
);

select is(
  (
    select squad_size_limit
    from public.match_sport_workflows
    where match_id = '65000000-0000-0000-0000-000000000001'
  ),
  14::smallint,
  'la limite habituelle de convocation est initialisée à 14'
);

select is(
  (
    select count(*)
    from public.match_sport_participants
    where match_id = '65000000-0000-0000-0000-000000000001'
      and is_eligible
  ),
  2::bigint,
  'seuls les joueurs actifs liés à un compte actif sont éligibles'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"61000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (
    select count(*)
    from public.match_sport_workflows
    where match_id = '65000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'un joueur participant peut lire le workflow de son match'
);

select is(
  (
    select count(*)
    from public.match_sport_participants
    where match_id = '65000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'un joueur ne voit que sa propre ligne de disponibilité'
);

select throws_ok(
  $$
    update public.match_sport_participants
    set availability_status = 'available'
    where match_id = '65000000-0000-0000-0000-000000000001'
  $$,
  '42501',
  'aucune mise à jour directe ne contourne la RPC atomique'
);

select is(
  public.set_my_match_availability(
    '65000000-0000-0000-0000-000000000001',
    'available',
    'ce commentaire doit être supprimé'
  ) #>> '{availability_status}',
  'available',
  'le joueur peut se déclarer disponible'
);

select is(
  public.get_my_match_availability(
    '65000000-0000-0000-0000-000000000001'
  ) #>> '{private_comment}',
  null,
  'un commentaire est supprimé pour le statut disponible'
);

select is(
  public.set_my_match_availability(
    '65000000-0000-0000-0000-000000000001',
    'absent',
    'Déplacement professionnel'
  ) #>> '{availability_status}',
  'absent',
  'le joueur peut modifier sa réponse avant le coup d’envoi'
);

select is(
  (
    select count(*)
    from public.match_sport_participant_events
    where match_id = '65000000-0000-0000-0000-000000000001'
  ),
  2::bigint,
  'chaque changement réel ajoute un événement append-only'
);

select throws_ok(
  $$
    select public.set_my_match_availability(
      '65000000-0000-0000-0000-000000000002',
      'available',
      null
    )
  $$,
  '22023',
  'le joueur ne peut pas répondre avant l’ouverture exacte'
);

select throws_ok(
  $$select public.admin_sync_match_sport_workflow('65000000-0000-0000-0000-000000000001')$$,
  '42501',
  'un joueur ne peut pas synchroniser un workflow'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"61000000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (
    select count(*)
    from public.match_sport_participants
    where season_player_id = '64000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'Bruno ne peut pas lire la disponibilité privée d’Alice'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"61000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_override_match_availability(
    '65000000-0000-0000-0000-000000000001',
    '64000000-0000-0000-0000-000000000002',
    'absent',
    'Blessure signalée au coach',
    'Correction après appel du joueur'
  ) #>> '{availability_status}',
  'absent',
  'un administrateur peut corriger une réponse avec motif d’audit'
);

reset role;
select is(
  (
    select count(*)
    from private.sport_admin_audit_log
    where match_id = '65000000-0000-0000-0000-000000000001'
      and action = 'override_availability'
  ),
  1::bigint,
  'la correction administrative est auditée'
);

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = '61000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"61000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (
    select count(*)
    from public.match_sport_participants
    where match_id = '65000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'la désactivation masque immédiatement les données par RLS'
);

select throws_ok(
  $$
    select public.set_my_match_availability(
      '65000000-0000-0000-0000-000000000001',
      'available',
      null
    )
  $$,
  '42501',
  'la désactivation bloque immédiatement toute nouvelle écriture'
);

reset role;
select is(
  (
    select count(*)
    from public.match_sport_participants
    where match_id = '65000000-0000-0000-0000-000000000001'
  ),
  2::bigint,
  'les données existantes sont conservées après désactivation'
);

select * from finish();
rollback;
