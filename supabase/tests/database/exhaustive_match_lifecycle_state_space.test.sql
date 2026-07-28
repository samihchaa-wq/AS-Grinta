begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  ('e1000000-0000-0000-0000-000000000001', 'match-space-admin@example.invalid', '{"first_name":"Admin"}'::jsonb),
  ('e1000000-0000-0000-0000-000000000002', 'match-space-player@example.invalid', '{"first_name":"Player"}'::jsonb);

update public.profiles
set role = case
      when id = 'e1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'e1000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000002'
);

insert into public.seasons(id, name, status)
values
  ('e2000000-0000-0000-0000-000000000001', '2098-2099', 'open'),
  ('e2000000-0000-0000-0000-000000000002', '2097-2098', 'closed');

insert into public.opponents(id, name)
values
  ('e3000000-0000-0000-0000-000000000001', 'Lifecycle FC'),
  ('e3000000-0000-0000-0000-000000000002', 'Collision FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
) values (
  'e4000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001',
  'Player', 'Lifecycle', false, true, 1,
  'e1000000-0000-0000-0000-000000000002'
);

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'e1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"e1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

create temporary table pg_temp.match_creation_state_space (
  season_kind text not null,
  location text not null,
  match_date date not null,
  odds numeric not null,
  expected_success boolean not null,
  observed_success boolean not null,
  observed_sqlstate text,
  observed_message text
) on commit drop;

do $state_space$
declare
  v_season_kind text;
  v_season_id uuid;
  v_location text;
  v_date date;
  v_odds numeric;
  v_match_id uuid;
  v_success boolean;
  v_sqlstate text;
  v_message text;
begin
  foreach v_season_kind in array array['open', 'closed', 'missing']
  loop
    v_season_id := case v_season_kind
      when 'open' then 'e2000000-0000-0000-0000-000000000001'::uuid
      when 'closed' then 'e2000000-0000-0000-0000-000000000002'::uuid
      else '00000000-0000-0000-0000-000000000000'::uuid
    end;

    foreach v_location in array array['domicile', 'exterieur', 'invalid']
    loop
      foreach v_date in array array[
        date '1999-12-31',
        date '2000-01-01',
        date '2100-12-31',
        date '2101-01-01'
      ]
      loop
        foreach v_odds in array array[
          1.00::numeric,
          1.01::numeric,
          100.00::numeric,
          100.01::numeric
        ]
        loop
          v_match_id := null;
          v_success := true;
          v_sqlstate := null;
          v_message := null;
          begin
            v_match_id := public.create_match_with_odds(
              v_season_id,
              'e3000000-0000-0000-0000-000000000001',
              v_date,
              time '18:00',
              v_location,
              v_odds,
              v_odds,
              v_odds
            );
          exception when others then
            v_success := false;
            v_sqlstate := sqlstate;
            v_message := sqlerrm;
          end;

          insert into pg_temp.match_creation_state_space values (
            v_season_kind,
            v_location,
            v_date,
            v_odds,
            v_season_kind = 'open'
              and v_location in ('domicile', 'exterieur')
              and v_date between date '2000-01-01' and date '2100-12-31'
              and v_odds between 1.01 and 100,
            v_success,
            v_sqlstate,
            v_message
          );

          if v_match_id is not null then
            perform public.delete_match(v_match_id);
          end if;
        end loop;
      end loop;
    end loop;
  end loop;
end;
$state_space$;

select diag(format(
  'STATE_SPACE match_create season=%s location=%s date=%s odds=%s expected=%s observed=%s sqlstate=%s message=%s',
  season_kind,
  location,
  match_date,
  odds,
  expected_success,
  observed_success,
  coalesce(observed_sqlstate, '-'),
  coalesce(observed_message, '-')
))
from pg_temp.match_creation_state_space
order by season_kind, location, match_date, odds;

select is(
  (select count(*) from pg_temp.match_creation_state_space),
  144::bigint,
  'les 144 créations aux bornes sont exécutées'
);

select is(
  (
    select count(*)
    from pg_temp.match_creation_state_space
    where expected_success is distinct from observed_success
  ),
  0::bigint,
  'toutes les créations suivent le contrat date, lieu, saison et cotes'
);

