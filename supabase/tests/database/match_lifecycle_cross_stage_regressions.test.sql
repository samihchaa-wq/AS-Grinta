begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data) values
  (
    'fa100000-0000-0000-0000-000000000001',
    'cross-stage-admin@example.invalid',
    '{"first_name":"Admin","last_name":"CrossStage"}'::jsonb
  ),
  (
    'fa100000-0000-0000-0000-000000000002',
    'cross-stage-a@example.invalid',
    '{"first_name":"Alpha","last_name":"CrossStage"}'::jsonb
  ),
  (
    'fa100000-0000-0000-0000-000000000003',
    'cross-stage-b@example.invalid',
    '{"first_name":"Beta","last_name":"CrossStage"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'fa100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'fa100000-0000-0000-0000-000000000001',
  'fa100000-0000-0000-0000-000000000002',
  'fa100000-0000-0000-0000-000000000003'
);

insert into public.seasons(id, name, status)
values ('fa200000-0000-0000-0000-000000000001', '2099-2100', 'open');

insert into public.opponents(id, name)
values ('fa300000-0000-0000-0000-000000000001', 'Cross Stage FC');

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position,
  profile_id
) values
  (
    'fa400000-0000-0000-0000-000000000001',
    'fa200000-0000-0000-0000-000000000001',
    'Alpha',
    'CrossStage',
    false,
    true,
    1,
    'fa100000-0000-0000-0000-000000000002'
  ),
  (
    'fa400000-0000-0000-0000-000000000002',
    'fa200000-0000-0000-0000-000000000001',
    'Beta',
    'CrossStage',
    false,
    true,
    2,
    'fa100000-0000-0000-0000-000000000003'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'fa100000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.cross_stage_match',
  public.admin_create_match_complete(
    'fa200000-0000-0000-0000-000000000001',
    'fa300000-0000-0000-0000-000000000001',
    ((now() + interval '2 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '2 days') at time zone 'Europe/Paris')::time,
    'domicile',
    2.10,
    3.20,
    2.90,
    null,
    null,
    false,
    'championnat',
    null
  )::text,
  true
);

reset role;

select is(
  (
    select count(*)
    from public.match_sport_workflows
    where match_id = current_setting('test.cross_stage_match')::uuid
  ),
  1::bigint,
  'un match normal créé sans limite explicite possède quand même son workflow sportif'
);

select is(
  (
    select squad_size_limit
    from public.match_sport_workflows
    where match_id = current_setting('test.cross_stage_match')::uuid
  ),
  14,
  'la limite par défaut est résolue côté serveur'
);

select set_config(
  'test.cross_stage_updated_at',
  (
    select updated_at::text
    from public.matches
    where id = current_setting('test.cross_stage_match')::uuid
  ),
  true
);

select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.admin_update_match_complete(
    current_setting('test.cross_stage_match')::uuid,
    'fa200000-0000-0000-0000-000000000001',
    'fa300000-0000-0000-0000-000000000001',
    ((now() + interval '10 minutes') at time zone 'Europe/Paris')::date,
    ((now() + interval '10 minutes') at time zone 'Europe/Paris')::time,
    'domicile',
    'a_venir',
    2.10,
    3.20,
    2.90,
    current_setting('test.cross_stage_updated_at')::timestamptz,
    null,
    null,
    false,
    'championnat',
    null
  ),
  'un report sans limite explicite repasse quand même par le workflow sportif'
);

reset role;

select is(
  (
    select workflow.availability_opens_at
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    where workflow.match_id = current_setting('test.cross_stage_match')::uuid
  ),
  (
    select private.match_features_open_at(match.kickoff_at)
    from public.matches match
    where match.id = current_setting('test.cross_stage_match')::uuid
  ),
  'le report recalcule la fenêtre de disponibilité'
);

select is(
  (
    select workflow.late_withdrawal_cutoff_at
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.cross_stage_match')::uuid
  ),
  (
    select (
      (((match.kickoff_at at time zone 'Europe/Paris')::date - 1) + time '12:00')
      at time zone 'Europe/Paris'
    )
    from public.matches match
    where match.id = current_setting('test.cross_stage_match')::uuid
  ),
  'le report recalcule le cutoff de liste d’attente'
);

-- Both players answer available through the real player RPC.
select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  format(
    'select public.set_my_match_availability(%L::uuid,%L,%L)',
    current_setting('test.cross_stage_match'),
    'available',
    null
  ),
  'Alpha peut se déclarer disponible'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  format(
    'select public.set_my_match_availability(%L::uuid,%L,%L)',
    current_setting('test.cross_stage_match'),
    'available',
    null
  ),
  'Beta peut se déclarer disponible'
);

-- Staff deliberately leaves Beta on the waitlist, publishes convocations,
-- then publishes a composition with Alpha on the field and Beta not selected.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.admin_set_match_convocation(%L::uuid,%L::uuid,%L,true,%L)',
    current_setting('test.cross_stage_match'),
    'fa400000-0000-0000-0000-000000000002',
    'not_convoked',
    'Regression cross-stage'
  ),
  'Beta peut être placé explicitement en liste d’attente'
);

select lives_ok(
  format(
    'select public.admin_publish_match_convocations(%L::uuid,%L)',
    current_setting('test.cross_stage_match'),
    'Regression cross-stage'
  ),
  'les convocations sont publiées'
);

