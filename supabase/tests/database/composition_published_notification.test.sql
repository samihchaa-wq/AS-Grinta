begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- La mise en ligne d'une composition prévient les convoqués, et une seule
-- fois : les retouches suivantes ne renotifient personne. La garantie ne vient
-- pas des appelants mais de la clé primaire du journal d'envoi, vérifiée ici.

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'c8100000-0000-0000-0000-000000000001',
    'compo-notif-admin@example.invalid',
    '{"first_name":"Admin"}'::jsonb
  ),
  (
    'c8100000-0000-0000-0000-000000000002',
    'compo-notif-un@example.invalid',
    '{"first_name":"Titulaire"}'::jsonb
  ),
  (
    'c8100000-0000-0000-0000-000000000003',
    'compo-notif-deux@example.invalid',
    '{"first_name":"Second"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'c8100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'c8100000-0000-0000-0000-000000000001'
  and 'c8100000-0000-0000-0000-000000000003';

select ok(
  (
    select bool_and(notify_composition)
    from public.profiles
    where id between
      'c8100000-0000-0000-0000-000000000001'
      and 'c8100000-0000-0000-0000-000000000003'
  ),
  'le réglage « composition en ligne » est actif par défaut'
);

insert into public.seasons(id, name, status)
values ('c8200000-0000-0000-0000-000000000001', '2501-2502', 'open');

insert into public.opponents(id, name)
values ('c8300000-0000-0000-0000-000000000001', 'Notif Compo FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  (
    'c8400000-0000-0000-0000-000000000001',
    'c8200000-0000-0000-0000-000000000001',
    'Titulaire', 'Notif', true, true, 1,
    'c8100000-0000-0000-0000-000000000002'
  ),
  (
    'c8400000-0000-0000-0000-000000000002',
    'c8200000-0000-0000-0000-000000000001',
    'Second', 'Notif', false, true, 2,
    'c8100000-0000-0000-0000-000000000003'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'c8100000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"c8100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.compo_notif_match',
  public.create_match_with_odds_and_sport_limit(
    'c8200000-0000-0000-0000-000000000001',
    'c8300000-0000-0000-0000-000000000001',
    ((now() + interval '4 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '4 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 4
  )::text,
  true
);

reset role;

update public.match_sport_participants
set availability_status = 'available',
    availability_updated_at = now(),
    availability_updated_by = 'c8100000-0000-0000-0000-000000000001',
    updated_at = now()
where match_id = current_setting('test.compo_notif_match')::uuid;

create or replace function pg_temp.compo_notif_participant(p_season_player uuid)
returns uuid
language sql
stable
as $function$
  select participant.id
  from public.match_sport_participants participant
  where participant.match_id = current_setting('test.compo_notif_match')::uuid
    and participant.season_player_id = p_season_player;
$function$;

create or replace function pg_temp.compo_notif_entries(p_second_zone text)
returns jsonb
language sql
stable
as $function$
  select jsonb_build_array(
    jsonb_build_object(
      'participant_id',
      pg_temp.compo_notif_participant('c8400000-0000-0000-0000-000000000001'),
      'zone', 'field', 'x', 0.5, 'y', 0.9, 'sort_order', 1
    ),
    jsonb_build_object(
      'participant_id',
      pg_temp.compo_notif_participant('c8400000-0000-0000-0000-000000000002'),
      'zone', p_second_zone,
      'x', case when p_second_zone = 'field' then 0.5 else null end,
      'y', case when p_second_zone = 'field' then 0.4 else null end,
      'sort_order', 2
    )
  );
$function$;

-- Le journal d'envoi est fermé aux comptes joueurs, et doit le rester : on le
-- lit donc hors de leur rôle, comme le ferait un exploitant.
create or replace function pg_temp.compo_notif_log_count()
returns bigint
language sql
stable
security definer
set search_path = ''
as $function$
  select count(*)
  from public.push_notification_log log
  where log.match_id = pg_catalog.current_setting('test.compo_notif_match')::uuid
    and log.kind = 'composition_published';
$function$;

select ok(
  not has_table_privilege('authenticated', 'public.push_notification_log', 'SELECT'),
  'le journal des envois reste fermé aux comptes joueurs'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c8100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_publish_match_effectif(
    current_setting('test.compo_notif_match')::uuid,
    4,
    jsonb_build_array(
      jsonb_build_object(
        'season_player_id', 'c8400000-0000-0000-0000-000000000001',
        'status', 'convoked'
      ),
      jsonb_build_object(
        'season_player_id', 'c8400000-0000-0000-0000-000000000002',
        'status', 'convoked'
      )
    ),
    'Effectif du test de notification'
  ) #>> '{convocation_state}',
  'published',
  'l’effectif est écrit avant la composition'
);

select is(
  pg_temp.compo_notif_log_count(),
  0::bigint,
  'écrire l’effectif ne prévient personne de la composition'
);

select is(
  public.admin_save_match_composition(
    current_setting('test.compo_notif_match')::uuid,
    '4-4-2',
    pg_temp.compo_notif_entries('bench'),
    false,
    'Première feuille'
  ) #>> '{version}',
  '1',
  'la première feuille est publiée'
);

select is(
  pg_temp.compo_notif_log_count(),
  1::bigint,
  'la première mise en ligne prévient les convoqués, une fois'
);

select is(
  public.admin_save_match_composition(
    current_setting('test.compo_notif_match')::uuid,
    '4-4-2',
    pg_temp.compo_notif_entries('field'),
    false,
    'Feuille retouchée'
  ) #>> '{version}',
  '2',
  'la feuille peut être retouchée'
);

select is(
  pg_temp.compo_notif_log_count(),
  1::bigint,
  'une retouche ne renotifie personne'
);

-- Le réglage personnel reste modifiable, y compris depuis une page restée sur
-- l'ancienne version qui n'envoie que trois arguments.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"c8100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.update_my_notification_preferences(true, true, true, false),
  'un joueur peut couper la notification de composition'
);

-- Relu comme l'application le fait : par la RPC de profil, la table elle-même
-- n'étant pas lisible directement par un compte joueur.
select is(
  public.get_my_profile() ->> 'notify_composition',
  'false',
  'le choix du joueur est enregistré'
);

select ok(
  public.update_my_notification_preferences(true, true, true),
  'l’appel à trois arguments reste accepté'
);

select is(
  public.get_my_profile() ->> 'notify_composition',
  'false',
  'et il laisse le réglage de composition intact'
);

reset role;
select * from finish();
rollback;
