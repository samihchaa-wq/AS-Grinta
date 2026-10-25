begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- L'effectif d'un match est publié dès la création du match. Il ne passe
-- plus par un brouillon qui durait jusqu'à ce qu'un admin ouvre la page.
--
-- Ordre de la liste d'attente : Alice n°1, Bruno n°2. Les derniers de la
-- liste gardent leur place en priorité : Alice est la première à tomber en
-- attente.

select vault.create_secret('test-token', 'push_internal_token')
where not exists (
  select 1 from vault.secrets secret where secret.name = 'push_internal_token'
);

update private.app_feature_flags
set enabled = false
where key = 'notifications_paused';

insert into auth.users(id, email, raw_user_meta_data)
values
  ('f5710000-0000-0000-0000-000000000001', 'always-published-admin@example.invalid',
   '{"first_name":"Admin"}'::jsonb),
  ('f5710000-0000-0000-0000-000000000002', 'always-published-alice@example.invalid',
   '{"first_name":"Alice"}'::jsonb),
  ('f5710000-0000-0000-0000-000000000003', 'always-published-bruno@example.invalid',
   '{"first_name":"Bruno"}'::jsonb);

update public.profiles
set role = case
      when id = 'f5710000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'f5710000-0000-0000-0000-000000000001'
  and 'f5710000-0000-0000-0000-000000000003';

insert into public.seasons(id, name, status)
values ('f5720000-0000-0000-0000-000000000001', '2701-2702', 'open');

insert into public.opponents(id, name)
values ('f5730000-0000-0000-0000-000000000001', 'Publié FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  ('f5740000-0000-0000-0000-000000000001',
   'f5720000-0000-0000-0000-000000000001', 'Alice', 'Publie', false, true, 1,
   'f5710000-0000-0000-0000-000000000002'),
  ('f5740000-0000-0000-0000-000000000002',
   'f5720000-0000-0000-0000-000000000001', 'Bruno', 'Publie', false, true, 2,
   'f5710000-0000-0000-0000-000000000003');

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

create or replace function pg_temp.workflow_of(p_match uuid)
returns text
language sql
stable
as $function$
  select workflow.convocation_state::text
    || ' v' || workflow.convocation_version
    || case
         when workflow.convocation_published_at is null then ' sans date'
         else ' daté'
       end
  from public.match_sport_workflows workflow
  where workflow.match_id = p_match;
$function$;

-- ---------------------------------------------------------------------------
-- 1. Un nouveau match naît publié
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
    'domicile', 2.10, 3.20, 2.90, 1
  )::text,
  true
);

reset role;

select is(
  pg_temp.workflow_of(current_setting('test.match')::uuid),
  'published v1 daté',
  'un nouveau match a un effectif publié, en version 1, dès sa création'
);

-- ---------------------------------------------------------------------------
-- 2. Sans qu'aucun admin n'ouvre la page, les règles publiées s'appliquent
-- ---------------------------------------------------------------------------

-- Une seule place. Alice répond la première : elle est convoquée.
select pg_temp.mark();
select pg_temp.as_profile('f5710000-0000-0000-0000-000000000002');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'available', null
);

select is(
  public.get_my_match_availability(current_setting('test.match')::uuid)
    ->> 'convocation_status',
  'convoked',
  'Alice voit tout de suite qu''elle est convoquée'
);

reset role;

-- Bruno répond : n°2, il garde la place ; Alice, n°1, passe en attente et
-- en est prévenue sans qu'aucun admin ne soit intervenu.
select pg_temp.as_profile('f5710000-0000-0000-0000-000000000003');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'available', null
);
reset role;

select pg_temp.as_profile('f5710000-0000-0000-0000-000000000002');
set local role authenticated;

select is(
  public.get_my_match_availability(current_setting('test.match')::uuid)
    ->> 'convocation_status',
  'not_convoked',
  'Alice voit tout de suite qu''elle est en liste d''attente'
);

reset role;

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  'Tu passes en liste d''attente → Alice',
  'Alice est prévenue dès qu''elle perd sa place, sans action d''un admin'
);

-- Bruno se désiste : comme sur un effectif publié, Alice remonte et
-- reçoit « Tu es convoqué ».
select pg_temp.mark();
select pg_temp.as_profile('f5710000-0000-0000-0000-000000000003');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'absent', null
);
reset role;

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  'Tu es convoqué → Alice',
  'le désistement de Bruno fait remonter Alice, qui est prévenue'
);

-- ---------------------------------------------------------------------------
-- 3. Un report à un autre jour remet les réponses à zéro, l'effectif reste
--    publié
-- ---------------------------------------------------------------------------

update public.matches
set kickoff_at = kickoff_at + interval '1 day',
    match_date = match_date + 1
where id = current_setting('test.match')::uuid;

select is(
  (
    select workflow.convocation_state::text
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.match')::uuid
  ),
  'published',
  'après un report à un autre jour, l''effectif reste publié'
);

select is(
  (
    select count(*)::integer
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.match')::uuid
      and participant.season_player_id is not null
      and participant.availability_status <> 'no_response'
  ),
  0,
  'après un report à un autre jour, les réponses sont remises à zéro'
);

-- ---------------------------------------------------------------------------
-- 4. Match entre nous : modifier l'effectif n'efface plus la composition
-- ---------------------------------------------------------------------------

select pg_temp.as_profile('f5710000-0000-0000-0000-000000000001');
set local role authenticated;

select set_config(
  'test.internal',
  public.create_internal_match_v2(
    'f5720000-0000-0000-0000-000000000001',
    ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
    time '20:00', null, 'now', null
  )::text,
  true
);

select public.admin_override_match_availability(
  current_setting('test.internal')::uuid,
  'f5740000-0000-0000-0000-000000000001', 'available', null, 'Test'
);

reset role;

select is(
  pg_temp.workflow_of(current_setting('test.internal')::uuid),
  'published v1 daté',
  'un match entre nous naît lui aussi publié, en version 1'
);

-- L'admin prépare la composition interne avant de toucher à l'effectif.
insert into public.match_internal_compositions(match_id, updated_by)
values (
  current_setting('test.internal')::uuid,
  'f5710000-0000-0000-0000-000000000001'
);

insert into public.match_internal_composition_entries(
  match_id, participant_id, team_no, sort_order
)
select participant.match_id, participant.id, 1, 0
from public.match_sport_participants participant
where participant.match_id = current_setting('test.internal')::uuid
  and participant.season_player_id = 'f5740000-0000-0000-0000-000000000001';

select pg_temp.as_profile('f5710000-0000-0000-0000-000000000001');
set local role authenticated;
select public.admin_save_match_effectif(
  current_setting('test.internal')::uuid,
  30,
  jsonb_build_array(jsonb_build_object(
    'season_player_id', 'f5740000-0000-0000-0000-000000000001',
    'status', 'convoked',
    'changed', false
  )),
  'Premier enregistrement'
);
reset role;

select is(
  (
    select count(*)::integer
    from public.match_internal_composition_entries entry
    where entry.match_id = current_setting('test.internal')::uuid
  ),
  1,
  'le premier enregistrement de l''effectif garde la composition préparée'
);

select * from finish();
rollback;
