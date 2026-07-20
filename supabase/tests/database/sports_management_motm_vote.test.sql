begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('public.match_sport_motm_elections') is not null
  and to_regclass('public.match_sport_motm_votes') is not null
  and to_regclass('public.match_sport_motm_results') is not null,
  'les tables du scrutin HDM existent'
);

select ok(
  (
    select bool_and(relrowsecurity)
    from pg_class
    where oid in (
      'public.match_sport_motm_elections'::regclass,
      'public.match_sport_motm_votes'::regclass,
      'public.match_sport_motm_results'::regclass
    )
  ),
  'RLS est activée sur toutes les tables du scrutin'
);

select is(
  (
    select count(*)
    from unnest(array[
      'public.get_match_motm_vote(uuid)',
      'public.cast_match_motm_vote(uuid,uuid)',
      'public.admin_cancel_match_motm_vote(uuid,text)',
      'public.admin_restart_match_motm_vote(uuid,text)'
    ]::text[]) expected(signature)
    join pg_proc procedure on procedure.oid = to_regprocedure(expected.signature)
    where procedure.prosecdef
  ),
  0::bigint,
  'les RPC publiques HDM restent SECURITY INVOKER'
);

select ok(
  not has_function_privilege('anon', 'public.get_match_motm_vote(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.cast_match_motm_vote(uuid,uuid)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.match_sport_motm_votes', 'SELECT')
  and not has_table_privilege('authenticated', 'public.match_sport_motm_votes', 'INSERT'),
  'les bulletins sont secrets et inaccessibles directement'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  ('c1000000-0000-0000-0000-000000000001', 'motm-admin@example.invalid', '{"first_name":"Admin"}'::jsonb),
  ('c1000000-0000-0000-0000-000000000002', 'motm-one@example.invalid', '{"first_name":"Votant Un"}'::jsonb),
  ('c1000000-0000-0000-0000-000000000003', 'motm-two@example.invalid', '{"first_name":"Votant Deux"}'::jsonb),
  ('c1000000-0000-0000-0000-000000000004', 'motm-absent@example.invalid', '{"first_name":"Absent"}'::jsonb);

update public.profiles
set role = case
      when id = 'c1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'c1000000-0000-0000-0000-000000000001',
  'c1000000-0000-0000-0000-000000000002',
  'c1000000-0000-0000-0000-000000000003',
  'c1000000-0000-0000-0000-000000000004'
);

insert into public.seasons(id, name, status)
values ('c2000000-0000-0000-0000-000000000001', '2096-2097', 'open');
insert into public.opponents(id, name)
values ('c3000000-0000-0000-0000-000000000001', 'Vote FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
) values
  (
    'c4000000-0000-0000-0000-000000000001',
    'c2000000-0000-0000-0000-000000000001',
    'Votant', 'Un', false, true, 1,
    'c1000000-0000-0000-0000-000000000002'
  ),
  (
    'c4000000-0000-0000-0000-000000000002',
    'c2000000-0000-0000-0000-000000000001',
    'Votant', 'Deux', false, true, 2,
    'c1000000-0000-0000-0000-000000000003'
  ),
  (
    'c4000000-0000-0000-0000-000000000003',
    'c2000000-0000-0000-0000-000000000001',
    'Joueur', 'Absent', false, true, 3,
    'c1000000-0000-0000-0000-000000000004'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'c1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.motm_match',
  public.create_match_with_odds_and_sport_limit(
    'c2000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 14
  )::text,
  true
);

select set_config(
  'test.motm_guest_result',
  public.admin_add_or_reuse_match_guest(
    current_setting('test.motm_match')::uuid,
    null,
    'Renfort',
    'Invité',
    false,
    'Test du vote HDM'
  )::text,
  true
);
select set_config(
  'test.motm_guest_participant',
  current_setting('test.motm_guest_result')::jsonb ->> 'participant_id',
  true
);

