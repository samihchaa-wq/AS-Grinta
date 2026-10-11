begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Match annulé, reporté ou déplacé : trois notifications essentielles,
-- déclenchées par la modification du match lui-même.
--
-- * heure changée le même jour      → « Horaire du match modifié » ;
-- * date changée                    → « Match reporté », disponibilités
--                                     redemandées ;
-- * match annulé                    → « Match annulé » ;
-- * avant l'ouverture des disponibilités, rien ne part ;
-- * le coupe-circuit des notifications arrête l'envoi, pas le changement.
--
-- Les envois sont lus dans la file de pg_net, à l'intérieur de la
-- transaction du test : rien ne part réellement, tout est annulé à la fin.

select vault.create_secret('test-token', 'push_internal_token')
where not exists (
  select 1 from vault.secrets secret where secret.name = 'push_internal_token'
);

update private.app_feature_flags
set enabled = false
where key = 'notifications_paused';

insert into auth.users(id, email, raw_user_meta_data)
values
  ('e8100000-0000-0000-0000-000000000001', 'match-change-admin@example.invalid',
   '{"first_name":"Admin"}'::jsonb),
  ('e8100000-0000-0000-0000-000000000002', 'match-change-player@example.invalid',
   '{"first_name":"Joueur"}'::jsonb);

update public.profiles
set role = case
      when id = 'e8100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'e8100000-0000-0000-0000-000000000001',
  'e8100000-0000-0000-0000-000000000002'
);

insert into public.seasons(id, name, status)
values ('e8200000-0000-0000-0000-000000000001', '2109-2110', 'open');

insert into public.opponents(id, name)
values ('e8300000-0000-0000-0000-000000000001', 'Report FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
) values (
  'e8400000-0000-0000-0000-000000000001',
  'e8200000-0000-0000-0000-000000000001',
  'Joueur', 'Report', false, true, 1,
  'e8100000-0000-0000-0000-000000000002'
);

