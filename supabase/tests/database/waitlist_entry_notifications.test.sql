begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Entrer en liste d'attente prévient toujours le joueur, entrer chez les
-- convoqués jamais : être convoqué est le résultat attendu.
--
-- * à la première publication de l'effectif, les joueurs déjà placés en
--   liste d'attente reçoivent « Tu passes en liste d'attente » ;
-- * après la publication, un joueur qui répond « Présent » et tombe
--   directement en liste d'attente la reçoit aussi ;
-- * un joueur convoqué directement ne reçoit rien.
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
  ('e7100000-0000-0000-0000-000000000001', 'waitlist-entry-admin@example.invalid',
   '{"first_name":"Admin"}'::jsonb),
  ('e7100000-0000-0000-0000-000000000002', 'waitlist-entry-alice@example.invalid',
   '{"first_name":"Alice"}'::jsonb),
  ('e7100000-0000-0000-0000-000000000003', 'waitlist-entry-bruno@example.invalid',
   '{"first_name":"Bruno"}'::jsonb),
  ('e7100000-0000-0000-0000-000000000004', 'waitlist-entry-chloe@example.invalid',
   '{"first_name":"Chloé"}'::jsonb);

update public.profiles
set role = case
      when id = 'e7100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'e7100000-0000-0000-0000-000000000001'
  and 'e7100000-0000-0000-0000-000000000004';

insert into public.seasons(id, name, status)
values ('e7200000-0000-0000-0000-000000000001', '2107-2108', 'open');

insert into public.opponents(id, name)
values ('e7300000-0000-0000-0000-000000000001', 'Liste FC');

-- Ordre de la liste d'attente : Alice n°1, Bruno n°2, Chloé n°3. Les
-- derniers de la liste gardent leur place en priorité : Alice est la
-- première à tomber en attente.
insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  ('e7400000-0000-0000-0000-000000000001',
   'e7200000-0000-0000-0000-000000000001', 'Alice', 'Entree', false, true, 1,
   'e7100000-0000-0000-0000-000000000002'),
  ('e7400000-0000-0000-0000-000000000002',
   'e7200000-0000-0000-0000-000000000001', 'Bruno', 'Entree', false, true, 2,
   'e7100000-0000-0000-0000-000000000003'),
  ('e7400000-0000-0000-0000-000000000003',
   'e7200000-0000-0000-0000-000000000001', 'Chloé', 'Entree', false, true, 3,
   'e7100000-0000-0000-0000-000000000004');

insert into public.sport_waitlist_entries(
  season_id, season_player_id, position, source, created_by, updated_by
)
select
  player.season_id, player.id, player.position, 'manual',
  'e7100000-0000-0000-0000-000000000001',
  'e7100000-0000-0000-0000-000000000001'
from public.season_players player
where player.season_id = 'e7200000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'e7100000-0000-0000-0000-000000000001'
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

-- Décisions telles que l'écran les envoie quand l'admin ne déplace personne :
-- chaque joueur disponible garde la place calculée par le serveur.
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

create or replace function pg_temp.status_of(p_match uuid, p_player uuid)
returns text
language sql
stable
as $function$
  select participant.convocation_status::text
  from public.match_sport_participants participant
  where participant.match_id = p_match
    and participant.season_player_id = p_player;
$function$;

-- ---------------------------------------------------------------------------
-- 1. Première publication : la liste d'attente initiale est prévenue
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.match_publish',
  public.create_match_with_odds_and_sport_limit(
    'e7200000-0000-0000-0000-000000000001',
    'e7300000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 1
  )::text,
  true
);

-- Alice et Bruno répondent avant la publication : une seule place.
select public.admin_override_match_availability(
  current_setting('test.match_publish')::uuid,
  'e7400000-0000-0000-0000-000000000001', 'available', null, 'Test'
);
select public.admin_override_match_availability(
  current_setting('test.match_publish')::uuid,
  'e7400000-0000-0000-0000-000000000002', 'available', null, 'Test'
);

reset role;

select is(
  (
    select workflow.convocation_state::text
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.match_publish')::uuid
  ),
  'draft',
  'avant l''enregistrement de l''effectif, rien n''est publié'
);

select pg_temp.mark();
select set_config(
  'test.decisions_publish',
  pg_temp.untouched_decisions(current_setting('test.match_publish')::uuid)::text,
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_save_match_effectif(
  current_setting('test.match_publish')::uuid,
  1,
  current_setting('test.decisions_publish')::jsonb,
  'Première publication'
);

reset role;

select is(
  pg_temp.status_of(
    current_setting('test.match_publish')::uuid,
    'e7400000-0000-0000-0000-000000000002'
  ) || ' / ' || pg_temp.status_of(
    current_setting('test.match_publish')::uuid,
    'e7400000-0000-0000-0000-000000000001'
  ),
  'convoked / not_convoked',
  'Bruno garde la place, Alice tombe en liste d''attente'
);

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  'Tu passes en liste d''attente → Alice',
  'à la publication, seule Alice, en liste d''attente, est prévenue'
);

