begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- L'effectif bouge jusqu'au coup d'envoi. La feuille publiée doit suivre sans
-- exiger une nouvelle publication : le joueur qui s'en va laisse sa place
-- vide, celui qui arrive apparaît sur le banc, et celui que l'administrateur
-- avait volontairement laissé hors feuille y reste.

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'c9100000-0000-0000-0000-000000000001',
    'compo-suit-admin@example.invalid',
    '{"first_name":"Admin"}'::jsonb
  ),
  (
    'c9100000-0000-0000-0000-000000000002',
    'compo-suit-titulaire@example.invalid',
    '{"first_name":"Titulaire"}'::jsonb
  ),
  (
    'c9100000-0000-0000-0000-000000000003',
    'compo-suit-partant@example.invalid',
    '{"first_name":"Partant"}'::jsonb
  ),
  (
    'c9100000-0000-0000-0000-000000000004',
    'compo-suit-remplacant@example.invalid',
    '{"first_name":"Remplacant"}'::jsonb
  ),
  (
    'c9100000-0000-0000-0000-000000000005',
    'compo-suit-ecarte@example.invalid',
    '{"first_name":"Ecarte"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'c9100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'c9100000-0000-0000-0000-000000000001'
  and 'c9100000-0000-0000-0000-000000000005';

insert into public.seasons(id, name, status)
values ('c9200000-0000-0000-0000-000000000001', '2401-2402', 'open');

insert into public.opponents(id, name)
values ('c9300000-0000-0000-0000-000000000001', 'Effectif Vivant FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  (
    'c9400000-0000-0000-0000-000000000001',
    'c9200000-0000-0000-0000-000000000001',
    'Titulaire', 'Suit', false, true, 1,
    'c9100000-0000-0000-0000-000000000002'
  ),
  (
    'c9400000-0000-0000-0000-000000000002',
    'c9200000-0000-0000-0000-000000000001',
    'Partant', 'Suit', false, true, 2,
    'c9100000-0000-0000-0000-000000000003'
  ),
  (
    'c9400000-0000-0000-0000-000000000003',
    'c9200000-0000-0000-0000-000000000001',
    'Remplacant', 'Suit', false, true, 3,
    'c9100000-0000-0000-0000-000000000004'
  ),
  (
    'c9400000-0000-0000-0000-000000000004',
    'c9200000-0000-0000-0000-000000000001',
    'Ecarte', 'Suit', false, true, 4,
    'c9100000-0000-0000-0000-000000000005'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'c9100000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"c9100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.compo_suit_match',
  public.create_match_with_odds_and_sport_limit(
    'c9200000-0000-0000-0000-000000000001',
    'c9300000-0000-0000-0000-000000000001',
    ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '3 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 4
  )::text,
  true
);

reset role;

update public.match_sport_participants
set availability_status = 'available',
    availability_updated_at = now(),
    availability_updated_by = 'c9100000-0000-0000-0000-000000000001',
    updated_at = now()
where match_id = current_setting('test.compo_suit_match')::uuid;

create or replace function pg_temp.compo_suit_participant(p_season_player uuid)
returns uuid
language sql
stable
as $function$
  select participant.id
  from public.match_sport_participants participant
  where participant.match_id = current_setting('test.compo_suit_match')::uuid
    and participant.season_player_id = p_season_player;
$function$;

-- Trois convoqués, un laissé en réserve : c'est lui que la liste d'attente
-- promeut automatiquement quand un convoqué se désiste.
create or replace function pg_temp.compo_suit_decisions()
returns jsonb
language sql
stable
as $function$
  select jsonb_agg(
    jsonb_build_object(
      'season_player_id', player.id,
      'status', case
        when player.id = 'c9400000-0000-0000-0000-000000000003'::uuid
          then 'not_convoked'
        else 'convoked'
      end
    ) order by player.position
  )
  from public.season_players player
  where player.season_id = 'c9200000-0000-0000-0000-000000000001';
$function$;

-- Feuille de départ : deux titulaires, un convoqué volontairement laissé hors
-- feuille, et le réserviste qui ne peut pas y figurer.
create or replace function pg_temp.compo_suit_entries()
returns jsonb
language sql
stable
as $function$
  select jsonb_build_array(
    jsonb_build_object(
      'participant_id',
      pg_temp.compo_suit_participant('c9400000-0000-0000-0000-000000000001'),
      'zone', 'field', 'x', 0.5, 'y', 0.8, 'sort_order', 1
    ),
    jsonb_build_object(
      'participant_id',
      pg_temp.compo_suit_participant('c9400000-0000-0000-0000-000000000002'),
      'zone', 'field', 'x', 0.3, 'y', 0.4, 'sort_order', 2
    ),
    jsonb_build_object(
      'participant_id',
      pg_temp.compo_suit_participant('c9400000-0000-0000-0000-000000000003'),
      'zone', 'not_selected', 'x', null, 'y', null, 'sort_order', 3
    ),
    jsonb_build_object(
      'participant_id',
      pg_temp.compo_suit_participant('c9400000-0000-0000-0000-000000000004'),
      'zone', 'not_selected', 'x', null, 'y', null, 'sort_order', 4
    )
  );
$function$;

create or replace function pg_temp.compo_suit_zone(p_season_player uuid)
returns text
language sql
stable
as $function$
  select entry ->> 'zone'
  from jsonb_array_elements(
    public.get_published_match_composition(
      current_setting('test.compo_suit_match')::uuid
    ) -> 'entries'
  ) entry
  where entry ->> 'season_player_id' = p_season_player::text;
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"c9100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_publish_match_effectif(
    current_setting('test.compo_suit_match')::uuid,
    4,
    pg_temp.compo_suit_decisions(),
    'Effectif de départ'
  ) #>> '{convocation_state}',
  'published',
  'l’effectif de départ est écrit sans étape de validation supplémentaire'
);

