begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- ---------------------------------------------------------------------------
-- Un membre ajouté à l'effectif après la configuration d'un match doit
-- rejoindre ce match tout seul : sans ligne de participation, le planificateur
-- ne peut pas le voir et il ne reçoit jamais sa demande de disponibilité.
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data)
values
  ('9a000000-0000-0000-0000-000000000001',
   'late-roster-admin@example.invalid',
   '{"first_name":"Admin","last_name":"Roster"}'::jsonb),
  ('9a000000-0000-0000-0000-000000000002',
   'late-roster-present@example.invalid',
   '{"first_name":"Presente","last_name":"Depuis"}'::jsonb),
  ('9a000000-0000-0000-0000-000000000003',
   'late-roster-player@example.invalid',
   '{"first_name":"Tardif","last_name":"Joueur"}'::jsonb),
  ('9a000000-0000-0000-0000-000000000004',
   'late-roster-coach@example.invalid',
   '{"first_name":"Tardif","last_name":"Coach"}'::jsonb);

update public.profiles
set role = case
      when id = '9a000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  '9a000000-0000-0000-0000-000000000001'
  and '9a000000-0000-0000-0000-000000000004';

insert into public.seasons (id, name, status)
values
  ('9b000000-0000-0000-0000-000000000001', '2097-2098', 'open'),
  ('9b000000-0000-0000-0000-000000000002', '2098-2099', 'open');

insert into public.opponents (id, name)
values ('9c000000-0000-0000-0000-000000000001', 'Retard FC');

-- L'effectif au moment où le match est configuré : une seule joueuse.
insert into public.season_players (
  id, season_id, first_name, last_name,
  is_goalkeeper, is_active, is_coach, position, profile_id
)
values
  ('9d000000-0000-0000-0000-000000000001',
   '9b000000-0000-0000-0000-000000000001',
   'Presente', 'Depuis', false, true, false, 1,
   '9a000000-0000-0000-0000-000000000002');

insert into public.push_subscriptions (profile_id, endpoint, p256dh, auth, user_agent)
values
  ('9a000000-0000-0000-0000-000000000002',
   'https://push.example.invalid/late-roster-present', 'k1', 'a1', 'pgTAP'),
  ('9a000000-0000-0000-0000-000000000003',
   'https://push.example.invalid/late-roster-player', 'k2', 'a2', 'pgTAP'),
  ('9a000000-0000-0000-0000-000000000004',
   'https://push.example.invalid/late-roster-coach', 'k3', 'a3', 'pgTAP');

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '9a000000-0000-0000-0000-000000000001'
where key = 'sports_management';

-- Le coupe-circuit des notifications ne doit pas fausser le scénario.
update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = '9a000000-0000-0000-0000-000000000001'
where key = 'notifications_paused';