select lives_ok(
  format(
    $sql$
      select public.admin_save_match_composition(
        %L::uuid,
        '4-4-2',
        jsonb_build_array(
          jsonb_build_object(
            'participant_id', (
              select id from public.match_sport_participants
              where match_id = %L::uuid
                and season_player_id = 'fa400000-0000-0000-0000-000000000001'
            ),
            'zone', 'field', 'x', 0.5, 'y', 0.5,
            'slot_label', '9', 'sort_order', 0
          ),
          jsonb_build_object(
            'participant_id', (
              select id from public.match_sport_participants
              where match_id = %L::uuid
                and season_player_id = 'fa400000-0000-0000-0000-000000000002'
            ),
            'zone', 'not_selected', 'x', null, 'y', null,
            'slot_label', null, 'sort_order', 1
          )
        ),
        false,
        'Regression cross-stage'
      )
    $sql$,
    current_setting('test.cross_stage_match'),
    current_setting('test.cross_stage_match'),
    current_setting('test.cross_stage_match')
  ),
  'la composition est enregistrée'
);

select lives_ok(
  format(
    'select public.admin_publish_match_composition(%L::uuid,false,%L)',
    current_setting('test.cross_stage_match'),
    'Regression cross-stage'
  ),
  'la composition est publiée'
);

-- Alpha withdraws after publication. The real workflow must promote Beta.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  format(
    'select public.set_my_match_availability(%L::uuid,%L,%L)',
    current_setting('test.cross_stage_match'),
    'absent',
    'Retrait après publication'
  ),
  'Alpha peut se retirer après publication'
);

reset role;
select is(
  (
    select convocation_status::text
    from public.match_sport_participants
    where match_id = current_setting('test.cross_stage_match')::uuid
      and season_player_id = 'fa400000-0000-0000-0000-000000000001'
  ),
  'not_applicable',
  'Alpha est retiré de la convocation courante'
);

select is(
  (
    select convocation_status::text
    from public.match_sport_participants
    where match_id = current_setting('test.cross_stage_match')::uuid
      and season_player_id = 'fa400000-0000-0000-0000-000000000002'
  ),
  'convoked',
  'Beta est promu après le retrait'
);

select ok(
  (
    select promoted_after_withdrawal_at is not null
    from public.match_sport_participants
    where match_id = current_setting('test.cross_stage_match')::uuid
      and season_player_id = 'fa400000-0000-0000-0000-000000000002'
  ),
  'la promotion est explicitement tracée'
);

-- Opening Live must reconcile the stale publication snapshot.
select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  format(
    'select public.open_match_live_workspace(%L::uuid,90)',
    current_setting('test.cross_stage_match')
  ),
  'le Live s’ouvre après la promotion'
);
reset role;

select is(
  (
    select entry.zone::text
    from public.match_composition_entries entry
    join public.match_sport_participants participant
      on participant.id = entry.participant_id
    where entry.match_id = current_setting('test.cross_stage_match')::uuid
      and participant.season_player_id = 'fa400000-0000-0000-0000-000000000001'
  ),
  'not_selected',
  'le joueur retiré ne réapparaît pas dans le Live'
);

select is(
  (
    select entry.zone::text
    from public.match_composition_entries entry
    join public.match_sport_participants participant
      on participant.id = entry.participant_id
    where entry.match_id = current_setting('test.cross_stage_match')::uuid
      and participant.season_player_id = 'fa400000-0000-0000-0000-000000000002'
  ),
  'bench',
  'le joueur promu est injecté sur le banc du Live'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  format(
    'select public.confirm_start_match_live(%L::uuid,%L)',
    current_setting('test.cross_stage_match'),
    'Regression cross-stage'
  ),
  'le Live démarre avec une feuille cohérente'
);

-- Internal matches are not prediction targets, even through a direct route/RPC.
select set_config(
  'test.cross_stage_internal_match',
  public.create_internal_match(
    'fa200000-0000-0000-0000-000000000001',
    ((now() + interval '1 day') at time zone 'Europe/Paris')::date,
    ((now() + interval '1 day') at time zone 'Europe/Paris')::time,
    null
  )::text,
  true
);
reset role;

select is(
  (
    select count(*)
    from public.match_predictions prediction
    where prediction.match_id = current_setting('test.cross_stage_internal_match')::uuid
  ),
  0::bigint,
  'un match entre nous ne reçoit aucune ligne de pronostic'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  format(
    'select public.save_match_prediction(%L::uuid,1,0)',
    current_setting('test.cross_stage_internal_match')
  ),
  '22023',
  'Les matchs entre nous ne sont pas ouverts aux pronostics.',
  'un appel direct ne peut pas créer de prono sur un match entre nous'
);

-- A player deactivated after participating remains a valid historical scorer.
reset role;
update public.season_players
set is_active = false
where id = 'fa400000-0000-0000-0000-000000000001';

select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.cross_stage_final_match',
  public.admin_create_match_complete(
    'fa200000-0000-0000-0000-000000000001',
    'fa300000-0000-0000-0000-000000000001',
    ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '3 days') at time zone 'Europe/Paris')::time,
    'exterieur',
    2.20,
    3.10,
    3.00,
    null,
    null,
    false,
    'amical',
    null
  )::text,
  true
);

select lives_ok(
  format(
    $sql$
      select public.finalize_match_postgame(
        %L::uuid,
        0,
        jsonb_build_array(
          jsonb_build_object(
            'season_player_id', 'fa400000-0000-0000-0000-000000000001',
            'goals', 1
          )
        ),
        null,
        1
      )
    $sql$,
    current_setting('test.cross_stage_final_match')
  ),
  'un ancien joueur de la saison peut rester buteur après désactivation'
);

reset role;
select is(
  (
    select goals
    from public.match_player_stats
    where match_id = current_setting('test.cross_stage_final_match')::uuid
      and season_player_id = 'fa400000-0000-0000-0000-000000000001'
  ),
  1,
  'le but historique est conservé malgré la désactivation du joueur'
);

select * from finish();
rollback;
