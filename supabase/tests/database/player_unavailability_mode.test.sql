begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- ---------------------------------------------------------------------------
-- Mode Indisponibilité
--
-- Un joueur déclare lui-même une période. Pendant cette période il sort de
-- l'effectif convocable et des notifications qui en découlent, il ne peut plus
-- répondre à la disponibilité des matchs concernés, et personne ne répond à sa
-- place. Annuler la période rend la main au joueur, sans jamais écraser une
-- absence qu'il avait écrite lui-même.
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data)
values
  ('ab000000-0000-0000-0000-000000000001',
   'unavailability-admin@example.invalid',
   '{"first_name":"Admin","last_name":"Club"}'::jsonb),
  ('ab000000-0000-0000-0000-000000000002',
   'unavailability-parti@example.invalid',
   '{"first_name":"Parti","last_name":"Loin"}'::jsonb),
  ('ab000000-0000-0000-0000-000000000003',
   'unavailability-reste@example.invalid',
   '{"first_name":"Reste","last_name":"La"}'::jsonb);

update public.profiles
set role = case
      when id = 'ab000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'ab000000-0000-0000-0000-000000000001'
  and 'ab000000-0000-0000-0000-000000000003';

insert into public.seasons (id, name, status)
values ('ac000000-0000-0000-0000-000000000001', '2097-2098', 'open');

insert into public.opponents (id, name)
values ('ad000000-0000-0000-0000-000000000001', 'Absents FC');

insert into public.season_players (
  id, season_id, first_name, last_name,
  is_goalkeeper, is_active, is_coach, position, profile_id
)
values
  ('ae000000-0000-0000-0000-000000000001',
   'ac000000-0000-0000-0000-000000000001',
   'Parti', 'Loin', false, true, false, 1,
   'ab000000-0000-0000-0000-000000000002'),
  ('ae000000-0000-0000-0000-000000000002',
   'ac000000-0000-0000-0000-000000000001',
   'Reste', 'La', false, true, false, 2,
   'ab000000-0000-0000-0000-000000000003');

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'ab000000-0000-0000-0000-000000000001'
where key = 'sports_management';

-- Le coupe-circuit des notifications ne doit pas fausser le scénario.
update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = 'ab000000-0000-0000-0000-000000000001'
where key = 'notifications_paused';

select set_config(
  'request.jwt.claims',
  '{"sub":"ab000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.unavailability_match',
  public.create_match_with_odds_and_sport_limit(
    'ac000000-0000-0000-0000-000000000001',
    'ad000000-0000-0000-0000-000000000001',
    ((now() + interval '10 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '10 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 14
  )::text,
  true
);

reset role;

-- Les disponibilités sont ouvertes tout de suite pour jouer le scénario.
update public.match_sport_workflows
set availability_opens_at = now() - interval '1 hour',
    availability_state = 'open',
    availability_opened_at = now() - interval '1 hour'
where match_id = current_setting('test.unavailability_match')::uuid;

select set_config(
  'test.unavailability_day',
  (
    (
      select match.kickoff_at
      from public.matches match
      where match.id = current_setting('test.unavailability_match')::uuid
    ) at time zone 'Europe/Paris'
  )::date::text,
  true
);

-- ---------------------------------------------------------------------------
-- 1. La table reste hors de portée des clients.
-- ---------------------------------------------------------------------------

select ok(
  (
    select relation.relrowsecurity
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'player_unavailabilities'
  ),
  'la table des indisponibilités garde la RLS active'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.player_unavailabilities', 'SELECT'
  )
  and not has_table_privilege(
    'anon', 'public.player_unavailabilities', 'SELECT'
  ),
  'aucun client ne lit la table directement'
);

-- ---------------------------------------------------------------------------
-- 2. Le joueur déclare sa période et sort de l'effectif convocable.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"ab000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  (
    public.get_my_match_availability(
      current_setting('test.unavailability_match')::uuid
    ) ->> 'can_respond'
  )::boolean,
  'avant toute déclaration, le joueur peut répondre'
);

select set_config(
  'test.unavailability_id',
  (
    public.set_my_unavailability(
      null,
      current_setting('test.unavailability_day')::date - 2,
      current_setting('test.unavailability_day')::date + 2,
      'Vacances en famille'
    ) ->> 'id'
  ),
  true
);

reset role;

select is(
  (
    select participant.availability_status::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.unavailability_match')::uuid
      and participant.season_player_id = 'ae000000-0000-0000-0000-000000000001'
  ),
  'absent',
  'le joueur indisponible est posé absent sur le match de la période'
);

select is(
  (
    select participant.convocation_status::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.unavailability_match')::uuid
      and participant.season_player_id = 'ae000000-0000-0000-0000-000000000001'
  ),
  'not_applicable',
  'il ne fait plus partie de l’effectif convocable'
);

select ok(
  (
    select participant.availability_forced_by_unavailability
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.unavailability_match')::uuid
      and participant.season_player_id = 'ae000000-0000-0000-0000-000000000001'
  ),
  'l’absence est marquée comme posée par l’indisponibilité'
);

-- ---------------------------------------------------------------------------
-- 3. Plus personne ne répond à sa place, lui compris.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"ab000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  not (
    public.get_my_match_availability(
      current_setting('test.unavailability_match')::uuid
    ) ->> 'can_respond'
  )::boolean,
  'la réponse de disponibilité est fermée pendant la période'
);

select is(
  public.get_my_match_availability(
    current_setting('test.unavailability_match')::uuid
  ) ->> 'unavailability_reason',
  'Vacances en famille',
  'le joueur voit pourquoi sa réponse est fermée'
);