select throws_ok(
  $$select public.create_match_with_odds(
    null,
    'e3000000-0000-0000-0000-000000000001',
    date '2099-01-01', time '18:00', 'domicile', 2, 3, 4
  )$$,
  '22023',
  'une saison nulle est refusée'
);
select throws_ok(
  $$select public.create_match_with_odds(
    'e2000000-0000-0000-0000-000000000001',
    null,
    date '2099-01-01', time '18:00', 'domicile', 2, 3, 4
  )$$,
  '22023',
  'un adversaire nul est refusé'
);
select throws_ok(
  $$select public.create_match_with_odds(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    null, time '18:00', 'domicile', 2, 3, 4
  )$$,
  '22023',
  'une date nulle est refusée'
);
select throws_ok(
  $$select public.create_match_with_odds(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    date '2099-01-01', null, 'domicile', 2, 3, 4
  )$$,
  '22023',
  'une heure nulle est refusée'
);

-- Un joueur ne peut jamais créer, modifier, archiver ou supprimer.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"e1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.create_match_with_odds(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    date '2099-02-01', time '18:00', 'domicile', 2, 3, 4
  )$$,
  '42501',
  'un joueur ne peut pas créer un match'
);
select throws_ok(
  $$select public.archive_match('00000000-0000-0000-0000-000000000000')$$,
  '42501',
  'un joueur ne peut pas archiver un match'
);
select throws_ok(
  $$select public.delete_match('00000000-0000-0000-0000-000000000000')$$,
  '42501',
  'un joueur ne peut pas supprimer un match'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"e1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

-- Collision : la règle actuelle autorise un seul match par date, même à une autre heure.
select set_config(
  'test.lifecycle_collision_match',
  public.create_match_with_odds_and_sport_limit(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    date '2099-03-01', time '18:00', 'domicile', 2, 3, 4, 14
  )::text,
  true
);

select throws_ok(
  $$select public.create_match_with_odds(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000002',
    date '2099-03-01', time '18:00', 'exterieur', 2, 3, 4
  )$$,
  '23505',
  'une collision exacte est refusée'
);
select throws_ok(
  $$select public.create_match_with_odds(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000002',
    date '2099-03-01', time '21:00', 'exterieur', 2, 3, 4
  )$$,
  '23505',
  'un second match le même jour est aussi refusé quelle que soit l’heure'
);

-- Un report par modification conserve l’identité et les données liées.
reset role;
insert into public.match_predictions(
  match_id, profile_id, predicted_score_as_grinta,
  predicted_score_adverse, is_filled, use_x2
) values (
  current_setting('test.lifecycle_collision_match')::uuid,
  'e1000000-0000-0000-0000-000000000002',
  2, 1, true, false
);

select set_config(
  'test.lifecycle_participant_count',
  (
    select count(*)::text
    from public.match_sport_participants
    where match_id = current_setting('test.lifecycle_collision_match')::uuid
  ),
  true
);

set local role authenticated;
select ok(
  public.update_match_with_odds(
    current_setting('test.lifecycle_collision_match')::uuid,
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    date '2099-03-02', time '20:30',
    'domicile', 'a_venir', 2.2, 3.3, 4.4
  ),
  'le report par changement de date réussit'
);

reset role;
select is(
  (
    select match_date::text || ' ' || match_time::text
    from public.matches
    where id = current_setting('test.lifecycle_collision_match')::uuid
  ),
  '2099-03-02 20:30:00',
  'la nouvelle date et la nouvelle heure sont enregistrées'
);
select is(
  (
    select (kickoff_at at time zone 'Europe/Paris')::date
    from public.matches
    where id = current_setting('test.lifecycle_collision_match')::uuid
  ),
  date '2099-03-02',
  'le coup d’envoi UTC est recalculé lors du report'
);
select is(
  (
    select count(*)
    from public.match_predictions
    where match_id = current_setting('test.lifecycle_collision_match')::uuid
  ),
  1::bigint,
  'le pronostic est conservé lors du report'
);
select is(
  (
    select count(*)::text
    from public.match_sport_participants
    where match_id = current_setting('test.lifecycle_collision_match')::uuid
  ),
  current_setting('test.lifecycle_participant_count'),
  'les participants sportifs sont conservés lors du report'
);
select is(
  (
    select count(*)
    from public.match_sport_workflows
    where match_id = current_setting('test.lifecycle_collision_match')::uuid
  ),
  1::bigint,
  'le workflow sportif est conservé lors du report'
);

-- La date libérée peut recevoir un nouveau match.
set local role authenticated;
select set_config(
  'test.lifecycle_replacement_match',
  public.create_match_with_odds(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000002',
    date '2099-03-01', time '21:00', 'exterieur', 2, 3, 4
  )::text,
  true
);
select ok(
  current_setting('test.lifecycle_replacement_match')::uuid is not null,
  'un nouveau match peut occuper la date libérée'
);

-- Tous les statuts proposés sont testés par le RPC de modification.
create temporary table pg_temp.match_status_state_space (
  proposed_status text primary key,
  expected_success boolean not null,
  observed_success boolean not null,
  observed_sqlstate text,
  observed_message text
) on commit drop;

do $state_space$
declare
  v_status text;
  v_success boolean;
  v_sqlstate text;
  v_message text;
begin
  foreach v_status in array array[
    'a_venir', 'en_cours', 'termine', 'archive', 'annule', 'reporte', 'invalid'
  ]
  loop
    v_success := true;
    v_sqlstate := null;
    v_message := null;
    begin
      perform public.update_match_with_odds(
        current_setting('test.lifecycle_replacement_match')::uuid,
        'e2000000-0000-0000-0000-000000000001',
        'e3000000-0000-0000-0000-000000000002',
        date '2099-03-01', time '21:00',
        'exterieur', v_status,
        case when v_status = 'a_venir' then 2 else null end,
        case when v_status = 'a_venir' then 3 else null end,
        case when v_status = 'a_venir' then 4 else null end
      );
    exception when others then
      v_success := false;
      v_sqlstate := sqlstate;
      v_message := sqlerrm;
    end;

    insert into pg_temp.match_status_state_space values (
      v_status,
      v_status in ('a_venir', 'termine', 'archive'),
      v_success,
      v_sqlstate,
      v_message
    );
  end loop;
end;
$state_space$;

select diag(format(
  'STATE_SPACE match_status proposed=%s expected=%s observed=%s sqlstate=%s message=%s',
  proposed_status,
  expected_success,
  observed_success,
  coalesce(observed_sqlstate, '-'),
  coalesce(observed_message, '-')
))
from pg_temp.match_status_state_space
order by proposed_status;

select is(
  (
    select count(*)
    from pg_temp.match_status_state_space
    where expected_success is distinct from observed_success
  ),
  0::bigint,
  'le contrat des sept statuts proposés est stable'
);

-- Archivage idempotent explicitement vérifié.
perform public.update_match_with_odds(
  current_setting('test.lifecycle_replacement_match')::uuid,
  'e2000000-0000-0000-0000-000000000001',
  'e3000000-0000-0000-0000-000000000002',
  date '2099-03-01', time '21:00',
  'exterieur', 'termine', null, null, null
);
select ok(
  public.archive_match(current_setting('test.lifecycle_replacement_match')::uuid),
  'un match terminé peut être archivé'
);
select throws_ok(
  format(
    'select public.archive_match(%L::uuid)',
    current_setting('test.lifecycle_replacement_match')
  ),
  'P0002',
  'archiver deux fois est explicitement refusé'
);

-- Suppression complète de toutes les dépendances créées dans ce scénario.
select ok(
  public.delete_match(current_setting('test.lifecycle_collision_match')::uuid),
  'la suppression du match reporté réussit'
);
reset role;
select is(
  (
    select count(*)
    from public.matches
    where id = current_setting('test.lifecycle_collision_match')::uuid
  ),
  0::bigint,
  'la ligne match est supprimée'
);
select is(
  (
    select count(*)
    from public.match_odds
    where match_id = current_setting('test.lifecycle_collision_match')::uuid
  ),
  0::bigint,
  'les cotes liées sont supprimées'
);
select is(
  (
    select count(*)
    from public.match_predictions
    where match_id = current_setting('test.lifecycle_collision_match')::uuid
  ),
  0::bigint,
  'les pronostics liés sont supprimés'
);
select is(
  (
    select count(*)
    from public.match_sport_workflows
    where match_id = current_setting('test.lifecycle_collision_match')::uuid
  ),
  0::bigint,
  'le workflow sportif lié est supprimé'
);
select is(
  (
    select count(*)
    from public.match_sport_participants
    where match_id = current_setting('test.lifecycle_collision_match')::uuid
  ),
  0::bigint,
  'les participants sportifs liés sont supprimés'
);

select * from finish();
rollback;
