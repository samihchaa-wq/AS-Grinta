begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('private.match_effectif_drafts') is null
  and to_regclass('private.match_effectif_draft_entries') is null,
  'les tables privées de brouillon d’effectif ont disparu'
);

select is(
  (
    select count(*)
    from unnest(array[
      'public.admin_save_match_effectif(uuid,integer,jsonb,text)',
      'public.admin_publish_match_effectif(uuid,integer,jsonb,text)'
    ]::text[]) expected(signature)
    join pg_proc procedure on procedure.oid = to_regprocedure(expected.signature)
    where procedure.prosecdef
  ),
  0::bigint,
  'les RPC publiques d’effectif restent SECURITY INVOKER'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_save_match_effectif(uuid,integer,jsonb,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.admin_publish_match_effectif(uuid,integer,jsonb,text)',
    'EXECUTE'
  ),
  'les écritures d’effectif ne sont jamais exposées au rôle anonyme'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'b1000000-0000-0000-0000-000000000001',
    'effectif-admin@example.invalid',
    '{"first_name":"Admin"}'::jsonb
  ),
  (
    'b1000000-0000-0000-0000-000000000002',
    'effectif-alice@example.invalid',
    '{"first_name":"Alice"}'::jsonb
  ),
  (
    'b1000000-0000-0000-0000-000000000003',
    'effectif-bruno@example.invalid',
    '{"first_name":"Bruno"}'::jsonb
  ),
  (
    'b1000000-0000-0000-0000-000000000004',
    'effectif-chloe@example.invalid',
    '{"first_name":"Chloé"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'b1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'b1000000-0000-0000-0000-000000000001'
  and 'b1000000-0000-0000-0000-000000000004';

insert into public.seasons(id, name, status)
values ('b2000000-0000-0000-0000-000000000001', '2101-2102', 'open');

insert into public.opponents(id, name)
values ('b3000000-0000-0000-0000-000000000001', 'Immediat FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  (
    'b4000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000001',
    'Alice', 'Immediat', false, true, 1,
    'b1000000-0000-0000-0000-000000000002'
  ),
  (
    'b4000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000001',
    'Bruno', 'Immediat', false, true, 2,
    'b1000000-0000-0000-0000-000000000003'
  ),
  (
    'b4000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000001',
    'Chloé', 'Immediat', false, true, 3,
    'b1000000-0000-0000-0000-000000000004'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'b1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.effectif_match',
  public.create_match_with_odds_and_sport_limit(
    'b2000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 2
  )::text,
  true
);

reset role;

update public.match_sport_participants
set availability_status = 'available',
    availability_updated_at = now(),
    availability_updated_by = 'b1000000-0000-0000-0000-000000000001',
    updated_at = now()
where match_id = current_setting('test.effectif_match')::uuid;

create or replace function pg_temp.effectif_decisions(p_version integer)
returns jsonb
language sql
stable
as $function$
  select jsonb_agg(
    jsonb_build_object(
      'season_player_id', player.id,
      'status', case
        when p_version = 1 and player.position <= 2 then 'convoked'
        when p_version = 2 and player.position >= 2 then 'convoked'
        else 'not_convoked'
      end
    ) order by player.position
  )
  from public.season_players player
  where player.season_id = 'b2000000-0000-0000-0000-000000000001';
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_save_match_effectif(
    current_setting('test.effectif_match')::uuid,
    2,
    pg_temp.effectif_decisions(1),
    'Tentative joueur'
  )$$,
  '42501',
  'Active administrator role required',
  'un joueur ne peut pas modifier l’effectif'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_save_match_effectif(
    current_setting('test.effectif_match')::uuid,
    2,
    pg_temp.effectif_decisions(1),
    'Première décision immédiate'
  ) #>> '{has_unpublished_changes}',
  'false',
  'enregistrer ne crée aucun brouillon privé'
);

select is(
  (
    select convocation_state::text || '/' || convocation_version::text
    from public.match_sport_workflows
    where match_id = current_setting('test.effectif_match')::uuid
  ),
  'published/1',
  'le premier save publie immédiatement la version 1'
);

select is(
  (
    select player ->> 'convocation_status'
    from jsonb_array_elements(
      public.admin_get_match_convocations(
        current_setting('test.effectif_match')::uuid
      ) -> 'players'
    ) player
    where player ->> 'season_player_id'
      = 'b4000000-0000-0000-0000-000000000001'
  ),
  'convoked',
  'l’administration relit immédiatement la décision enregistrée'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.get_my_match_availability(
    current_setting('test.effectif_match')::uuid
  ) #>> '{convocation_status}',
  'convoked',
  'Alice voit immédiatement sa convocation'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_save_match_effectif(
    current_setting('test.effectif_match')::uuid,
    2,
    pg_temp.effectif_decisions(2),
    'Deuxième décision immédiate'
  ) #>> '{has_unpublished_changes}',
  'false',
  'une modification après publication reste immédiatement visible'
);

select is(
  (
    select convocation_state::text || '/' || convocation_version::text
    from public.match_sport_workflows
    where match_id = current_setting('test.effectif_match')::uuid
  ),
  'published/2',
  'le deuxième save publie immédiatement la version 2'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.get_my_match_availability(
    current_setting('test.effectif_match')::uuid
  ) #>> '{convocation_status}',
  'not_convoked',
  'Alice voit immédiatement la nouvelle décision sans étape de publication'
);

