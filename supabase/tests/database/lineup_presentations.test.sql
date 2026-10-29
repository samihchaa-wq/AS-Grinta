begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Présentation cinématique des compositions : la mise en ligne d'une
-- composition demande sa vidéo, une seule par contenu, sans jamais bloquer
-- la publication ; l'application n'en voit que ce qu'un membre a le droit
-- de voir, et seulement quand le réglage le permet.

insert into auth.users(id, email, raw_user_meta_data)
values
  ('e7100000-0000-0000-0000-000000000001', 'video-admin@example.invalid', '{"first_name":"Admin"}'::jsonb),
  ('e7100000-0000-0000-0000-000000000002', 'video-gardien@example.invalid', '{"first_name":"gardien"}'::jsonb),
  ('e7100000-0000-0000-0000-000000000003', 'video-avant@example.invalid', '{"first_name":"Avant"}'::jsonb),
  ('e7100000-0000-0000-0000-000000000004', 'video-banc@example.invalid', '{"first_name":"Banc"}'::jsonb);

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
values ('e7200000-0000-0000-0000-000000000001', '2601-2602', 'open');

insert into public.opponents(id, name)
values ('e7300000-0000-0000-0000-000000000001', 'Vidéo Test FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper, is_active, position, profile_id
)
values
  ('e7400000-0000-0000-0000-000000000001', 'e7200000-0000-0000-0000-000000000001',
   'Gardien', 'Vidéo', true, true, 1, 'e7100000-0000-0000-0000-000000000002'),
  ('e7400000-0000-0000-0000-000000000002', 'e7200000-0000-0000-0000-000000000001',
   'Avant', 'Vidéo', false, true, 2, 'e7100000-0000-0000-0000-000000000003'),
  ('e7400000-0000-0000-0000-000000000003', 'e7200000-0000-0000-0000-000000000001',
   'Banc', 'Vidéo', false, true, 3, 'e7100000-0000-0000-0000-000000000004');

update private.app_feature_flags
set enabled = true, updated_at = now(), updated_by = 'e7100000-0000-0000-0000-000000000001'
where key = 'sports_management';

select is(
  (select enabled from private.app_feature_flags where key = 'lineup_presentation'),
  false,
  'la présentation est coupée par défaut'
);

select ok(
  not has_table_privilege('authenticated', 'public.match_lineup_presentations', 'SELECT')
    and not has_table_privilege('anon', 'public.match_lineup_presentations', 'SELECT')
    and not has_table_privilege('authenticated', 'public.match_lineup_presentations', 'INSERT'),
  'la file des vidéos n''est pas lisible directement par l''application'
);

select ok(
  not has_function_privilege('authenticated', 'public.lineup_render_claim(integer)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.lineup_render_complete(uuid, integer, bigint, bigint)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.lineup_render_fail(uuid, text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.lineup_render_purgeable(integer)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.lineup_render_mark_purged(uuid[])', 'EXECUTE')
    and not has_function_privilege('anon', 'public.get_lineup_presentation(uuid)', 'EXECUTE'),
  'seul le serveur fabrique et range les vidéos'
);

select ok(
  (select not public from storage.buckets where id = 'lineup-presentations'),
  'les vidéos sont rangées dans un espace privé'
);

