begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('private.match_effectif_drafts') is not null
  and to_regclass('private.match_effectif_draft_entries') is not null,
  'les brouillons d’effectif sont stockés dans le schéma privé'
);

select ok(
  not has_table_privilege(
    'authenticated', 'private.match_effectif_drafts', 'SELECT'
  )
  and not has_table_privilege(
    'authenticated', 'private.match_effectif_draft_entries', 'SELECT'
  ),
  'les brouillons ne sont jamais accessibles directement au client'
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
    'public.admin_publish_match_effectif(uuid,integer,jsonb,text)',
    'EXECUTE'
  ),
  'la publication de l’effectif n’est jamais exposée au rôle anonyme'
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
values ('b3000000-0000-0000-0000-000000000001', 'Brouillon FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  (
    'b4000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000001',
    'Alice', 'Brouillon', false, true, 1,
    'b1000000-0000-0000-0000-000000000002'
  ),
  (
    'b4000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000001',
    'Bruno', 'Brouillon', false, true, 2,
    'b1000000-0000-0000-0000-000000000003'
  ),
  (
    'b4000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000001',
    'Chloé', 'Brouillon', false, true, 3,
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

create or replace function pg_temp.effectif_composition_payload()
returns jsonb
language sql
stable
as $function$
  with ranked as (
    select participant.id,
      participant.convocation_status,
      row_number() over (order by player.position, participant.id) as number
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    where participant.match_id = current_setting('test.effectif_match')::uuid
  )
  select jsonb_agg(
    jsonb_build_object(
      'participant_id', id,
      'zone', case
        when convocation_status = 'not_convoked' then 'not_selected'
        when number = 1 then 'field'
        else 'bench'
      end,
      'x', case when number = 1 then 0.50 else null end,
      'y', case when number = 1 then 0.90 else null end,
      'slot_label', case when number = 1 then 'ATT' else null end,
      'sort_order', number
    ) order by number
  )
  from ranked;
$function$;

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
    'Premier brouillon'
  ) #>> '{has_unpublished_changes}',
  'true',
  'enregistrer crée un brouillon privé non publié'
);

select is(
  (
    select convocation_state::text || '/' || convocation_version::text
    from public.match_sport_workflows
    where match_id = current_setting('test.effectif_match')::uuid
  ),
  'draft/0',
  'le brouillon ne publie ni état ni nouvelle version'
);

select is(
  public.admin_publish_match_effectif(
    current_setting('test.effectif_match')::uuid,
    2,
    pg_temp.effectif_decisions(1),
    'Publication initiale'
  ) #>> '{has_unpublished_changes}',
  'false',
  'la publication explicite nettoie le marqueur de brouillon'
);

select is(
  (
    select convocation_state::text || '/' || convocation_version::text
    from public.match_sport_workflows
    where match_id = current_setting('test.effectif_match')::uuid
  ),
  'published/1',
  'la première publication crée exactement la version 1'
);

select is(
  public.admin_save_match_composition(
    current_setting('test.effectif_match')::uuid,
    '4-4-2',
    pg_temp.effectif_composition_payload(),
    false,
    'Brouillon de composition'
  ) #>> '{field_count}',
  '1',
  'la composition peut être préparée après publication des convocations'
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
  'Alice voit la première convocation publiée'
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
    'Modification non publiée'
  ) #>> '{has_unpublished_changes}',
  'true',
  'une modification après publication reste privée'
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
  'not_convoked',
  'l’administration relit la décision du brouillon'
);

select is(
  (
    select convocation_version
    from public.match_sport_workflows
    where match_id = current_setting('test.effectif_match')::uuid
  ),
  1,
  'enregistrer une modification ne crée pas de version publiée'
);

select throws_ok(
  $$select public.admin_publish_match_composition(
    current_setting('test.effectif_match')::uuid,
    false,
    'Publication interdite'
  )$$,
  '22023',
  'Publish pending convocation changes before publishing the composition',
  'une composition ne peut pas contourner un brouillon d’effectif en attente'
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
  'le joueur conserve la dernière décision publiée pendant le brouillon'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_publish_match_effectif(
    current_setting('test.effectif_match')::uuid,
    2,
    pg_temp.effectif_decisions(2),
    'Publication de la mise à jour'
  ) #>> '{convocation_version}',
  '2',
  'la seconde publication crée exactement la version 2'
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
  'le joueur voit la nouvelle décision uniquement après publication'
);

reset role;
select ok(
  exists (
    select 1
    from private.sport_admin_audit_log audit
    where audit.match_id = current_setting('test.effectif_match')::uuid
      and audit.action = 'save_match_effectif_draft'
  )
  and exists (
    select 1
    from private.sport_admin_audit_log audit
    where audit.match_id = current_setting('test.effectif_match')::uuid
      and audit.action = 'publish_match_effectif'
  ),
  'les enregistrements et publications restent audités séparément'
);

select * from finish();
rollback;
