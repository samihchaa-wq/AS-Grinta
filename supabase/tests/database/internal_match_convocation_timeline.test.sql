begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Répétition complète du cycle d'un « Match entre nous », de sa création
-- jusqu'aux convocations publiées, puis à la clôture automatique.
--
-- Les tests existants couvrent le choix du mode de lancement. Celui-ci couvre
-- la suite : l'ouverture automatique à J-6 12 h par le cron, l'envoi unique de
-- la notification d'ouverture, le calcul et la publication des convocations,
-- le verrou T-15 et la fin automatique après la durée du match.
--
-- Les appels métier s'exécutent sous le rôle `authenticated`, comme
-- l'application. Les vérifications repassent sous `postgres` afin de lire les
-- tables internes sans dépendre des politiques de lecture.

insert into auth.users (id, email, raw_user_meta_data)
values (
  '9a000000-0000-0000-0000-000000000001',
  'timeline-admin@example.invalid',
  '{"first_name":"Admin","last_name":"Timeline"}'::jsonb
);

update public.profiles
set role = 'admin', status = 'active', updated_at = now()
where id = '9a000000-0000-0000-0000-000000000001';

insert into public.seasons (id, name, status)
values ('9a000000-0000-0000-0000-0000000000aa', '2996-2997', 'open');

update private.app_feature_flags
set enabled = true, updated_at = now()
where key = 'sports_management';

update private.app_feature_flags
set enabled = false, updated_at = now()
where key = 'notifications_paused';

-- Vingt joueurs à l'effectif ; seuls les neuf premiers ont un compte actif.
do $seed$
declare
  v_i integer;
  v_uid uuid;
  v_name text;
begin
  for v_i in 1..20 loop
    v_name := 'Joueur' || chr(64 + v_i);
    if v_i <= 9 then
      v_uid := ('9a000000-0000-0000-0000-0000002000' || lpad(v_i::text, 2, '0'))::uuid;
      insert into auth.users (id, email, raw_user_meta_data)
      values (
        v_uid,
        'timeline-p' || v_i || '@example.invalid',
        json_build_object('first_name', v_name, 'last_name', 'Timeline')::jsonb
      );
      update public.profiles
      set role = 'pronostiqueur', status = 'active', updated_at = now()
      where id = v_uid;
    else
      v_uid := null;
    end if;

    insert into public.season_players (
      id, season_id, first_name, last_name, is_goalkeeper, is_active, position, profile_id
    )
    values (
      ('9a000000-0000-0000-0000-0000001000' || lpad(v_i::text, 2, '0'))::uuid,
      '9a000000-0000-0000-0000-0000000000aa',
      v_name,
      'Timeline',
      v_i <= 2,
      true,
      v_i,
      v_uid
    );
  end loop;
end
$seed$;

