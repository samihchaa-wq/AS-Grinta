begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- ---------------------------------------------------------------------------
-- Le coach est un membre du club comme les autres : il répond, il est notifié,
-- il apparaît dans l'effectif et il vote. Il reste seulement en dehors de la
-- rotation, de la composition et des statistiques joueurs.
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data)
values
  ('8a000000-0000-0000-0000-000000000001',
   'coach-member-admin@example.invalid',
   '{"first_name":"Admin","last_name":"Coach"}'::jsonb),
  ('8a000000-0000-0000-0000-000000000002',
   'coach-member-philippe@example.invalid',
   '{"first_name":"Philippe","last_name":"Coach"}'::jsonb),
  ('8a000000-0000-0000-0000-000000000003',
   'coach-member-alice@example.invalid',
   '{"first_name":"Alice","last_name":"Joueuse"}'::jsonb),
  ('8a000000-0000-0000-0000-000000000004',
   'coach-member-bruno@example.invalid',
   '{"first_name":"Bruno","last_name":"Joueur"}'::jsonb);

update public.profiles
set role = case
      when id = '8a000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    notify_match_reminders = true,
    notify_motm_vote = true,
    updated_at = now()
where id between
  '8a000000-0000-0000-0000-000000000001'
  and '8a000000-0000-0000-0000-000000000004';

insert into public.seasons (id, name, status)
values ('8b000000-0000-0000-0000-000000000001', '2096-2097', 'open');

insert into public.opponents (id, name)
values ('8c000000-0000-0000-0000-000000000001', 'Coach FC');

insert into public.season_players (
  id, season_id, first_name, last_name,
  is_goalkeeper, is_active, is_coach, position, profile_id
)
values
  ('8d000000-0000-0000-0000-000000000001',
   '8b000000-0000-0000-0000-000000000001',
   'Philippe', 'Coach', false, true, true, 1,
   '8a000000-0000-0000-0000-000000000002'),
  ('8d000000-0000-0000-0000-000000000002',
   '8b000000-0000-0000-0000-000000000001',
   'Alice', 'Joueuse', false, true, false, 2,
   '8a000000-0000-0000-0000-000000000003'),
  ('8d000000-0000-0000-0000-000000000003',
   '8b000000-0000-0000-0000-000000000001',
   'Bruno', 'Joueur', false, true, false, 3,
   '8a000000-0000-0000-0000-000000000004');

insert into public.push_subscriptions (profile_id, endpoint, p256dh, auth, user_agent)
values
  ('8a000000-0000-0000-0000-000000000002',
   'https://push.example.invalid/coach-member-philippe', 'k1', 'a1', 'pgTAP'),
  ('8a000000-0000-0000-0000-000000000003',
   'https://push.example.invalid/coach-member-alice', 'k2', 'a2', 'pgTAP');

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '8a000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"8a000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.coach_match',
  public.create_match_with_odds_and_sport_limit(
    '8b000000-0000-0000-0000-000000000001',
    '8c000000-0000-0000-0000-000000000001',
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
where match_id = current_setting('test.coach_match')::uuid;

-- ---------------------------------------------------------------------------
-- 1. Le coach reste hors rotation.
-- ---------------------------------------------------------------------------

select ok(
  exists (
    select 1
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.coach_match')::uuid
      and participant.season_player_id = '8d000000-0000-0000-0000-000000000001'
  ),
  'le coach a bien une ligne de participation sur le match'
);

select ok(
  not exists (
    select 1
    from public.sport_waitlist_entries entry
    where entry.season_player_id = '8d000000-0000-0000-0000-000000000001'
  ),
  'le coach n’entre jamais dans la liste d’attente'
);

-- ---------------------------------------------------------------------------
-- 2. Il répond à sa disponibilité comme tout le monde.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"8a000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  (
    public.get_my_match_availability(
      current_setting('test.coach_match')::uuid
    ) ->> 'can_respond'
  )::boolean,
  'le coach peut répondre présent ou absent'
);

select set_config(
  'test.coach_answer',
  public.set_my_match_availability(
    current_setting('test.coach_match')::uuid, 'available', null
  )::text,
  true
);

reset role;

-- ---------------------------------------------------------------------------
-- 3. Sa réponse le pose dans l'effectif, sans toucher au quota des joueurs.
-- ---------------------------------------------------------------------------

select is(
  (
    select participant.convocation_status::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.coach_match')::uuid
      and participant.season_player_id = '8d000000-0000-0000-0000-000000000001'
  ),
  'convoked',
  'le coach présent est convoqué dans l’effectif'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"8a000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.coach_convocations',
  public.admin_get_match_convocations(
    current_setting('test.coach_match')::uuid
  )::text,
  true
);

reset role;

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      current_setting('test.coach_convocations')::jsonb -> 'players'
    ) player
    where player ->> 'season_player_id' = '8d000000-0000-0000-0000-000000000001'
      and (player ->> 'is_coach')::boolean
      and player ->> 'convocation_status' = 'convoked'
  ),
  'l’effectif affiche le coach, identifié comme coach'
);