reset role;
select set_config(
  'test.motm_player_one_participant',
  (
    select participant.id::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.motm_match')::uuid
      and participant.season_player_id =
        'c4000000-0000-0000-0000-000000000001'::uuid
  ),
  true
);
update public.matches
set kickoff_at = now() - interval '2 hours',
    match_date = ((now() - interval '2 hours') at time zone 'Europe/Paris')::date,
    match_time = ((now() - interval '2 hours') at time zone 'Europe/Paris')::time
where id = current_setting('test.motm_match')::uuid;

create or replace function pg_temp.motm_final_payload(
  p_guest_present boolean default true
)
returns jsonb
language sql
stable
as $function$
  select jsonb_agg(
    jsonb_build_object(
      'participant_id', participant.id,
      'present', case
        when participant.guest_player_id is not null then p_guest_present
        when participant.season_player_id in (
          'c4000000-0000-0000-0000-000000000001'::uuid,
          'c4000000-0000-0000-0000-000000000002'::uuid
        ) then true
        else false
      end,
      'final_selection_status', case
        when participant.season_player_id =
          'c4000000-0000-0000-0000-000000000001'::uuid then 'starter'
        when participant.season_player_id =
          'c4000000-0000-0000-0000-000000000002'::uuid then 'substitute'
        when participant.guest_player_id is not null and p_guest_present
          then 'substitute'
        else 'not_selected'
      end,
      'goals', 0,
      'clean_sheet', false
    ) order by participant.id
  )
  from public.match_sport_participants participant
  where participant.match_id = current_setting('test.motm_match')::uuid;
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_finalize_match_sport_postgame(
    current_setting('test.motm_match')::uuid,
    0,
    0,
    pg_temp.motm_final_payload(true),
    'Validation ouvrant le scrutin'
  ) #>> '{vote_state}',
  'open',
  'la validation finale ouvre automatiquement le scrutin'
);

reset role;
select is(
  (
    select extract(epoch from (closes_at - opens_at))::integer
    from public.match_sport_motm_elections
    where match_id = current_setting('test.motm_match')::uuid
  ),
  86400,
  'la fenêtre de vote dure exactement vingt-quatre heures'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000004","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.cast_match_motm_vote(
    current_setting('test.motm_match')::uuid,
    current_setting('test.motm_player_one_participant')::uuid
  )$$,
  '42501',
  'Only a permanently registered present player can vote',
  'un joueur réellement absent ne peut pas voter'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(
  public.get_match_motm_vote(current_setting('test.motm_match')::uuid)
    #>> '{can_vote}',
  'true',
  'un permanent présent peut voter'
);
select throws_ok(
  $$select public.cast_match_motm_vote(
    current_setting('test.motm_match')::uuid,
    current_setting('test.motm_player_one_participant')::uuid
  )$$,
  '22023',
  'A player cannot vote for himself',
  'l’auto-vote est interdit'
);
select is(
  public.cast_match_motm_vote(
    current_setting('test.motm_match')::uuid,
    current_setting('test.motm_guest_participant')::uuid
  ) #>> '{accepted}',
  'true',
  'un invité présent peut recevoir un vote'
);
select throws_ok(
  $$select public.cast_match_motm_vote(
    current_setting('test.motm_match')::uuid,
    current_setting('test.motm_guest_participant')::uuid
  )$$,
  '23505',
  'MOTM vote is immutable and has already been cast',
  'le vote est unique et irréversible'
);
select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      public.get_match_motm_vote(current_setting('test.motm_match')::uuid)
        -> 'candidates'
    ) candidate
    where candidate -> 'votes_count' <> 'null'::jsonb
  ),
  'aucun résultat provisoire n’est exposé'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(
  public.cast_match_motm_vote(
    current_setting('test.motm_match')::uuid,
    current_setting('test.motm_player_one_participant')::uuid
  ) #>> '{accepted}',
  'true',
  'le deuxième joueur vote pour un permanent présent'
);

reset role;
update public.match_sport_motm_elections
set opens_at = now() - interval '25 hours',
    closes_at = now() - interval '1 hour'