select set_config(
  'request.jwt.claims',
  '{"sub":"9a000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.late_match',
  public.create_match_with_odds_and_sport_limit(
    '9b000000-0000-0000-0000-000000000001',
    '9c000000-0000-0000-0000-000000000001',
    ((now() + interval '10 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '10 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 14
  )::text,
  true
);

-- Un match d'une autre saison, pour prouver que le rattrapage reste borné.
select set_config(
  'test.other_season_match',
  public.create_match_with_odds_and_sport_limit(
    '9b000000-0000-0000-0000-000000000002',
    '9c000000-0000-0000-0000-000000000001',
    ((now() + interval '11 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '11 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 14
  )::text,
  true
);

reset role;

select is(
  (
    select count(*)::bigint
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.late_match')::uuid
  ),
  1::bigint,
  'le match est configuré avec le seul effectif du moment'
);

-- ---------------------------------------------------------------------------
-- 1. L'arrivée tardive rejoint le match déjà configuré.
-- ---------------------------------------------------------------------------

insert into public.season_players (
  id, season_id, first_name, last_name,
  is_goalkeeper, is_active, is_coach, position, profile_id
)
values
  ('9d000000-0000-0000-0000-000000000002',
   '9b000000-0000-0000-0000-000000000001',
   'Tardif', 'Joueur', false, true, false, 2,
   '9a000000-0000-0000-0000-000000000003'),
  ('9d000000-0000-0000-0000-000000000003',
   '9b000000-0000-0000-0000-000000000001',
   'Tardif', 'Coach', false, true, true, 3,
   '9a000000-0000-0000-0000-000000000004');

select is(
  (
    select participant.is_eligible
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.late_match')::uuid
      and participant.season_player_id = '9d000000-0000-0000-0000-000000000002'
  ),
  true,
  'le joueur arrivé après la configuration rejoint le match, dans la rotation'
);

select is(
  (
    select participant.is_eligible
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.late_match')::uuid
      and participant.season_player_id = '9d000000-0000-0000-0000-000000000003'
  ),
  false,
  'le coach arrivé après la configuration rejoint le match, hors rotation'
);

select is(
  (
    select participant.availability_status::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.late_match')::uuid
      and participant.season_player_id = '9d000000-0000-0000-0000-000000000002'
  ),
  'no_response',
  'l’arrivée tardive démarre sans réponse, comme tout le monde'
);

select is(
  (
    select count(*)::bigint
    from public.match_sport_participants participant
    where participant.match_id
          = current_setting('test.other_season_match')::uuid
  ),
  0::bigint,
  'le match d’une autre saison n’est jamais complété par cet effectif'
);

-- ---------------------------------------------------------------------------
-- 2. Le planificateur voit désormais l'arrivée tardive.
-- ---------------------------------------------------------------------------

update public.match_sport_workflows
set availability_opens_at = now() - interval '1 hour'
where match_id = current_setting('test.late_match')::uuid;

select ok(
  (
    private.process_sport_availability_notifications(
      (
        select availability_opens_at
        from public.match_sport_workflows
        where match_id = current_setting('test.late_match')::uuid
      )
    ) #>> '{notifications_created}'
  )::integer >= 3,
  'l’ouverture des disponibilités notifie aussi les arrivées tardives'
);

select ok(
  exists (
    select 1
    from public.sport_availability_notification_events event
    where event.match_id = current_setting('test.late_match')::uuid
      and event.profile_id = '9a000000-0000-0000-0000-000000000003'
      and event.kind = 'availability_open'
  ),
  'le joueur arrivé tardivement reçoit sa demande de disponibilité'
);

select ok(
  exists (
    select 1
    from public.sport_availability_notification_events event
    where event.match_id = current_setting('test.late_match')::uuid
      and event.profile_id = '9a000000-0000-0000-0000-000000000004'
      and event.kind = 'availability_open'
  ),
  'le coach arrivé tardivement reçoit sa demande de disponibilité'
);

-- ---------------------------------------------------------------------------
-- 3. Sortir de l'effectif sort de la rotation, sans rien effacer.
-- ---------------------------------------------------------------------------

update public.season_players
set is_active = false
where id = '9d000000-0000-0000-0000-000000000002';

select is(
  (
    select participant.is_eligible
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.late_match')::uuid
      and participant.season_player_id = '9d000000-0000-0000-0000-000000000002'
  ),
  false,
  'le membre désactivé quitte la rotation du match à venir'
);

select ok(
  exists (
    select 1
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.late_match')::uuid
      and participant.season_player_id = '9d000000-0000-0000-0000-000000000002'
  ),
  'sa ligne de participation est conservée, rien n’est effacé'
);

-- ---------------------------------------------------------------------------
-- 4. Revenir dans l'effectif ramène dans la rotation.
-- ---------------------------------------------------------------------------

update public.season_players
set is_active = true
where id = '9d000000-0000-0000-0000-000000000002';

select is(
  (
    select participant.is_eligible
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.late_match')::uuid
      and participant.season_player_id = '9d000000-0000-0000-0000-000000000002'
  ),
  true,
  'le membre réactivé revient dans la rotation du match à venir'
);

update public.season_players
set is_active = false
where id = '9d000000-0000-0000-0000-000000000003';

update public.season_players
set is_active = true
where id = '9d000000-0000-0000-0000-000000000003';

select is(
  (
    select participant.is_eligible
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.late_match')::uuid
      and participant.season_player_id = '9d000000-0000-0000-0000-000000000003'
  ),
  false,
  'la réactivation ne fait jamais entrer un coach dans la rotation'
);

select * from finish();
rollback;
