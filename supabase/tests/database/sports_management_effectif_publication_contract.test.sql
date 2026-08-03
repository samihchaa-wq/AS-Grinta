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
