begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Quand un convoqué se désiste après la publication de l'effectif, sa place
-- revient au joueur en attente le plus BAS dans la liste, celui que le
-- recalcul automatique aurait convoqué. Le n°1 de la liste reste en attente.
--
-- Ordre de la liste : Alice n°1, Bruno n°2, Chloé n°3, Damien n°4. Deux
-- places : Chloé et Damien sont convoqués, Alice et Bruno en attente.

select vault.create_secret('test-token', 'push_internal_token')
where not exists (
  select 1 from vault.secrets secret where secret.name = 'push_internal_token'
);

update private.app_feature_flags
set enabled = false
where key = 'notifications_paused';

insert into auth.users(id, email, raw_user_meta_data)
values
  ('f5710000-0000-0000-0000-000000000001', 'withdrawal-order-admin@example.invalid',
   '{"first_name":"Admin"}'::jsonb),
  ('f5710000-0000-0000-0000-000000000002', 'withdrawal-order-alice@example.invalid',
   '{"first_name":"Alice"}'::jsonb),
  ('f5710000-0000-0000-0000-000000000003', 'withdrawal-order-bruno@example.invalid',
   '{"first_name":"Bruno"}'::jsonb),
  ('f5710000-0000-0000-0000-000000000004', 'withdrawal-order-chloe@example.invalid',
   '{"first_name":"Chloé"}'::jsonb),
  ('f5710000-0000-0000-0000-000000000005', 'withdrawal-order-damien@example.invalid',
   '{"first_name":"Damien"}'::jsonb);

update public.profiles
set role = case
      when id = 'f5710000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'f5710000-0000-0000-0000-000000000001'
  and 'f5710000-0000-0000-0000-000000000005';

insert into public.seasons(id, name, status)
values ('f5720000-0000-0000-0000-000000000001', '2603-2604', 'open');

insert into public.opponents(id, name)
values ('f5730000-0000-0000-0000-000000000001', 'Désistement FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  ('f5740000-0000-0000-0000-000000000001',
   'f5720000-0000-0000-0000-000000000001', 'Alice', 'Ordre', false, true, 1,
   'f5710000-0000-0000-0000-000000000002'),
  ('f5740000-0000-0000-0000-000000000002',
   'f5720000-0000-0000-0000-000000000001', 'Bruno', 'Ordre', false, true, 2,
   'f5710000-0000-0000-0000-000000000003'),
  ('f5740000-0000-0000-0000-000000000003',
   'f5720000-0000-0000-0000-000000000001', 'Chloé', 'Ordre', false, true, 3,
   'f5710000-0000-0000-0000-000000000004'),
  ('f5740000-0000-0000-0000-000000000004',
   'f5720000-0000-0000-0000-000000000001', 'Damien', 'Ordre', false, true, 4,
   'f5710000-0000-0000-0000-000000000005');

insert into public.sport_waitlist_entries(
  season_id, season_player_id, position, source, created_by, updated_by
)
select
  player.season_id, player.id, player.position, 'manual',
  'f5710000-0000-0000-0000-000000000001',
  'f5710000-0000-0000-0000-000000000001'
from public.season_players player
where player.season_id = 'f5720000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'f5710000-0000-0000-0000-000000000001'
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
-- Publication : les deux derniers de la liste sont convoqués
-- ---------------------------------------------------------------------------

select pg_temp.as_profile('f5710000-0000-0000-0000-000000000001');
set local role authenticated;

select set_config(
  'test.match',
  public.create_match_with_odds_and_sport_limit(
    'f5720000-0000-0000-0000-000000000001',
    'f5730000-0000-0000-0000-000000000001',
    ((now() + interval '4 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '4 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 2
  )::text,
  true
);

select public.admin_override_match_availability(
  current_setting('test.match')::uuid,
  'f5740000-0000-0000-0000-000000000001', 'available', null, 'Test'
);
select public.admin_override_match_availability(
  current_setting('test.match')::uuid,
  'f5740000-0000-0000-0000-000000000002', 'available', null, 'Test'
);
select public.admin_override_match_availability(
  current_setting('test.match')::uuid,
  'f5740000-0000-0000-0000-000000000003', 'available', null, 'Test'
);
select public.admin_override_match_availability(
  current_setting('test.match')::uuid,
  'f5740000-0000-0000-0000-000000000004', 'available', null, 'Test'
);

reset role;

select set_config(
  'test.decisions',
  pg_temp.untouched_decisions(current_setting('test.match')::uuid)::text,
  true
);
select pg_temp.as_profile('f5710000-0000-0000-0000-000000000001');
set local role authenticated;
select public.admin_save_match_effectif(
  current_setting('test.match')::uuid,
  2,
  current_setting('test.decisions')::jsonb,
  'Publication'
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match')::uuid),
  'Alice not_convoked / Bruno not_convoked / Chloé convoked / Damien convoked',
  'à la publication, Chloé et Damien sont convoqués, Alice et Bruno attendent'
);

-- ---------------------------------------------------------------------------
-- Le cas réel : un convoqué se désiste
-- ---------------------------------------------------------------------------

select pg_temp.mark();
select pg_temp.as_profile('f5710000-0000-0000-0000-000000000005');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'absent', null
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match')::uuid),
  'Alice not_convoked / Bruno convoked / Chloé convoked / Damien not_applicable',
  'Damien se désiste : Bruno, dernier en attente, monte ; Alice, n°1, reste en attente'
);

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  'Tu es convoqué → Bruno',
  'seul Bruno est prévenu de sa convocation'
);