select is(
  public.admin_save_match_composition(
    current_setting('test.compo_suit_match')::uuid,
    '4-4-2',
    pg_temp.compo_suit_entries(),
    false,
    'Feuille de départ'
  ) #>> '{version}',
  '1',
  'la composition est publiée dès son enregistrement'
);

select is(
  public.get_published_match_composition(
    current_setting('test.compo_suit_match')::uuid
  ) #>> '{field_count}',
  '2',
  'la feuille publiée part avec deux titulaires'
);

-- Un convoqué se désiste : la liste d'attente promeut le réserviste.
select isnt(
  public.admin_override_match_availability(
    current_setting('test.compo_suit_match')::uuid,
    'c9400000-0000-0000-0000-000000000002',
    'absent',
    null,
    'Désistement de dernière minute'
  ) #>> '{promoted_season_player_id}',
  null,
  'le désistement d’un convoqué promeut le premier réserviste disponible'
);

select is(
  pg_temp.compo_suit_zone('c9400000-0000-0000-0000-000000000002'),
  'not_selected',
  'le joueur qui quitte l’effectif libère sa place sur le terrain'
);

select is(
  public.get_published_match_composition(
    current_setting('test.compo_suit_match')::uuid
  ) #>> '{field_count}',
  '1',
  'la place libérée reste vide : personne ne la comble automatiquement'
);

select is(
  pg_temp.compo_suit_zone('c9400000-0000-0000-0000-000000000003'),
  'bench',
  'le joueur convoqué après la publication apparaît sur le banc'
);

select is(
  pg_temp.compo_suit_zone('c9400000-0000-0000-0000-000000000004'),
  'not_selected',
  'un convoqué volontairement laissé hors feuille n’y entre pas tout seul'
);

select is(
  pg_temp.compo_suit_zone('c9400000-0000-0000-0000-000000000001'),
  'field',
  'le titulaire inchangé garde sa place'
);

-- Un invité ajouté après la feuille est convoqué d'office : il doit lui aussi
-- rejoindre le banc, sans nouvelle publication.
select set_config(
  'test.compo_suit_guest',
  public.admin_add_or_reuse_match_guest(
    current_setting('test.compo_suit_match')::uuid,
    null,
    'Invite',
    'Tardif',
    false,
    'Invité ajouté après la feuille'
  ) #>> '{participant_id}',
  true
);

select is(
  (
    select entry ->> 'zone'
    from jsonb_array_elements(
      public.get_published_match_composition(
        current_setting('test.compo_suit_match')::uuid
      ) -> 'entries'
    ) entry
    where entry ->> 'participant_id' = current_setting('test.compo_suit_guest')
  ),
  'bench',
  'un invité ajouté après la feuille apparaît sur le banc'
);

reset role;
select * from finish();
rollback;