-- Le premier match se joue dans trois jours à 18 h, heure de Paris : ses
-- disponibilités sont ouvertes. Le second, dans trois semaines : elles ne le
-- sont pas encore.
insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, kickoff_at,
  location, planned_duration_minutes, status, created_by
) values
  (
    'e8500000-0000-0000-0000-000000000001',
    'e8200000-0000-0000-0000-000000000001',
    'e8300000-0000-0000-0000-000000000001',
    (now() at time zone 'Europe/Paris')::date + 3,
    time '18:00',
    (((now() at time zone 'Europe/Paris')::date + 3) + time '18:00')
      at time zone 'Europe/Paris',
    'domicile', 90, 'a_venir',
    'e8100000-0000-0000-0000-000000000001'
  ),
  (
    'e8500000-0000-0000-0000-000000000002',
    'e8200000-0000-0000-0000-000000000001',
    'e8300000-0000-0000-0000-000000000001',
    (now() at time zone 'Europe/Paris')::date + 21,
    time '18:00',
    (((now() at time zone 'Europe/Paris')::date + 21) + time '18:00')
      at time zone 'Europe/Paris',
    'domicile', 90, 'a_venir',
    'e8100000-0000-0000-0000-000000000001'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'e8100000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"e8100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
select private.sync_match_sport_workflow('e8500000-0000-0000-0000-000000000001');
select private.sync_match_sport_workflow('e8500000-0000-0000-0000-000000000002');

update public.match_sport_workflows
set availability_state = 'open',
    availability_opens_at = now() - interval '1 hour',
    availability_opened_at = now() - interval '1 hour'
where match_id = 'e8500000-0000-0000-0000-000000000001';

update public.match_sport_participants
set availability_status = 'available',
    availability_updated_at = now(),
    updated_at = now()
where match_id = 'e8500000-0000-0000-0000-000000000001'
  and season_player_id = 'e8400000-0000-0000-0000-000000000001';

insert into public.push_subscriptions(profile_id, endpoint, p256dh, auth)
values (
  'e8100000-0000-0000-0000-000000000002',
  'https://push.example.invalid/match-change',
  'p256dh-test',
  'auth-test'
);

-- Types des envois de match mis en file après le repère, dans l'ordre.
create or replace function pg_temp.match_pushes_since(p_marker bigint)
returns text
language sql
stable
as $function$
  select coalesce(string_agg(
    (convert_from(queue.body, 'UTF8')::jsonb ->> 'kind')
      || ' → ' || right(convert_from(queue.body, 'UTF8')::jsonb ->> 'match_id', 1),
    ' | ' order by queue.id
  ), '')
  from net.http_request_queue queue
  where queue.id > p_marker
    and convert_from(queue.body, 'UTF8')::jsonb ->> 'kind' in (
      'match_cancelled', 'match_rescheduled_date', 'match_rescheduled_time'
    );
$function$;

create or replace function pg_temp.mark()
returns text
language sql
as $function$
  select set_config(
    'test.marker',
    (select coalesce(max(id), 0) from net.http_request_queue)::text,
    true
  );
$function$;

create or replace function pg_temp.move_match(
  p_match uuid,
  p_days integer,
  p_time time
)
returns void
language sql
as $function$
  update public.matches
  set match_date = (now() at time zone 'Europe/Paris')::date + p_days,
      match_time = p_time,
      kickoff_at = (((now() at time zone 'Europe/Paris')::date + p_days) + p_time)
        at time zone 'Europe/Paris'
  where id = p_match;
$function$;

-- ---------------------------------------------------------------------------
-- Le message est préparé pour les joueurs du match
-- ---------------------------------------------------------------------------

select is(
  (
    select string_agg(subscription ->> 'profile_id', ',')
    from jsonb_array_elements(
      public.internal_push_dispatch(
        'match_cancelled', 'e8500000-0000-0000-0000-000000000001'
      ) -> 'subscriptions'
    ) subscription
  ),
  'e8100000-0000-0000-0000-000000000002',
  'l''annulation vise le joueur du match abonné aux notifications'
);

-- ---------------------------------------------------------------------------
-- Heure changée, même jour
-- ---------------------------------------------------------------------------

select pg_temp.mark();
select pg_temp.move_match('e8500000-0000-0000-0000-000000000001', 3, time '20:00');

select is(
  pg_temp.match_pushes_since(current_setting('test.marker')::bigint),
  'match_rescheduled_time → 1',
  'une nouvelle heure le même jour annonce « Horaire du match modifié »'
);

select is(
  (
    select participant.availability_status::text
    from public.match_sport_participants participant
    where participant.match_id = 'e8500000-0000-0000-0000-000000000001'
      and participant.season_player_id = 'e8400000-0000-0000-0000-000000000001'
  ),
  'available',
  'un simple changement d''heure garde les disponibilités'
);

-- ---------------------------------------------------------------------------
-- Date changée
-- ---------------------------------------------------------------------------

select pg_temp.mark();
select pg_temp.move_match('e8500000-0000-0000-0000-000000000001', 4, time '20:00');

select is(
  pg_temp.match_pushes_since(current_setting('test.marker')::bigint),
  'match_rescheduled_date → 1',
  'une nouvelle date annonce « Match reporté »'
);

select is(
  (
    select participant.availability_status::text
    from public.match_sport_participants participant
    where participant.match_id = 'e8500000-0000-0000-0000-000000000001'
      and participant.season_player_id = 'e8400000-0000-0000-0000-000000000001'
  ),
  'no_response',
  'un report redemande les disponibilités'
);

-- ---------------------------------------------------------------------------
-- Coupe-circuit : le match change, la notification ne part pas
-- ---------------------------------------------------------------------------

update private.app_feature_flags
set enabled = true
where key = 'notifications_paused';

select pg_temp.mark();
select pg_temp.move_match('e8500000-0000-0000-0000-000000000001', 4, time '21:00');

select is(
  pg_temp.match_pushes_since(current_setting('test.marker')::bigint),
  '',
  'en pause, un changement d''heure n''envoie rien'
);

select is(
  (
    select to_char(match.kickoff_at at time zone 'Europe/Paris', 'HH24:MI')
    from public.matches match
    where match.id = 'e8500000-0000-0000-0000-000000000001'
  ),
  '21:00',
  'en pause, le changement d''heure est bien enregistré'
);

update private.app_feature_flags
set enabled = false
where key = 'notifications_paused';

-- ---------------------------------------------------------------------------
-- Annulation
-- ---------------------------------------------------------------------------

select pg_temp.mark();
select set_config(
  'request.jwt.claims',
  '{"sub":"e8100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.cancel_match('e8500000-0000-0000-0000-000000000002');
select public.cancel_match('e8500000-0000-0000-0000-000000000001');
reset role;

select is(
  pg_temp.match_pushes_since(current_setting('test.marker')::bigint),
  'match_cancelled → 1',
  'seul le match aux disponibilités ouvertes annonce son annulation'
);

select is(
  (
    select string_agg(match.status::text, ',' order by match.id)
    from public.matches match
    where match.id in (
      'e8500000-0000-0000-0000-000000000001',
      'e8500000-0000-0000-0000-000000000002'
    )
  ),
  'annule,annule',
  'les deux matchs sont bien annulés'
);

select * from finish();
rollback;