select ok(
  (
    select participant.promoted_from_participant_id is null
       and not participant.convocation_manual_override
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.match')::uuid
      and participant.season_player_id = 'f5740000-0000-0000-0000-000000000002'
  ),
  'Bruno est convoqué par le calcul unique, sans lien arbitraire de remplacement'
);

-- Le désistement suit le même ordre que le recalcul de l'effectif : un
-- enregistrement sans changement ne déplace personne.
select set_config(
  'test.decisions_after',
  pg_temp.untouched_decisions(current_setting('test.match')::uuid)::text,
  true
);
select pg_temp.as_profile('f5710000-0000-0000-0000-000000000001');
set local role authenticated;
select public.admin_save_match_effectif(
  current_setting('test.match')::uuid,
  2,
  current_setting('test.decisions_after')::jsonb,
  'Contrôle'
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match')::uuid),
  'Alice not_convoked / Bruno convoked / Chloé convoked / Damien not_applicable',
  'un enregistrement de l''effectif confirme le choix fait au désistement'
);

-- Damien revient : il reprend sa place, Bruno retourne en attente.
select pg_temp.as_profile('f5710000-0000-0000-0000-000000000005');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'available', null
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match')::uuid),
  'Alice not_convoked / Bruno not_convoked / Chloé convoked / Damien convoked',
  'Damien, revenu, récupère sa place et Bruno retourne en attente'
);

-- ---------------------------------------------------------------------------
-- Retour d'un convoqué dont la place a été reprise à la main
-- ---------------------------------------------------------------------------

-- Damien se désiste de nouveau : Bruno, dernier en attente, monte.
select pg_temp.as_profile('f5710000-0000-0000-0000-000000000005');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'absent', null
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match')::uuid),
  'Alice not_convoked / Bruno convoked / Chloé convoked / Damien not_applicable',
  'second désistement de Damien : Bruno monte'
);

-- Comme Poulain pour le match du 9 novembre, l'admin renvoie à la main le
-- remplaçant en liste d'attente. Le recalcul donne la place libre à Alice,
-- sans la noter comme remplaçante de Damien.
select set_config(
  'test.decisions_manual',
  (
    select jsonb_agg(
      case
        when decision ->> 'season_player_id'
             = 'f5740000-0000-0000-0000-000000000002'
          then jsonb_build_object(
            'season_player_id', decision ->> 'season_player_id',
            'status', 'not_convoked',
            'changed', true
          )
        else decision
      end
    )
    from jsonb_array_elements(
      pg_temp.untouched_decisions(current_setting('test.match')::uuid)
    ) decision
  )::text,
  true
);
select pg_temp.as_profile('f5710000-0000-0000-0000-000000000001');
set local role authenticated;
select public.admin_save_match_effectif(
  current_setting('test.match')::uuid,
  2,
  current_setting('test.decisions_manual')::jsonb,
  'Correction manuelle'
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match')::uuid),
  'Alice convoked / Bruno not_convoked / Chloé convoked / Damien not_applicable',
  'après la correction manuelle, Alice occupe la place de Damien'
);

-- Damien revient. Personne n'est noté comme son remplaçant : sans
-- correction, il reprenait sa place et l'effectif passait à 3 pour 2.
select pg_temp.mark();
select pg_temp.as_profile('f5710000-0000-0000-0000-000000000005');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'available', null
);
reset role;

select is(
  pg_temp.effectif(current_setting('test.match')::uuid),
  'Alice not_convoked / Bruno not_convoked / Chloé convoked / Damien convoked',
  'Damien récupère sa place et Alice, la plus haute des convoqués dans la liste, repasse en attente'
);

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  'Tu passes en liste d''attente → Alice',
  'seule Alice, qui perd sa place, est prévenue'
);

select * from finish();
rollback;