select throws_ok(
  format(
    'select public.set_my_match_availability(%L::uuid, %L, null)',
    current_setting('test.unavailability_match'),
    'available'
  ),
  '22023',
  null,
  'le joueur ne peut pas se remettre disponible sans annuler sa période'
);

reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"ab000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  format(
    'select public.admin_override_match_availability(%L::uuid, %L::uuid, %L, null, %L)',
    current_setting('test.unavailability_match'),
    'ae000000-0000-0000-0000-000000000001',
    'available',
    'test'
  ),
  '22023',
  null,
  'un administrateur ne remet pas un joueur indisponible dans l’effectif'
);

-- ---------------------------------------------------------------------------
-- 4. L'administrateur lit l'ensemble des indisponibilités, le joueur non.
-- ---------------------------------------------------------------------------

select ok(
  exists (
    select 1
    from jsonb_array_elements(public.admin_get_player_unavailabilities()) entry
    where entry ->> 'profile_id' = 'ab000000-0000-0000-0000-000000000002'
      and entry ->> 'reason' = 'Vacances en famille'
      and (entry ->> 'created_at') is not null
  ),
  'l’administrateur voit la période, sa raison et sa date de saisie'
);

reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"ab000000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  'select public.admin_get_player_unavailabilities()',
  '42501',
  null,
  'un joueur ne lit pas les indisponibilités des autres'
);

select is(
  jsonb_array_length(public.get_my_unavailabilities()),
  0,
  'un joueur ne voit que ses propres périodes'
);

reset role;

-- ---------------------------------------------------------------------------
-- 5. Les notifications d'ouverture des disponibilités le sautent.
-- ---------------------------------------------------------------------------

delete from public.sport_availability_notification_events
where match_id = current_setting('test.unavailability_match')::uuid;

update public.match_sport_workflows
set availability_state = 'pending',
    availability_opens_at = now() - interval '1 hour'
where match_id = current_setting('test.unavailability_match')::uuid;

select set_config(
  'test.unavailability_notifications',
  private.process_sport_availability_notifications(now())::text,
  true
);

select ok(
  not exists (
    select 1
    from public.sport_availability_notification_events event
    join public.match_sport_participants participant
      on participant.id = event.participant_id
    where event.match_id = current_setting('test.unavailability_match')::uuid
      and participant.season_player_id = 'ae000000-0000-0000-0000-000000000001'
  ),
  'le joueur indisponible ne reçoit pas l’ouverture des disponibilités'
);

select ok(
  exists (
    select 1
    from public.sport_availability_notification_events event
    join public.match_sport_participants participant
      on participant.id = event.participant_id
    where event.match_id = current_setting('test.unavailability_match')::uuid
      and participant.season_player_id = 'ae000000-0000-0000-0000-000000000002'
  ),
  'les autres joueurs reçoivent l’ouverture normalement'
);

-- ---------------------------------------------------------------------------
-- 6. Annuler rend la main au joueur.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"ab000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.cancel_my_unavailability(%L::uuid)',
    current_setting('test.unavailability_id')
  ),
  'le joueur annule sa période quand il veut'
);

reset role;

select is(
  (
    select participant.availability_status::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.unavailability_match')::uuid
      and participant.season_player_id = 'ae000000-0000-0000-0000-000000000001'
  ),
  'no_response',
  'le match repart sans réponse une fois la période annulée'
);

-- ---------------------------------------------------------------------------
-- 7. Une absence écrite par le joueur lui appartient.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"ab000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.unavailability_manual_absence',
  public.set_my_match_availability(
    current_setting('test.unavailability_match')::uuid, 'absent', 'Mariage'
  )::text,
  true
);

select set_config(
  'test.unavailability_second_id',
  (
    public.set_my_unavailability(
      null,
      current_setting('test.unavailability_day')::date,
      current_setting('test.unavailability_day')::date,
      'Blessure'
    ) ->> 'id'
  ),
  true
);

reset role;

select is(
  (
    select participant.availability_comment_private
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.unavailability_match')::uuid
      and participant.season_player_id = 'ae000000-0000-0000-0000-000000000001'
  ),
  'Mariage',
  'la période n’écrase pas le commentaire que le joueur avait écrit'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"ab000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  format(
    'select public.set_my_unavailability(null, %L::date, %L::date, %L)',
    current_setting('test.unavailability_day')::date - 1,
    current_setting('test.unavailability_day')::date + 1,
    'Autre'
  ),
  '22023',
  null,
  'deux périodes ne peuvent pas se chevaucher'
);

select throws_ok(
  format(
    'select public.set_my_unavailability(null, %L::date, %L::date, %L)',
    (now() at time zone 'Europe/Paris')::date - 10,
    (now() at time zone 'Europe/Paris')::date - 5,
    'Trop tard'
  ),
  '22023',
  null,
  'une période déjà terminée ne peut pas être déclarée'
);

select throws_ok(
  format(
    'select public.set_my_unavailability(null, %L::date, %L::date, %L)',
    (now() at time zone 'Europe/Paris')::date + 40,
    (now() at time zone 'Europe/Paris')::date + 45,
    '   '
  ),
  '22023',
  null,
  'la raison est obligatoire'
);

select lives_ok(
  format(
    'select public.cancel_my_unavailability(%L::uuid)',
    current_setting('test.unavailability_second_id')
  ),
  'la seconde période est annulée'
);

reset role;

select is(
  (
    select participant.availability_status::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.unavailability_match')::uuid
      and participant.season_player_id = 'ae000000-0000-0000-0000-000000000001'
  ),
  'absent',
  'l’absence personnelle du joueur survit à l’annulation de la période'
);

select * from finish();
rollback;