-- Un jeton d'appel GitHub est enregistré : chaque nouvelle vidéo à fabriquer
-- prévient le workflow.
select vault.create_secret('jeton-de-test', 'github_lineup_render_token')
where not exists (
  select 1 from vault.secrets secret where secret.name = 'github_lineup_render_token'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.video_match',
  public.create_match_with_odds_and_sport_limit(
    'e7200000-0000-0000-0000-000000000001',
    'e7300000-0000-0000-0000-000000000001',
    ((now() + interval '4 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '4 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 5
  )::text,
  true
);

reset role;

update public.match_sport_participants
set availability_status = 'available',
    availability_updated_at = now(),
    availability_updated_by = 'e7100000-0000-0000-0000-000000000001',
    updated_at = now()
where match_id = current_setting('test.video_match')::uuid;

create or replace function pg_temp.video_participant(p_season_player uuid)
returns uuid
language sql
stable
as $function$
  select participant.id
  from public.match_sport_participants participant
  where participant.match_id = current_setting('test.video_match')::uuid
    and participant.season_player_id = p_season_player;
$function$;

-- Gardien et avant-centre titulaires, troisième joueur sur le banc.
create or replace function pg_temp.video_entries(p_striker_y numeric, p_bench_order integer)
returns jsonb
language sql
stable
as $function$
  select jsonb_build_array(
    jsonb_build_object(
      'participant_id', pg_temp.video_participant('e7400000-0000-0000-0000-000000000001'),
      'zone', 'field', 'x', 0.5, 'y', 0.89, 'sort_order', 1
    ),
    jsonb_build_object(
      'participant_id', pg_temp.video_participant('e7400000-0000-0000-0000-000000000002'),
      'zone', 'field', 'x', 0.5, 'y', p_striker_y, 'sort_order', 2
    ),
    jsonb_build_object(
      'participant_id', pg_temp.video_participant('e7400000-0000-0000-0000-000000000003'),
      'zone', 'bench', 'x', null, 'y', null, 'sort_order', p_bench_order
    )
  );
$function$;

-- La file est lue hors du rôle des joueurs, comme le ferait un exploitant.
create or replace function pg_temp.video_rows()
returns table(status text, fingerprint text, players integer, attempts integer)
language sql
stable
security definer
set search_path = ''
as $function$
  select presentation.status,
    presentation.fingerprint,
    jsonb_array_length(presentation.payload -> 'players'),
    presentation.attempts
  from public.match_lineup_presentations presentation
  where presentation.match_id = pg_catalog.current_setting('test.video_match')::uuid
  order by presentation.requested_at, presentation.id;
$function$;

create or replace function pg_temp.dispatch_count()
returns bigint
language sql
stable
security definer
set search_path = ''
as $function$
  select count(*)
  from net.http_request_queue queue
  where queue.url like 'https://api.github.com/repos/samihchaa-wq/AS-Grinta/actions/workflows/lineup_presentation_render.yml/dispatches';
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_publish_match_effectif(
    current_setting('test.video_match')::uuid,
    5,
    jsonb_build_array(
      jsonb_build_object('season_player_id', 'e7400000-0000-0000-0000-000000000001', 'status', 'convoked'),
      jsonb_build_object('season_player_id', 'e7400000-0000-0000-0000-000000000002', 'status', 'convoked'),
      jsonb_build_object('season_player_id', 'e7400000-0000-0000-0000-000000000003', 'status', 'convoked')
    ),
    'Effectif du test vidéo'
  ) #>> '{convocation_state}',
  'published',
  'l''effectif est écrit avant la composition'
);

select is(
  (select count(*) from pg_temp.video_rows()),
  0::bigint,
  'aucune vidéo n''est préparée avant la publication de la composition'
);

select is(
  public.admin_save_match_composition(
    current_setting('test.video_match')::uuid,
    '4-2-1-3',
    pg_temp.video_entries(0.14, 3),
    false,
    'Première feuille'
  ) #>> '{version}',
  '1',
  'la composition est publiée'
);

select is(
  (select count(*) from pg_temp.video_rows() where status = 'pending'),
  1::bigint,
  'la mise en ligne demande la vidéo'
);

select is(
  (select players from pg_temp.video_rows()),
  2,
  'la vidéo ne montre que les titulaires'
);

select matches(
  (select fingerprint from pg_temp.video_rows()),
  '^[0-9a-f]{32}$',
  'la demande porte l''empreinte de son contenu'
);

select is(
  pg_temp.dispatch_count(),
  1::bigint,
  'le workflow GitHub est prévenu une fois'
);

select is(
  public.admin_save_match_composition(
    current_setting('test.video_match')::uuid,
    '4-2-1-3',
    pg_temp.video_entries(0.14, 7),
    false,
    'Banc retouché'
  ) #>> '{version}',
  '2',
  'une retouche du banc est publiée'
);

select is(
  (select count(*) from pg_temp.video_rows()),
  1::bigint,
  'le banc n''apparaît pas dans la vidéo : la même vidéo est réutilisée'
);

select is(
  pg_temp.dispatch_count(),
  1::bigint,
  'rien de nouveau à fabriquer, le workflow n''est pas rappelé'
);

select is(
  public.admin_save_match_composition(
    current_setting('test.video_match')::uuid,
    '4-2-1-3',
    pg_temp.video_entries(0.23, 7),
    false,
    'Titulaire déplacé'
  ) #>> '{version}',
  '3',
  'un titulaire déplacé est publié'
);

select is(
  (select string_agg(status, ',' order by status) from pg_temp.video_rows()),
  'pending,superseded',
  'la nouvelle composition remplace la demande précédente'
);

select is(
  pg_temp.dispatch_count(),
  2::bigint,
  'la nouvelle vidéo prévient le workflow'
);

-- Tant que le réglage est coupé, seuls les administrateurs y ont accès.
select is(
  public.get_lineup_presentation(current_setting('test.video_match')::uuid) ->> 'state',
  'pending',
  'l''administrateur voit la vidéo en préparation'
);

select is(
  public.get_lineup_presentation(current_setting('test.video_match')::uuid) ->> 'preview',
  'true',
  'et sait qu''elle n''est pas encore ouverte aux joueurs'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.get_lineup_presentation(current_setting('test.video_match')::uuid) ->> 'state',
  'disabled',
  'un joueur ne voit rien tant que le réglage est coupé'
);

reset role;
update private.app_feature_flags
set enabled = true, updated_at = now()
where key = 'lineup_presentation';

select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.get_lineup_presentation(current_setting('test.video_match')::uuid) ->> 'state',
  'pending',
  'réglage ouvert : le joueur voit la vidéo en préparation'
);

