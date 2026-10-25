begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Un joueur qui s'était dit absent puis se dit présent après la publication
-- de l'effectif prend son rang dans la liste d'attente, comme un joueur qui
-- répond pour la première fois. Il ne tombe plus d'office en liste
-- d'attente quand un convoqué placé avant lui dans la liste devrait y
-- passer à sa place.
--
-- Ordre de la liste d'attente : Alice n°1, Bruno n°2, Chloé n°3. Les
-- derniers de la liste gardent leur place en priorité : Alice est la
-- première à tomber en attente, Chloé la dernière.

select vault.create_secret('test-token', 'push_internal_token')
where not exists (
  select 1 from vault.secrets secret where secret.name = 'push_internal_token'
);

update private.app_feature_flags
set enabled = false
where key = 'notifications_paused';

insert into auth.users(id, email, raw_user_meta_data)
values
  ('f5610000-0000-0000-0000-000000000001', 'returning-absent-admin@example.invalid',
   '{"first_name":"Admin"}'::jsonb),
  ('f5610000-0000-0000-0000-000000000002', 'returning-absent-alice@example.invalid',
   '{"first_name":"Alice"}'::jsonb),
  ('f5610000-0000-0000-0000-000000000003', 'returning-absent-bruno@example.invalid',
   '{"first_name":"Bruno"}'::jsonb),
  ('f5610000-0000-0000-0000-000000000004', 'returning-absent-chloe@example.invalid',
   '{"first_name":"Chloé"}'::jsonb);

update public.profiles
set role = case
      when id = 'f5610000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'f5610000-0000-0000-0000-000000000001'
  and 'f5610000-0000-0000-0000-000000000004';

insert into public.seasons(id, name, status)
values ('f5620000-0000-0000-0000-000000000001', '2601-2602', 'open');

insert into public.opponents(id, name)
values ('f5630000-0000-0000-0000-000000000001', 'Retour FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  ('f5640000-0000-0000-0000-000000000001',
   'f5620000-0000-0000-0000-000000000001', 'Alice', 'Retour', false, true, 1,
   'f5610000-0000-0000-0000-000000000002'),
  ('f5640000-0000-0000-0000-000000000002',
   'f5620000-0000-0000-0000-000000000001', 'Bruno', 'Retour', false, true, 2,
   'f5610000-0000-0000-0000-000000000003'),
  ('f5640000-0000-0000-0000-000000000003',
   'f5620000-0000-0000-0000-000000000001', 'Chloé', 'Retour', false, true, 3,
   'f5610000-0000-0000-0000-000000000004');

insert into public.sport_waitlist_entries(
  season_id, season_player_id, position, source, created_by, updated_by
)
select
  player.season_id, player.id, player.position, 'manual',
  'f5610000-0000-0000-0000-000000000001',
  'f5610000-0000-0000-0000-000000000001'
from public.season_players player
where player.season_id = 'f5620000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'f5610000-0000-0000-0000-000000000001'
where key = 'sports_management';

-- « titre → prénom » pour chaque envoi de convocation ou de liste d'attente
-- mis en file après le repère, du plus ancien au plus récent.
create or replace function pg_temp.pushes_since(p_marker bigint)
returns text
language sql
stable
as $function$
  select coalesce(string_agg(
    (convert_from(queue.body, 'UTF8')::jsonb ->> 'title')
      || ' → ' || (
        select profile.first_name
        from public.profiles profile
        where profile.id = (
          convert_from(queue.body, 'UTF8')::jsonb #>> '{profile_ids,0}'
        )::uuid
      ),
    ' | ' order by queue.id
  ), '')
  from net.http_request_queue queue
  where queue.id > p_marker
    and convert_from(queue.body, 'UTF8')::jsonb ->> 'title' in (
      'Tu es convoqué', 'Tu passes en liste d''attente'
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

-- Décisions telles que l'écran les envoie quand l'admin ne déplace personne.
create or replace function pg_temp.untouched_decisions(p_match uuid)
returns jsonb
language sql
stable
as $function$
  select jsonb_agg(jsonb_build_object(
    'season_player_id', participant.season_player_id,
    'status', coalesce(
      nullif(participant.convocation_status::text, 'not_applicable'),
      'not_convoked'
    ),
    'changed', false
  ))
  from public.match_sport_participants participant
  where participant.match_id = p_match
    and participant.availability_status = 'available';
$function$;

-- « Alice convoked / Bruno convoked / Chloé not_applicable » : l'effectif
-- du match, dans l'ordre de la liste d'attente.
create or replace function pg_temp.effectif(p_match uuid)
returns text
language sql
stable
as $function$
  select string_agg(
    player.first_name || ' ' || participant.convocation_status::text,
    ' / ' order by player.position
  )
  from public.match_sport_participants participant
  join public.season_players player
    on player.id = participant.season_player_id
  where participant.match_id = p_match;
$function$;

create or replace function pg_temp.as_profile(p_profile uuid)
returns text
language sql
as $function$
  select set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_profile, 'role', 'authenticated', 'aud', 'authenticated'
    )::text,
    true
  );
$function$;

-- ---------------------------------------------------------------------------
-- 1. Le cas réel : la dernière de la liste revient après la publication
-- ---------------------------------------------------------------------------