reset role;

-- La sélection sportive ne doit plus écraser la disponibilité. Bruno reste
-- absent mais peut être pré-convoqué ; Chloé reste sans réponse mais peut être
-- placée en liste d'attente.
update public.match_sport_participants participant
set availability_status = case player.position
      when 2 then 'absent'::public.sport_availability_status
      when 3 then 'no_response'::public.sport_availability_status
      else 'available'::public.sport_availability_status
    end,
    availability_updated_at = now(),
    updated_at = now()
from public.season_players player
where participant.match_id = current_setting('test.effectif_match')::uuid
  and player.id = participant.season_player_id;

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_save_match_effectif(
    current_setting('test.effectif_match')::uuid,
    2,
    pg_temp.effectif_decisions(1),
    'Décisions indépendantes de la disponibilité'
  ) #>> '{convocation_version}',
  '3',
  'les décisions incluent un absent et une sans réponse'
);

reset role;
select ok(
  (
    select participant.availability_status = 'absent'
      and participant.convocation_status = 'convoked'
      and participant.convocation_manual_override
    from public.match_sport_participants participant
    where participant.season_player_id =
      'b4000000-0000-0000-0000-000000000002'
      and participant.match_id = current_setting('test.effectif_match')::uuid
  ),
  'un absent reste absent tout en étant pré-convoqué'
);
select ok(
  (
    select participant.availability_status = 'no_response'
      and participant.convocation_status = 'not_convoked'
      and participant.convocation_manual_override
      and not participant.waitlist_turn_should_consume
      and participant.waitlist_turn_state = 'not_applicable'
    from public.match_sport_participants participant
    where participant.season_player_id =
      'b4000000-0000-0000-0000-000000000003'
      and participant.match_id = current_setting('test.effectif_match')::uuid
  ),
  'une sans réponse reste identifiable et ne consomme aucun tour'
);

-- Replacer les joueurs dans leur colonne d'origine les retire du payload et
-- efface uniquement leur décision sportive, jamais leur disponibilité.
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_save_match_effectif(
    current_setting('test.effectif_match')::uuid,
    2,
    jsonb_build_array(jsonb_build_object(
      'season_player_id', 'b4000000-0000-0000-0000-000000000001',
      'status', 'convoked'
    )),
    'Retour aux colonnes de disponibilité'
  ) #>> '{convocation_version}',
  '4',
  'le retour aux colonnes source est publié immédiatement'
);

reset role;
select is(
  (
    select count(*)
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.effectif_match')::uuid
      and participant.season_player_id in (
        'b4000000-0000-0000-0000-000000000002',
        'b4000000-0000-0000-0000-000000000003'
      )
      and participant.convocation_status = 'not_applicable'
      and not participant.convocation_manual_override
      and (
        (participant.season_player_id =
          'b4000000-0000-0000-0000-000000000002'
          and participant.availability_status = 'absent')
        or
        (participant.season_player_id =
          'b4000000-0000-0000-0000-000000000003'
          and participant.availability_status = 'no_response')
      )
  ),
  2::bigint,
  'le retour source efface les deux décisions sans changer les réponses'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(
  public.admin_save_match_effectif(
    current_setting('test.effectif_match')::uuid,
    2,
    pg_temp.effectif_decisions(1),
    'Réapplication avant réponse'
  ) #>> '{convocation_version}',
  '5',
  'les décisions indisponibles peuvent être réappliquées'
);
reset role;

-- Quand ces joueurs répondent ensuite présent, la décision manuelle est
-- conservée et le tour de liste d'attente devient actif seulement à ce moment.
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_override_match_availability(
    current_setting('test.effectif_match')::uuid,
    'b4000000-0000-0000-0000-000000000002',
    'available',
    null,
    'Retour disponible du pré-convoqué'
  ) #>> '{availability_status}',
  'available',
  'le pré-convoqué peut ensuite se déclarer disponible'
);
select is(
  public.admin_override_match_availability(
    current_setting('test.effectif_match')::uuid,
    'b4000000-0000-0000-0000-000000000003',
    'available',
    null,
    'Réponse du joueur en attente'
  ) #>> '{availability_status}',
  'available',
  'la sans réponse en attente peut ensuite se déclarer disponible'
);

reset role;
select ok(
  (
    select participant.convocation_status = 'convoked'
      and participant.convocation_manual_override
    from public.match_sport_participants participant
    where participant.season_player_id =
      'b4000000-0000-0000-0000-000000000002'
      and participant.match_id = current_setting('test.effectif_match')::uuid
  ),
  'la pré-convocation manuelle survit au retour disponible'
);
select ok(
  (
    select participant.convocation_status = 'not_convoked'
      and participant.waitlist_turn_should_consume
      and participant.waitlist_turn_state = 'pending'
    from public.match_sport_participants participant
    where participant.season_player_id =
      'b4000000-0000-0000-0000-000000000003'
      and participant.match_id = current_setting('test.effectif_match')::uuid
  ),
  'le tour en attente ne devient consommable qu’après la réponse présente'
);

select ok(
  exists (
    select 1
    from private.sport_admin_audit_log audit
    where audit.match_id = current_setting('test.effectif_match')::uuid
      and audit.action = 'update_match_effectif'
  ),
  'les modifications immédiates restent auditées'
);

select * from finish();
rollback;