select set_config('test.today', ((now() at time zone 'Europe/Paris')::date)::text, true);
select set_config(
  'test.opens_at',
  (
    ((((now() at time zone 'Europe/Paris')::date + 1))::timestamp + time '12:00')
      at time zone 'Europe/Paris'
  )::text,
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"9a000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);

-- ---------------------------------------------------------------------------
-- 1. Création : le match s'ouvre automatiquement à J-6 à 12 h, heure de Paris.
-- ---------------------------------------------------------------------------
set local role authenticated;

select set_config(
  'test.timeline_match',
  public.create_internal_match_v3(
    '9a000000-0000-0000-0000-0000000000aa',
    current_setting('test.today')::date + 7,
    time '20:45',
    'Stade Timeline',
    'automatic',
    null,
    null
  )::text,
  true
);

set local role postgres;

select is(
  (select match_type from public.matches where id = current_setting('test.timeline_match')::uuid),
  'entre_nous',
  'le match créé est bien un match entre nous'
);

select is(
  (
    select workflow.availability_opens_at
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.timeline_match')::uuid
  ),
  current_setting('test.opens_at')::timestamptz,
  'les disponibilités s’ouvrent à J-6 à 12 h, heure de Paris'
);

select is(
  (
    select workflow.availability_state::text
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.timeline_match')::uuid
  ),
  'pending',
  'avant l’heure, les disponibilités restent fermées'
);

select is(
  (
    select workflow.squad_size_limit
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.timeline_match')::uuid
  ),
  30,
  'un match entre nous accueille tout l’effectif, pas seulement quatorze joueurs'
);

select is(
  (
    select count(*)
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.timeline_match')::uuid
      and participant.is_eligible
  ),
  20::bigint,
  'les vingt joueurs de l’effectif sont convocables'
);

-- ---------------------------------------------------------------------------
-- 2. Le cron n’ouvre rien une minute trop tôt.
-- ---------------------------------------------------------------------------
select is(
  private.process_sport_availability_notifications(
    current_setting('test.opens_at')::timestamptz - interval '1 minute'
  ) ->> 'notifications_created',
  '0',
  'aucune notification n’est envoyée avant l’heure d’ouverture'
);

select is(
  (
    select workflow.availability_state::text
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.timeline_match')::uuid
  ),
  'pending',
  'une minute avant l’heure, les disponibilités sont toujours fermées'
);

-- ---------------------------------------------------------------------------
-- 3. À l’heure dite, le cron ouvre et prévient les joueurs qui ont un compte.
-- ---------------------------------------------------------------------------
select lives_ok(
  $$select private.process_sport_availability_notifications(
      current_setting('test.opens_at')::timestamptz
    )$$,
  'le passage du cron à J-6 12 h se déroule sans erreur'
);

select is(
  (
    select workflow.availability_state::text
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.timeline_match')::uuid
  ),
  'open',
  'les disponibilités s’ouvrent à l’heure prévue'
);

select is(
  (
    select count(*)
    from public.sport_availability_notification_events event
    where event.match_id = current_setting('test.timeline_match')::uuid
      and event.kind = 'availability_open'
  ),
  9::bigint,
  'seuls les joueurs reliés à un compte actif sont prévenus'
);

select lives_ok(
  $$select private.process_sport_availability_notifications(
      current_setting('test.opens_at')::timestamptz + interval '1 minute'
    )$$,
  'le cron peut repasser sans erreur'
);

select is(
  (
    select count(*)
    from public.sport_availability_notification_events event
    where event.match_id = current_setting('test.timeline_match')::uuid
      and event.kind = 'availability_open'
  ),
  9::bigint,
  'le cron qui repasse chaque minute n’envoie jamais de doublon'
);

-- ---------------------------------------------------------------------------
-- 4. Convocations : réponses des joueurs puis calcul et publication.
-- ---------------------------------------------------------------------------
set local role authenticated;

select set_config(
  'test.convocation_match',
  public.create_internal_match_v3(
    '9a000000-0000-0000-0000-0000000000aa',
    current_setting('test.today')::date + 2,
    time '20:45',
    'Stade Timeline',
    'now',
    null,
    null
  )::text,
  true
);

-- Sept joueurs se déclarent disponibles eux-mêmes, deux se disent absents.
-- Le staff saisit ensuite les réponses des joueurs sans compte : sept
-- disponibles, un absent, trois sans réponse.
do $answers$
declare
  v_i integer;
  v_uid uuid;
begin
  for v_i in 1..9 loop
    v_uid := ('9a000000-0000-0000-0000-0000002000' || lpad(v_i::text, 2, '0'))::uuid;
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', v_uid, 'role', 'authenticated', 'aud', 'authenticated')::text,
      true
    );
    perform public.set_my_match_availability(
      current_setting('test.convocation_match')::uuid,
      case when v_i <= 7 then 'available' else 'absent' end,
      null
    );
  end loop;

  perform set_config(
    'request.jwt.claims',
    '{"sub":"9a000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
    true
  );

  for v_i in 10..17 loop
    perform public.admin_override_match_availability(
      current_setting('test.convocation_match')::uuid,
      ('9a000000-0000-0000-0000-0000001000' || lpad(v_i::text, 2, '0'))::uuid,
      case when v_i <= 16 then 'available' else 'absent' end,
      null,
      'saisie staff'
    );
  end loop;
end
$answers$;

set local role postgres;

select is(
  (
    select workflow.availability_state::text
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.convocation_match')::uuid
  ),
  'open',
  'un lancement immédiat ouvre tout de suite les disponibilités'
);

select is(
  (
    select count(*)
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.convocation_match')::uuid
      and participant.availability_status = 'available'
  ),
  14::bigint,
  'quatorze joueurs se déclarent disponibles'
);

select is(
  (
    select count(*)
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.convocation_match')::uuid
      and participant.availability_status = 'no_response'
  ),
  3::bigint,
  'trois joueurs restent sans réponse'
);

set local role authenticated;

select is(
  public.admin_recompute_match_convocations(
    current_setting('test.convocation_match')::uuid,
    false
  ) ->> 'convoked_count',
  '14',
  'tous les joueurs disponibles sont convoqués par défaut'
);

select is(
  public.admin_recompute_match_convocations(
    current_setting('test.convocation_match')::uuid,
    false
  ) ->> 'over_limit_count',
  '0',
  'quatorze convoqués ne dépassent jamais l’effectif d’un match entre nous'
);

set local role postgres;

select is(
  (
    select count(*)
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.convocation_match')::uuid
      and participant.availability_status <> 'available'
      and participant.convocation_status = 'convoked'
  ),
  0::bigint,
  'aucun joueur absent ou sans réponse n’est convoqué tout seul'
);

set local role authenticated;

select lives_ok(
  $$select public.admin_set_match_convocation(
      current_setting('test.convocation_match')::uuid,
      '9a000000-0000-0000-0000-000000100001'::uuid,
      'not_convoked',
      true,
      'choix du staff'
    )$$,
  'le staff peut écarter un joueur disponible'
);

select lives_ok(
  $$select public.admin_recompute_match_convocations(
      current_setting('test.convocation_match')::uuid,
      false
    )$$,
  'le recalcul des convocations reste possible après un choix manuel'
);

set local role postgres;