select pg_temp.as_profile('f5610000-0000-0000-0000-000000000001');
set local role authenticated;

select set_config(
  'test.match_rank',
  public.create_match_with_odds_and_sport_limit(
    'f5620000-0000-0000-0000-000000000001',
    'f5630000-0000-0000-0000-000000000001',
    ((now() + interval '4 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '4 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 2
  )::text,
  true
);

reset role;

-- Alice et Bruno sont présents, Chloé absente : deux places, deux convoqués.
select pg_temp.as_profile('f5610000-0000-0000-0000-000000000002');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match_rank')::uuid, 'available', null
);
reset role;

select pg_temp.as_profile('f5610000-0000-0000-0000-000000000003');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match_rank')::uuid, 'available', null
);
reset role;

select pg_temp.as_profile('f5610000-0000-0000-0000-000000000004');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match_rank')::uuid, 'absent', null
);
reset role;

select set_config(
  'test.decisions_rank',
  pg_temp.untouched_decisions(current_setting('test.match_rank')::uuid)::text,
  true
);
select pg_temp.as_profile('f5610000-0000-0000-0000-000000000001');
set local role authenticated;
select public.admin_save_match_effectif(
  current_setting('test.match_rank')::uuid,
  2,
  current_setting('test.decisions_rank')::jsonb,
  'Publication'
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match_rank')::uuid),
  'Alice convoked / Bruno convoked / Chloé not_applicable',
  'à la publication, Alice et Bruno sont convoqués, Chloé est absente'
);

-- Chloé change d'avis. Dernière de la liste, elle passe avant Alice, n°1.
select pg_temp.mark();
select pg_temp.as_profile('f5610000-0000-0000-0000-000000000004');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match_rank')::uuid, 'available', null
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match_rank')::uuid),
  'Alice not_convoked / Bruno convoked / Chloé convoked',
  'Chloé, revenue, prend son rang : Alice, n°1 de la liste, passe en attente'
);

select ok(
  (
    select not participant.convocation_manual_override
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.match_rank')::uuid
      and participant.season_player_id = 'f5640000-0000-0000-0000-000000000003'
  ),
  'la place de Chloé reste automatique, comme celle des autres joueurs'
);

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  'Tu passes en liste d''attente → Alice',
  'seule Alice, qui perd sa place, est prévenue'
);

-- ---------------------------------------------------------------------------
-- 2. La première de la liste revient : elle va en attente, personne ne bouge
-- ---------------------------------------------------------------------------

select pg_temp.as_profile('f5610000-0000-0000-0000-000000000001');
set local role authenticated;

select set_config(
  'test.match_first',
  public.create_match_with_odds_and_sport_limit(
    'f5620000-0000-0000-0000-000000000001',
    'f5630000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 2
  )::text,
  true
);

select public.admin_override_match_availability(
  current_setting('test.match_first')::uuid,
  'f5640000-0000-0000-0000-000000000001', 'absent', null, 'Test'
);
select public.admin_override_match_availability(
  current_setting('test.match_first')::uuid,
  'f5640000-0000-0000-0000-000000000002', 'available', null, 'Test'
);
select public.admin_override_match_availability(
  current_setting('test.match_first')::uuid,
  'f5640000-0000-0000-0000-000000000003', 'available', null, 'Test'
);

reset role;

select set_config(
  'test.decisions_first',
  pg_temp.untouched_decisions(current_setting('test.match_first')::uuid)::text,
  true
);
select pg_temp.as_profile('f5610000-0000-0000-0000-000000000001');
set local role authenticated;
select public.admin_save_match_effectif(
  current_setting('test.match_first')::uuid,
  2,
  current_setting('test.decisions_first')::jsonb,
  'Publication'
);
reset role;

select pg_temp.mark();
select pg_temp.as_profile('f5610000-0000-0000-0000-000000000001');
set local role authenticated;
select public.admin_override_match_availability(
  current_setting('test.match_first')::uuid,
  'f5640000-0000-0000-0000-000000000001', 'available', null, 'Retour'
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match_first')::uuid),
  'Alice not_convoked / Bruno convoked / Chloé convoked',
  'Alice, n°1 de la liste, revient et passe en attente sans déplacer personne'
);

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  'Tu passes en liste d''attente → Alice',
  'Alice est prévenue de son entrée en liste d''attente'
);

-- ---------------------------------------------------------------------------
-- 3. Inchangé : un convoqué qui s'était désisté récupère sa place
-- ---------------------------------------------------------------------------

-- Bruno, convoqué, se désiste : Alice monte à sa place.
select pg_temp.as_profile('f5610000-0000-0000-0000-000000000003');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match_first')::uuid, 'absent', null
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match_first')::uuid),
  'Alice convoked / Bruno not_applicable / Chloé convoked',
  'le désistement de Bruno fait monter Alice'
);

-- Bruno revient : il reprend sa place, Alice retourne en liste d'attente.
select pg_temp.as_profile('f5610000-0000-0000-0000-000000000003');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match_first')::uuid, 'available', null
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match_first')::uuid),
  'Alice not_convoked / Bruno convoked / Chloé convoked',
  'Bruno, revenu, récupère sa place et Alice retourne en attente'
);

select * from finish();
rollback;
