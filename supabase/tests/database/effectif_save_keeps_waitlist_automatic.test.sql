begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Enregistrer l'effectif ne fige que les joueurs que l'admin a déplacés. Les
-- autres suivent toujours la liste d'attente : un joueur qui répond plus tard
-- fait passer en attente le joueur le plus haut de la liste, même s'il était
-- déjà convoqué.

insert into auth.users(id, email, raw_user_meta_data)
values
  ('c1000000-0000-0000-0000-000000000001', 'auto-admin@example.invalid',
   '{"first_name":"Admin"}'::jsonb),
  ('c1000000-0000-0000-0000-000000000002', 'auto-alice@example.invalid',
   '{"first_name":"Alice"}'::jsonb),
  ('c1000000-0000-0000-0000-000000000003', 'auto-bruno@example.invalid',
   '{"first_name":"Bruno"}'::jsonb),
  ('c1000000-0000-0000-0000-000000000004', 'auto-chloe@example.invalid',
   '{"first_name":"Chloé"}'::jsonb);

update public.profiles
set role = case
      when id = 'c1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'c1000000-0000-0000-0000-000000000001'
  and 'c1000000-0000-0000-0000-000000000004';

insert into public.seasons(id, name, status)
values ('c2000000-0000-0000-0000-000000000001', '2103-2104', 'open');

insert into public.opponents(id, name)
values ('c3000000-0000-0000-0000-000000000001', 'Rotation FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  ('c4000000-0000-0000-0000-000000000001',
   'c2000000-0000-0000-0000-000000000001', 'Alice', 'Rotation', false, true, 1,
   'c1000000-0000-0000-0000-000000000002'),
  ('c4000000-0000-0000-0000-000000000002',
   'c2000000-0000-0000-0000-000000000001', 'Bruno', 'Rotation', false, true, 2,
   'c1000000-0000-0000-0000-000000000003'),
  ('c4000000-0000-0000-0000-000000000003',
   'c2000000-0000-0000-0000-000000000001', 'Chloé', 'Rotation', false, true, 3,
   'c1000000-0000-0000-0000-000000000004');

-- Alice est n°1 de la liste d'attente : la première à passer en attente.
insert into public.sport_waitlist_entries(
  season_id, season_player_id, position, source, created_by, updated_by
)
select
  player.season_id, player.id, player.position, 'manual',
  'c1000000-0000-0000-0000-000000000001',
  'c1000000-0000-0000-0000-000000000001'
from public.season_players player
where player.season_id = 'c2000000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'c1000000-0000-0000-0000-000000000001'
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
  where participant.match_id = current_setting('test.auto_match')::uuid
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
  where participant.match_id = current_setting('test.auto_match')::uuid
    and participant.availability_status = 'available';
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.auto_match',
  public.create_match_with_odds_and_sport_limit(
    'c2000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 2
  )::text,
  true
);

select public.admin_override_match_availability(
  current_setting('test.auto_match')::uuid,
  'c4000000-0000-0000-0000-000000000001', 'available', null, 'Test'
);
select public.admin_override_match_availability(
  current_setting('test.auto_match')::uuid,
  'c4000000-0000-0000-0000-000000000002', 'available', null, 'Test'
);

reset role;
select set_config(
  'test.decisions_first', pg_temp.decisions('{"_": null}'::jsonb)::text, true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

-- L'écran enregistre l'effectif tel que le serveur l'a calculé, sans aucun
-- déplacement de l'admin.
select public.admin_save_match_effectif(
  current_setting('test.auto_match')::uuid,
  2,
  current_setting('test.decisions_first')::jsonb,
  'Enregistrement sans déplacement'
);

reset role;

select is(
  pg_temp.status_of('c4000000-0000-0000-0000-000000000001')
    || ' ' || pg_temp.status_of('c4000000-0000-0000-0000-000000000002'),
  'convoked/auto convoked/auto',
  'un enregistrement sans déplacement ne fige personne'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_override_match_availability(
  current_setting('test.auto_match')::uuid,
  'c4000000-0000-0000-0000-000000000003', 'available', null, 'Réponse tardive'
);

reset role;

select is(
  pg_temp.status_of('c4000000-0000-0000-0000-000000000001')
    || ' ' || pg_temp.status_of('c4000000-0000-0000-0000-000000000002')
    || ' ' || pg_temp.status_of('c4000000-0000-0000-0000-000000000003'),
  'not_convoked/auto convoked/auto convoked/auto',
  'une réponse tardive fait passer en attente le n°1 de la liste, même déjà convoqué'
);

-- Un vrai déplacement de l'admin est figé, et la liste d'attente se
-- réapplique aux places restantes.
select set_config(
  'test.decisions_admin',
  pg_temp.decisions(
    '{"c4000000-0000-0000-0000-000000000001": "convoked"}'::jsonb
  )::text,
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_save_match_effectif(
  current_setting('test.auto_match')::uuid,
  2,
  current_setting('test.decisions_admin')::jsonb,
  'Alice convoquée par l’admin'
);

reset role;

select is(
  pg_temp.status_of('c4000000-0000-0000-0000-000000000001')
    || ' ' || pg_temp.status_of('c4000000-0000-0000-0000-000000000002')
    || ' ' || pg_temp.status_of('c4000000-0000-0000-0000-000000000003'),
  'convoked/manuel not_convoked/auto convoked/auto',
  'seul le joueur déplacé est figé ; le suivant de la liste passe en attente'
);

-- Un ancien client n'envoie pas « changed » : recopier le statut calculé ne
-- fige rien, et la décision déjà figée le reste.
select set_config(
  'test.decisions_legacy', pg_temp.decisions('{}'::jsonb)::text, true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_save_match_effectif(
  current_setting('test.auto_match')::uuid,
  2,
  current_setting('test.decisions_legacy')::jsonb,
  'Ancien client'
);

reset role;

select is(
  pg_temp.status_of('c4000000-0000-0000-0000-000000000001')
    || ' ' || pg_temp.status_of('c4000000-0000-0000-0000-000000000002')
    || ' ' || pg_temp.status_of('c4000000-0000-0000-0000-000000000003'),
  'convoked/manuel not_convoked/auto convoked/auto',
  'un ancien client qui recopie le calcul ne fige aucun joueur de plus'
);

select * from finish();
rollback;