select is(
  (
    select participant.convocation_status::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.convocation_match')::uuid
      and participant.season_player_id = '9a000000-0000-0000-0000-000000100001'::uuid
  ),
  'not_convoked',
  'un recalcul ne réécrit jamais une décision prise par le staff'
);

set local role authenticated;

select lives_ok(
  $$select public.admin_publish_match_convocations(
      current_setting('test.convocation_match')::uuid,
      'convocations du match entre nous'
    )$$,
  'les convocations se publient sans erreur'
);

set local role postgres;

select is(
  (
    select workflow.convocation_state::text
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.convocation_match')::uuid
  ),
  'published',
  'les convocations publiées deviennent visibles pour les joueurs'
);

select isnt(
  (
    select workflow.convocation_published_at
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.convocation_match')::uuid
  ),
  null,
  'la date de publication des convocations est enregistrée'
);

set local role authenticated;

-- Un joueur qui répond après la publication est repris par le recalcul.
select lives_ok(
  $$select public.admin_override_match_availability(
      current_setting('test.convocation_match')::uuid,
      '9a000000-0000-0000-0000-000000100018'::uuid,
      'available',
      null,
      'réponse tardive'
    )$$,
  'une réponse tardive reste acceptée avant T-15'
);

select lives_ok(
  $$select public.admin_publish_match_convocations(
      current_setting('test.convocation_match')::uuid,
      null
    )$$,
  'republier après une réponse tardive ne bloque pas le staff'
);

set local role postgres;

select is(
  (
    select participant.convocation_status::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.convocation_match')::uuid
      and participant.season_player_id = '9a000000-0000-0000-0000-000000100018'::uuid
  ),
  'convoked',
  'le joueur qui répond tard n’est jamais oublié des convocations'
);

-- ---------------------------------------------------------------------------
-- 5. Verrou T-15 et fin automatique.
-- ---------------------------------------------------------------------------
insert into public.matches (
  id, season_id, match_date, match_time, kickoff_at, status,
  match_type, competition, location, planned_duration_minutes, created_by
)
values (
  '9a000000-0000-0000-0000-0000000000b1',
  '9a000000-0000-0000-0000-0000000000aa',
  current_setting('test.today')::date,
  ((now() + interval '10 minutes') at time zone 'Europe/Paris')::time,
  now() + interval '10 minutes',
  'a_venir',
  'entre_nous',
  'Championnat',
  'domicile',
  90,
  '9a000000-0000-0000-0000-000000000001'
),
(
  '9a000000-0000-0000-0000-0000000000b2',
  '9a000000-0000-0000-0000-0000000000aa',
  current_setting('test.today')::date + 1,
  time '20:00',
  ((current_setting('test.today')::date + 1)::timestamp + time '20:00')
    at time zone 'Europe/Paris',
  'a_venir',
  'entre_nous',
  'Championnat',
  'domicile',
  90,
  '9a000000-0000-0000-0000-000000000001'
),
(
  '9a000000-0000-0000-0000-0000000000b3',
  '9a000000-0000-0000-0000-0000000000aa',
  current_setting('test.today')::date - 1,
  time '20:45',
  ((current_setting('test.today')::date - 1)::timestamp + time '20:45')
    at time zone 'Europe/Paris',
  'a_venir',
  'entre_nous',
  'Championnat',
  'domicile',
  90,
  '9a000000-0000-0000-0000-000000000001'
);

set local role authenticated;

select throws_ok(
  format(
    $$select public.update_internal_match(
        '9a000000-0000-0000-0000-0000000000b1'::uuid,
        '9a000000-0000-0000-0000-0000000000aa'::uuid,
        %L::date,
        '21:00'::time,
        'Autre stade',
        %L::timestamptz
      )$$,
    current_setting('test.today')::date + 4,
    (select updated_at from public.matches where id = '9a000000-0000-0000-0000-0000000000b1')
  ),
  '22023',
  'Le match est verrouillé depuis l’ouverture du Live.',
  'un match entre nous ne se modifie plus après T-15'
);

select lives_ok(
  format(
    $$select public.update_internal_match(
        '9a000000-0000-0000-0000-0000000000b2'::uuid,
        '9a000000-0000-0000-0000-0000000000aa'::uuid,
        %L::date,
        '21:00'::time,
        'Autre stade',
        %L::timestamptz
      )$$,
    current_setting('test.today')::date + 3,
    (select updated_at from public.matches where id = '9a000000-0000-0000-0000-0000000000b2')
  ),
  'avant T-15, le match entre nous reste modifiable'
);

set local role postgres;

select lives_ok(
  $$select private.finish_due_internal_matches(now())$$,
  'la clôture automatique des matchs entre nous s’exécute sans erreur'
);

select is(
  (select status from public.matches where id = '9a000000-0000-0000-0000-0000000000b3'),
  'termine',
  'un match entre nous se termine seul après sa durée plus quinze minutes'
);

select is(
  (select status from public.matches where id = '9a000000-0000-0000-0000-0000000000b1'),
  'a_venir',
  'un match entre nous à venir n’est jamais terminé par erreur'
);

select * from finish();
rollback;
