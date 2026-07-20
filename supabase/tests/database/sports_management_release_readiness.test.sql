begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select is(
  (
    select count(*)
    from unnest(array[
      'public.admin_list_match_motm_votes()',
      'public.admin_get_match_motm_dashboard(uuid)',
      'public.admin_close_match_motm_vote_early(uuid,text)',
      'public.admin_get_match_sport_statistics_integrity(uuid)'
    ]::text[]) expected(signature)
    join pg_proc procedure on procedure.oid = to_regprocedure(expected.signature)
    where procedure.prosecdef
  ),
  0::bigint,
  'les RPC publiques de finition restent SECURITY INVOKER'
);

select ok(
  not has_function_privilege('anon', 'public.admin_list_match_motm_votes()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.admin_get_match_motm_dashboard(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.admin_close_match_motm_vote_early(uuid,text)', 'EXECUTE'),
  'aucune RPC de suivi HDM n’est exposée au rôle anonyme'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  ('d1000000-0000-0000-0000-000000000001', 'readiness-admin@example.invalid', '{"first_name":"Admin"}'::jsonb),
  ('d1000000-0000-0000-0000-000000000002', 'readiness-one@example.invalid', '{"first_name":"Joueur Un"}'::jsonb),
  ('d1000000-0000-0000-0000-000000000003', 'readiness-two@example.invalid', '{"first_name":"Joueur Deux"}'::jsonb);

update public.profiles
set role = case
      when id = 'd1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'd1000000-0000-0000-0000-000000000001',
  'd1000000-0000-0000-0000-000000000002',
  'd1000000-0000-0000-0000-000000000003'
);

insert into public.seasons(id, name, status)
values ('d2000000-0000-0000-0000-000000000001', '2095-2096', 'open');
insert into public.opponents(id, name)
values ('d3000000-0000-0000-0000-000000000001', 'Readiness FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
) values
  (
    'd4000000-0000-0000-0000-000000000001',
    'd2000000-0000-0000-0000-000000000001',
    'Joueur', 'Un', false, true, 1,
    'd1000000-0000-0000-0000-000000000002'
  ),
  (
    'd4000000-0000-0000-0000-000000000002',
    'd2000000-0000-0000-0000-000000000001',
    'Joueur', 'Deux', false, true, 2,
    'd1000000-0000-0000-0000-000000000003'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'd1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.readiness_match',
  public.create_match_with_odds_and_sport_limit(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 14
  )::text,
  true
);

reset role;
select set_config(
  'test.readiness_player_one_participant',
  (
    select participant.id::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.readiness_match')::uuid
      and participant.season_player_id = 'd4000000-0000-0000-0000-000000000001'
  ),
  true
);
select set_config(
  'test.readiness_player_two_participant',
  (
    select participant.id::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.readiness_match')::uuid
      and participant.season_player_id = 'd4000000-0000-0000-0000-000000000002'
  ),
  true
);

update public.matches
set kickoff_at = now() - interval '2 hours',
    match_date = ((now() - interval '2 hours') at time zone 'Europe/Paris')::date,
    match_time = ((now() - interval '2 hours') at time zone 'Europe/Paris')::time
where id = current_setting('test.readiness_match')::uuid;

create or replace function pg_temp.readiness_payload()
returns jsonb
language sql
stable
as $function$
  select jsonb_agg(jsonb_build_object(
    'participant_id', participant.id,
    'present', true,
    'final_selection_status', case
      when participant.season_player_id = 'd4000000-0000-0000-0000-000000000001'::uuid
        then 'starter'
      else 'substitute'
    end,
    'goals', case
      when participant.season_player_id = 'd4000000-0000-0000-0000-000000000001'::uuid
        then 1
      else 0
    end,
    'clean_sheet', false
  ) order by participant.id)
  from public.match_sport_participants participant
  where participant.match_id = current_setting('test.readiness_match')::uuid;
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_finalize_match_sport_postgame(
    current_setting('test.readiness_match')::uuid,
    1,
    0,
    pg_temp.readiness_payload(),
    'Validation de bout en bout'
  ) #>> '{vote_state}',
  'open',
  'la validation finale ouvre le vote dans le parcours complet'
);

select is(
  public.admin_get_match_sport_statistics_integrity(
    current_setting('test.readiness_match')::uuid
  ) #>> '{all_ok}',
  'true',
  'les présences, buts et statistiques sont synchronisés avant le résultat HDM'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.cast_match_motm_vote(
    current_setting('test.readiness_match')::uuid,
    current_setting('test.readiness_player_two_participant')::uuid
  ) #>> '{accepted}',
  'true',
  'un joueur présent vote dans le parcours complet'
);

select throws_ok(
  $$select public.admin_list_match_motm_votes()$$,
  '42501',
  'Active administrator role required',
  'un joueur ne peut pas lire le tableau de bord administrateur'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_get_match_motm_dashboard(
    current_setting('test.readiness_match')::uuid
  ) #>> '{votes_received}',
  '1',
  'le tableau de bord compte les bulletins sans les exposer'
);

select is(
  public.admin_get_match_motm_dashboard(
    current_setting('test.readiness_match')::uuid
  ) #>> '{eligible_voter_count}',
  '2',
  'le tableau de bord compte les électeurs réellement présents'
);

select is(
  jsonb_array_length(public.admin_list_match_motm_votes()),
  1,
  'la liste administrateur contient le scrutin validé'
);

select is(
  public.admin_close_match_motm_vote_early(
    current_setting('test.readiness_match')::uuid,
    'Tous les votes attendus sont enregistrés'
  ) #>> '{state}',
  'closed',
  'la clôture anticipée motivée calcule immédiatement le résultat'
);

select is(
  (
    select season_player_id::text
    from public.match_man_of_match
    where match_id = current_setting('test.readiness_match')::uuid
  ),
  'd4000000-0000-0000-0000-000000000002',
  'le gagnant collectif alimente la table statistique historique'
);

select is(
  public.admin_get_match_sport_statistics_integrity(
    current_setting('test.readiness_match')::uuid
  ) #>> '{all_ok}',
  'true',
  'l’intégrité statistique reste complète après la clôture HDM'
);

reset role;
select ok(
  exists (
    select 1
    from private.sport_admin_audit_log audit
    where audit.match_id = current_setting('test.readiness_match')::uuid
      and audit.action = 'close_motm_vote_early'
      and audit.reason = 'Tous les votes attendus sont enregistrés'
  ),
  'la clôture anticipée est auditée avec son motif'
);

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = 'd1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_list_match_motm_votes()$$,
  '42501',
  'Sports-management module is disabled',
  'le feature flag désactivé masque aussi le tableau de bord final'
);

reset role;
select * from finish();
rollback;