select is(
  public.get_lineup_presentation(current_setting('test.video_match')::uuid) ->> 'video_1080',
  null,
  'aucun fichier n''est annoncé avant la fin du rendu'
);

select is(
  (select count(*) from pg_temp.video_rows()),
  2::bigint,
  'consulter la composition ne fabrique pas de nouvelle vidéo'
);

reset role;

-- Le fabricant de vidéos réserve, puis range la vidéo.
set local role service_role;

select is(public.lineup_render_pending_count(), 1, 'une vidéo attend son rendu');

select set_config(
  'test.video_jobs',
  public.lineup_render_claim(5)::text,
  true
);

select is(
  jsonb_array_length(current_setting('test.video_jobs')::jsonb),
  1,
  'le fabricant réserve la vidéo en attente'
);

select is(
  current_setting('test.video_jobs')::jsonb #>> '{0,payload,formation_code}',
  '4-2-1-3',
  'la réservation donne le dispositif'
);

select is(
  current_setting('test.video_jobs')::jsonb #>> '{0,payload,match,opponent_name}',
  'Vidéo Test FC',
  'et l''adversaire'
);

-- Le prénom est transmis tel qu'il est saisi : la majuscule est ajoutée à
-- l'affichage, par la vidéo comme par l'écran Compo.
select ok(
  (current_setting('test.video_jobs')::jsonb #> '{0,payload,players}') @> '[{"display_name":"gardien","is_goalkeeper":true}]'::jsonb,
  'et les titulaires tels que l''écran Compo les reçoit'
);

select is(public.lineup_render_pending_count(), 0, 'une vidéo réservée n''est plus en attente');

select is(
  jsonb_array_length(public.lineup_render_claim(5)),
  0,
  'une vidéo n''est jamais réservée deux fois'
);

select ok(
  public.lineup_render_fail(
    (current_setting('test.video_jobs')::jsonb #>> '{0,id}')::uuid,
    'Échec simulé'
  ),
  'un échec est noté'
);

reset role;
select is(
  (select status from pg_temp.video_rows() where status <> 'superseded'),
  'pending',
  'la vidéo repart en file après un premier échec'
);
set local role service_role;

select set_config('test.video_jobs', public.lineup_render_claim(1)::text, true);

select is(
  public.lineup_render_complete(
    (current_setting('test.video_jobs')::jsonb #>> '{0,id}')::uuid,
    18000, 4800000, 2000000
  ) ->> 'video_1080',
  current_setting('test.video_match') || '/'
    || (current_setting('test.video_jobs')::jsonb #>> '{0,fingerprint}') || '/1080.mp4',
  'la vidéo est rangée à l''emplacement de sa demande'
);

select is(
  public.lineup_render_complete(
    (current_setting('test.video_jobs')::jsonb #>> '{0,id}')::uuid,
    18000, 4800000, 2000000
  ),
  null,
  'une vidéo déjà rangée ne peut pas être réécrite'
);

reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.video_ready',
  public.get_lineup_presentation(current_setting('test.video_match')::uuid)::text,
  true
);

select is(
  current_setting('test.video_ready')::jsonb ->> 'state',
  'ready',
  'le joueur apprend que la vidéo est prête'
);

select is(
  current_setting('test.video_ready')::jsonb ->> 'duration_ms',
  '18000',
  'avec sa durée'
);

select ok(
  private.can_read_lineup_presentation_object(current_setting('test.video_ready')::jsonb ->> 'video_720'),
  'le joueur peut lire le fichier de la vidéo prête'
);

select ok(
  not private.can_read_lineup_presentation_object(current_setting('test.video_match') || '/autre/1080.mp4'),
  'mais aucun autre fichier'
);

reset role;
update private.app_feature_flags
set enabled = false, updated_at = now()
where key = 'lineup_presentation';

select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  not private.can_read_lineup_presentation_object(current_setting('test.video_ready')::jsonb ->> 'video_720'),
  'réglage recoupé : le fichier redevient illisible pour les joueurs'
);

reset role;

-- Une vidéo plus récente rend l'ancienne effaçable : le stockage ne garde
-- que la vidéo utile de chaque match.
update public.match_lineup_presentations presentation
set status = 'ready',
    video_path_1080 = presentation.match_id || '/ancienne/1080.mp4',
    video_path_720 = presentation.match_id || '/ancienne/720.mp4',
    duration_ms = 18000,
    rendered_at = now() - interval '1 hour'
where presentation.match_id = current_setting('test.video_match')::uuid
  and presentation.status = 'superseded';

set local role service_role;

select is(
  jsonb_array_length(public.lineup_render_purgeable(20)),
  1,
  'l''ancienne vidéo du match est effaçable, pas la vidéo actuelle'
);

select is(
  public.lineup_render_mark_purged(
    array[(public.lineup_render_purgeable(20) #>> '{0,id}')::uuid]
  ),
  1,
  'l''effacement est noté'
);

select is(
  jsonb_array_length(public.lineup_render_purgeable(20)),
  0,
  'plus rien à effacer'
);

reset role;

-- La publication passe même si la préparation de la vidéo échoue.
create or replace function private.lineup_presentation_source(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  raise exception 'panne simulée de la préparation vidéo';
end;
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"e7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_save_match_composition(
    current_setting('test.video_match')::uuid,
    '4-2-1-3',
    pg_temp.video_entries(0.30, 7),
    false,
    'Publication malgré la panne'
  ) #>> '{version}',
  '4',
  'une panne de la préparation vidéo ne bloque jamais la publication'
);

select is(
  public.get_lineup_presentation(current_setting('test.video_match')::uuid) ->> 'state',
  'unavailable',
  'l''application apprend simplement qu''il n''y a pas de vidéo'
);

reset role;
select * from finish();
rollback;
