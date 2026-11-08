begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Une fois les convocations publiées, un joueur qui passe de la liste
-- d'attente aux convoqués reçoit « Tu es convoqué », et un joueur qui passe
-- des convoqués à la liste d'attente reçoit « Tu passes en liste
-- d'attente ». Les deux partent même si le joueur a coupé l'ancien réglage
-- « Passage en convoqué » : ce sont des notifications essentielles.
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
  ('d1000000-0000-0000-0000-000000000001', 'notif-admin@example.invalid',
   '{"first_name":"Admin"}'::jsonb),
  ('d1000000-0000-0000-0000-000000000002', 'notif-alice@example.invalid',
   '{"first_name":"Alice"}'::jsonb),
  ('d1000000-0000-0000-0000-000000000003', 'notif-bruno@example.invalid',
   '{"first_name":"Bruno"}'::jsonb),
  ('d1000000-0000-0000-0000-000000000004', 'notif-chloe@example.invalid',
   '{"first_name":"Chloé"}'::jsonb);

update public.profiles
set role = case
      when id = 'd1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    -- L'ancien réglage coupé ne bloque plus rien.
    notify_convocation = false,
    updated_at = now()
where id between
  'd1000000-0000-0000-0000-000000000001'
  and 'd1000000-0000-0000-0000-000000000004';

insert into public.seasons(id, name, status)
values ('d2000000-0000-0000-0000-000000000001', '2105-2106', 'open');

insert into public.opponents(id, name)
values ('d3000000-0000-0000-0000-000000000001', 'Convocation FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  ('d4000000-0000-0000-0000-000000000001',
   'd2000000-0000-0000-0000-000000000001', 'Alice', 'Rotation', false, true, 1,
   'd1000000-0000-0000-0000-000000000002'),
  ('d4000000-0000-0000-0000-000000000002',
   'd2000000-0000-0000-0000-000000000001', 'Bruno', 'Rotation', false, true, 2,
   'd1000000-0000-0000-0000-000000000003'),
  ('d4000000-0000-0000-0000-000000000003',
   'd2000000-0000-0000-0000-000000000001', 'Chloé', 'Rotation', false, true, 3,
   'd1000000-0000-0000-0000-000000000004');

-- Alice est n°1 de la liste d'attente : la première à passer en attente.
insert into public.sport_waitlist_entries(
  season_id, season_player_id, position, source, created_by, updated_by
)
select
  player.season_id, player.id, player.position, 'manual',
  'd1000000-0000-0000-0000-000000000001',
  'd1000000-0000-0000-0000-000000000001'
from public.season_players player
where player.season_id = 'd2000000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'd1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

create or replace function pg_temp.status_of(p_player uuid)
returns text
language sql
stable
as $function$
  select participant.convocation_status::text
    || case when participant.convocation_manual_override
         then '/manuel' else '/auto' end
  from public.match_sport_participants participant
  where participant.match_id = current_setting('test.notif_match')::uuid
    and participant.season_player_id = p_player;
$function$;

create or replace function pg_temp.decisions(p_changed jsonb)
returns jsonb
language sql
stable
as $function$
  -- Recopie ce que le serveur a calculé, comme le fait l'écran ; p_changed
  -- force un statut et le marque comme décision de l'admin.
  select jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'season_player_id', participant.season_player_id,
      'status', coalesce(
        p_changed ->> participant.season_player_id::text,
        nullif(participant.convocation_status::text, 'not_applicable'),
        'not_convoked'
      ),
      'changed', case
        when p_changed = '{}'::jsonb then null
        else p_changed ? participant.season_player_id::text
      end
    ))
  )
  from public.match_sport_participants participant
  where participant.match_id = current_setting('test.notif_match')::uuid
    and participant.availability_status = 'available';
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.notif_match',
  public.create_match_with_odds_and_sport_limit(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 2
  )::text,
  true
);

select public.admin_override_match_availability(
  current_setting('test.notif_match')::uuid,
  'd4000000-0000-0000-0000-000000000001', 'available', null, 'Test'
);
select public.admin_override_match_availability(
  current_setting('test.notif_match')::uuid,
  'd4000000-0000-0000-0000-000000000002', 'available', null, 'Test'
);

reset role;
select set_config(
  'test.decisions_first', pg_temp.decisions('{"_": null}'::jsonb)::text, true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

-- L'écran enregistre l'effectif tel que le serveur l'a calculé, sans aucun
-- déplacement de l'admin.
select public.admin_save_match_effectif(
  current_setting('test.notif_match')::uuid,
  2,
  current_setting('test.decisions_first')::jsonb,
  'Enregistrement sans déplacement'
);

reset role;

-- Envois mis en file pour un joueur, du plus ancien au plus récent :
-- « titre → profil ».
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

select set_config(
  'test.marker',
  (select coalesce(max(id), 0) from net.http_request_queue)::text,
  true
);

select is(
  (
    select workflow.convocation_state::text
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.notif_match')::uuid
  ),
  'published',
  'l''effectif enregistré publie les convocations'
);

-- Chloé répond tard : Alice, n°1 de la liste, passe en attente.
select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_override_match_availability(
  current_setting('test.notif_match')::uuid,
  'd4000000-0000-0000-0000-000000000003', 'available', null, 'Réponse tardive'
);

reset role;

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  'Tu passes en liste d''attente → Alice',
  'le joueur qui passe en liste d''attente est prévenu, réglage coupé ou non'
);

select set_config(
  'test.marker',
  (select coalesce(max(id), 0) from net.http_request_queue)::text,
  true
);

-- L'admin reconvoque Alice : Alice est convoquée, Bruno passe en attente.
select set_config(
  'test.decisions_admin',
  pg_temp.decisions(
    '{"d4000000-0000-0000-0000-000000000001": "convoked"}'::jsonb
  )::text,
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_save_match_effectif(
  current_setting('test.notif_match')::uuid,
  2,
  current_setting('test.decisions_admin')::jsonb,
  'Alice reconvoquée'
);

reset role;

select is(
  (
    select string_agg(part, ' | ' order by part)
    from unnest(string_to_array(
      pg_temp.pushes_since(current_setting('test.marker')::bigint), ' | '
    )) part
  ),
  'Tu es convoqué → Alice | Tu passes en liste d''attente → Bruno',
  'chacun reçoit la notification de son changement, et elle seule'
);

select set_config(
  'test.marker',
  (select coalesce(max(id), 0) from net.http_request_queue)::text,
  true
);

-- Un joueur qui se déclare absent quitte l'effectif sans passer par la
-- liste d'attente : rien ne part.
select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_override_match_availability(
  current_setting('test.notif_match')::uuid,
  'd4000000-0000-0000-0000-000000000001', 'absent', null, 'Blessé'
);

reset role;

select ok(
  pg_temp.pushes_since(current_setting('test.marker')::bigint)
    not like '%Alice%',
  'un joueur devenu absent ne reçoit ni convocation ni liste d''attente'
);

-- Le coupe-circuit des notifications reste respecté.
update private.app_feature_flags
set enabled = true
where key = 'notifications_paused';

select set_config(
  'test.marker',
  (select coalesce(max(id), 0) from net.http_request_queue)::text,
  true
);

update public.match_sport_participants participant
set convocation_status = 'not_convoked'
where participant.match_id = current_setting('test.notif_match')::uuid
  and participant.season_player_id = 'd4000000-0000-0000-0000-000000000003'
  and participant.convocation_status = 'convoked';

select is(
  pg_temp.pushes_since(current_setting('test.marker')::bigint),
  '',
  'rien ne part quand les notifications sont en pause'
);

select * from finish();
rollback;