where match_id = current_setting('test.motm_match')::uuid;

select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(
  public.get_match_motm_vote(current_setting('test.motm_match')::uuid)
    #>> '{state}',
  'closed',
  'la lecture clôture un scrutin arrivé à échéance'
);
select is(
  (public.get_match_motm_vote(current_setting('test.motm_match')::uuid)
    ->> 'total_votes')::integer,
  2,
  'les deux bulletins sont comptés'
);
select is(
  (
    select count(*)
    from jsonb_array_elements(
      public.get_match_motm_vote(current_setting('test.motm_match')::uuid)
        -> 'candidates'
    ) candidate
    where (candidate ->> 'is_winner')::boolean
  ),
  2::bigint,
  'une égalité produit plusieurs co-HDM'
);
select throws_ok(
  $$select public.cast_match_motm_vote(
    current_setting('test.motm_match')::uuid,
    current_setting('test.motm_guest_participant')::uuid
  )$$,
  '22023',
  'MOTM vote is closed',
  'aucun vote n’est accepté à ou après l’échéance'
);

reset role;
select is(
  (
    select count(*)
    from public.match_man_of_match
    where match_id = current_setting('test.motm_match')::uuid
  ),
  1::bigint,
  'le co-HDM permanent alimente les statistiques existantes'
);
select is(
  (
    select count(*)
    from public.match_man_of_match mvp
    join public.season_players player
      on player.id = mvp.season_player_id
    where mvp.match_id = current_setting('test.motm_match')::uuid
      and player.profile_id =
        'c1000000-0000-0000-0000-000000000002'::uuid
  ),
  1::bigint,
  'le HDM permanent est relié au bon profil statistique'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(
  public.admin_finalize_match_sport_postgame(
    current_setting('test.motm_match')::uuid,
    0,
    0,
    pg_temp.motm_final_payload(false),
    'Correction sans invité présent'
  ) #>> '{vote_state}',
  'open',
  'une correction ouvre un nouveau scrutin de vingt-quatre heures'
);

reset role;
select is(
  (select count(*) from public.match_sport_motm_votes
   where match_id = current_setting('test.motm_match')::uuid),
  0::bigint,
  'la correction supprime les anciens bulletins'
);
select is(
  (select count(*) from public.match_sport_motm_results
   where match_id = current_setting('test.motm_match')::uuid),
  0::bigint,
  'la correction supprime les anciens résultats'
);
select is(
  (select count(*) from public.match_man_of_match
   where match_id = current_setting('test.motm_match')::uuid),
  0::bigint,
  'la correction retire les anciens HDM des statistiques'
);

set local role authenticated;
select is(
  public.admin_cancel_match_motm_vote(
    current_setting('test.motm_match')::uuid,
    'Scrutin annulé pour contrôle'
  ) #>> '{state}',
  'cancelled',
  'l’administrateur peut annuler avec motif'
);
select is(
  public.admin_restart_match_motm_vote(
    current_setting('test.motm_match')::uuid,
    'Nouveau scrutin contrôlé'
  ) #>> '{state}',
  'open',
  'l’administrateur peut relancer une fenêtre complète'
);

reset role;
select ok(
  exists (
    select 1
    from private.sport_admin_audit_log
    where match_id = current_setting('test.motm_match')::uuid
      and action = 'cancel_motm_vote'
      and reason = 'Scrutin annulé pour contrôle'
  )
  and exists (
    select 1
    from private.sport_admin_audit_log
    where match_id = current_setting('test.motm_match')::uuid
      and action = 'restart_motm_vote'
      and reason = 'Nouveau scrutin contrôlé'
  ),
  'les actions administrateur sont entièrement auditées'
);

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = 'c1000000-0000-0000-0000-000000000001'
where key = 'sports_management';
select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_match_motm_vote(
    current_setting('test.motm_match')::uuid
  )$$,
  '42501',
  'Sports-management module is disabled',
  'le feature flag désactivé bloque entièrement le scrutin'
);

reset role;
select * from finish();
rollback;