select is(
  (current_setting('test.coach_convocations')::jsonb ->> 'convoked_count'),
  '0',
  'le coach ne consomme aucune place du quota de convoqués'
);

select is(
  (current_setting('test.coach_convocations')::jsonb ->> 'available_count'),
  '0',
  'le coach ne compte pas parmi les joueurs disponibles'
);

-- ---------------------------------------------------------------------------
-- 4. Un joueur disponible garde exactement sa place.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"8a000000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.alice_answer',
  public.set_my_match_availability(
    current_setting('test.coach_match')::uuid, 'available', null
  )::text,
  true
);

select set_config(
  'request.jwt.claims',
  '{"sub":"8a000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);

select set_config(
  'test.coach_convocations_2',
  public.admin_get_match_convocations(
    current_setting('test.coach_match')::uuid
  )::text,
  true
);

reset role;

select is(
  (current_setting('test.coach_convocations_2')::jsonb ->> 'convoked_count'),
  '1',
  'seule la joueuse disponible compte dans les convoqués'
);

select is(
  (
    select count(*)::bigint
    from jsonb_array_elements(
      current_setting('test.coach_convocations_2')::jsonb -> 'players'
    ) player
  ),
  3::bigint,
  'l’effectif liste les deux joueurs de rotation et le coach'
);

-- ---------------------------------------------------------------------------
-- 5. Il est notifié comme les joueurs.
-- ---------------------------------------------------------------------------

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      public.internal_sport_push_dispatch(
        'availability_open',
        current_setting('test.coach_match')::uuid,
        array[
          '8a000000-0000-0000-0000-000000000002'::uuid,
          '8a000000-0000-0000-0000-000000000003'::uuid
        ]
      ) -> 'subscriptions'
    ) subscription
    where subscription ->> 'profile_id' = '8a000000-0000-0000-0000-000000000002'
  ),
  'le coach reçoit la notification d’ouverture des disponibilités'
);

update public.match_sport_participants
set availability_status = 'no_response',
    availability_updated_at = null
where match_id = current_setting('test.coach_match')::uuid
  and season_player_id = '8d000000-0000-0000-0000-000000000001';

select set_config(
  'request.jwt.claims',
  '{"sub":"8a000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.coach_reminders',
  public.admin_get_match_availability_reminders(
    current_setting('test.coach_match')::uuid
  )::text,
  true
);

reset role;

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      current_setting('test.coach_reminders')::jsonb -> 'players'
    ) player
    where player ->> 'season_player_id' = '8d000000-0000-0000-0000-000000000001'
  ),
  'un admin peut relancer le coach resté sans réponse'
);

-- ---------------------------------------------------------------------------
-- 6. Homme du match : il vote, il n'est pas candidat.
-- ---------------------------------------------------------------------------

update public.match_sport_participants
set availability_status = 'available',
    convocation_status = 'convoked'
where match_id = current_setting('test.coach_match')::uuid
  and season_player_id = '8d000000-0000-0000-0000-000000000001';

select ok(
  private.match_motm_voter_participant(
    current_setting('test.coach_match')::uuid,
    '8a000000-0000-0000-0000-000000000002'
  ) is not null,
  'le coach convoqué détient un bulletin de vote'
);

select ok(
  not exists (
    select 1
    from private.match_motm_candidate_participants(
      current_setting('test.coach_match')::uuid
    ) candidate
    join public.match_sport_participants participant
      on participant.id = candidate.participant_id
    where participant.season_player_id = '8d000000-0000-0000-0000-000000000001'
  ),
  'le coach n’est jamais candidat à l’Homme du match'
);

-- ---------------------------------------------------------------------------
-- 7. Statistiques joueurs et pari de saison : il n'y est pas une cible.
-- ---------------------------------------------------------------------------

select ok(
  not exists (
    select 1
    from public.v_statistics_players stat
    where stat.profile_id = '8a000000-0000-0000-0000-000000000002'
  ),
  'le coach n’apparaît pas dans les statistiques joueurs'
);

-- ---------------------------------------------------------------------------
-- 8. Composition et Live : le coach reste hors de la feuille de match.
--
-- Tout s'appuie sur un seul fait : le coach n'est jamais un participant
-- « éligible ». C'est ce drapeau que la composition, l'alignement du Live et
-- les statistiques joueurs contrôlent, chacun de leur côté.
-- ---------------------------------------------------------------------------

select ok(
  not (
    select participant.is_eligible
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.coach_match')::uuid
      and participant.season_player_id = '8d000000-0000-0000-0000-000000000001'
  ),
  'le coach convoqué n’est jamais un participant de rotation'
);

select is(
  (
    select count(*)::bigint
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.coach_match')::uuid
      and participant.is_eligible
  ),
  2::bigint,
  'la composition n’attend que les deux joueurs de rotation, jamais le coach'
);

select * from finish();
rollback;