-- La notification porte de quoi la retrouver dans le journal de livraison.
select is(
  (
    select (convert_from(queue.body, 'UTF8')::jsonb ->> 'log_kind')
      || ' / ' || (convert_from(queue.body, 'UTF8')::jsonb ->> 'match_id')
    from net.http_request_queue queue
    where queue.id > current_setting('test.marker')::bigint
      and convert_from(queue.body, 'UTF8')::jsonb ->> 'title'
        = 'Tu passes en liste d''attente'
    order by queue.id desc
    limit 1
  ),
  'convocation_demoted / ' || current_setting('test.match_publish'),
  'l''envoi indique son type et son match pour le journal de livraison'
);

-- Republier sans rien changer ne renvoie rien.
select pg_temp.mark();
select set_config(
  'test.decisions_republish',
  pg_temp.untouched_decisions(current_setting('test.match_publish')::uuid)::text,
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_save_match_effectif(
  current_setting('test.match_publish')::uuid,
  1,
  current_setting('test.decisions_republish')::jsonb,
  'Nouvel enregistrement'
);

reset role;

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  '',
  'un nouvel enregistrement sans changement de place ne prévient personne'
);

-- ---------------------------------------------------------------------------
-- 2. Après la publication : réponse tardive tombée en liste d'attente
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.match_late',
  public.create_match_with_odds_and_sport_limit(
    'e7200000-0000-0000-0000-000000000001',
    'e7300000-0000-0000-0000-000000000001',
    ((now() + interval '4 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '4 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 2
  )::text,
  true
);

-- Bruno et Chloé répondent, l'effectif est publié : deux places, deux
-- convoqués.
select public.admin_override_match_availability(
  current_setting('test.match_late')::uuid,
  'e7400000-0000-0000-0000-000000000002', 'available', null, 'Test'
);
select public.admin_override_match_availability(
  current_setting('test.match_late')::uuid,
  'e7400000-0000-0000-0000-000000000003', 'available', null, 'Test'
);

reset role;

select pg_temp.mark();
select set_config(
  'test.decisions_late',
  pg_temp.untouched_decisions(current_setting('test.match_late')::uuid)::text,
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_save_match_effectif(
  current_setting('test.match_late')::uuid,
  2,
  current_setting('test.decisions_late')::jsonb,
  'Publication'
);

reset role;

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  '',
  'des convoqués directs ne reçoivent rien à la publication'
);

-- Alice répond après la publication : n°1 de la liste, elle tombe
-- directement en liste d'attente.
select pg_temp.mark();
select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_override_match_availability(
  current_setting('test.match_late')::uuid,
  'e7400000-0000-0000-0000-000000000001', 'available', null, 'Réponse tardive'
);

reset role;

select is(
  pg_temp.status_of(
    current_setting('test.match_late')::uuid,
    'e7400000-0000-0000-0000-000000000001'
  ),
  'not_convoked',
  'la réponse tardive d''Alice la place en liste d''attente'
);

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  'Tu passes en liste d''attente → Alice',
  'Alice, entrée directement en liste d''attente, est prévenue, et elle seule'
);

-- Une place se libère : Alice passe de la liste d'attente aux convoqués.
select pg_temp.mark();
select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_override_match_availability(
  current_setting('test.match_late')::uuid,
  'e7400000-0000-0000-0000-000000000003', 'absent', null, 'Blessée'
);

reset role;

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  'Tu es convoqué → Alice',
  'quand une place se libère, Alice reçoit « Tu es convoqué »'
);

-- ---------------------------------------------------------------------------
-- 3. Le coupe-circuit reste respecté
-- ---------------------------------------------------------------------------

update private.app_feature_flags
set enabled = true
where key = 'notifications_paused';

select pg_temp.mark();

update public.match_sport_participants participant
set convocation_status = 'not_applicable'
where participant.match_id = current_setting('test.match_late')::uuid
  and participant.season_player_id = 'e7400000-0000-0000-0000-000000000002';
update public.match_sport_participants participant
set convocation_status = 'not_convoked'
where participant.match_id = current_setting('test.match_late')::uuid
  and participant.season_player_id = 'e7400000-0000-0000-0000-000000000002';

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  '',
  'rien ne part quand les notifications sont en pause'
);

select * from finish();
rollback;
