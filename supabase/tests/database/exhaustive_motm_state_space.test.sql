begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  ('d1000000-0000-0000-0000-000000000001', 'motm-space-admin@example.invalid', '{"first_name":"Admin"}'::jsonb),
  ('d1000000-0000-0000-0000-000000000002', 'motm-space-1@example.invalid', '{"first_name":"Joueur1"}'::jsonb),
  ('d1000000-0000-0000-0000-000000000003', 'motm-space-2@example.invalid', '{"first_name":"Joueur2"}'::jsonb),
  ('d1000000-0000-0000-0000-000000000004', 'motm-space-3@example.invalid', '{"first_name":"Joueur3"}'::jsonb),
  ('d1000000-0000-0000-0000-000000000005', 'motm-space-4@example.invalid', '{"first_name":"Joueur4"}'::jsonb);

update public.profiles
set role = case
      when id = 'd1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'd1000000-0000-0000-0000-000000000001'
  and 'd1000000-0000-0000-0000-000000000005';

insert into public.seasons(id, name, status)
values ('d2000000-0000-0000-0000-000000000001', '2103-2104', 'open');

insert into public.opponents(id, name)
values ('d3000000-0000-0000-0000-000000000001', 'HDM State Space FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
select
  ('d4000000-0000-0000-0000-' || lpad(number::text, 12, '0'))::uuid,
  'd2000000-0000-0000-0000-000000000001',
  format('Joueur%s', number),
  'StateSpace',
  number = 1,
  true,
  number,
  ('d1000000-0000-0000-0000-' || lpad((number + 1)::text, 12, '0'))::uuid
from generate_series(1, 4) number;

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
  'test.exhaustive_motm_match',
  public.create_match_with_odds_and_sport_limit(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    ((now() + interval '1 day') at time zone 'Europe/Paris')::date,
    ((now() + interval '1 day') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 14
  )::text,
  true
);

reset role;

update public.matches
set kickoff_at = now() - interval '2 hours',
    match_date = ((now() - interval '2 hours') at time zone 'Europe/Paris')::date,
    match_time = ((now() - interval '2 hours') at time zone 'Europe/Paris')::time
where id = current_setting('test.exhaustive_motm_match')::uuid;

create or replace function pg_temp.exhaustive_motm_payload()
returns jsonb
language sql
stable
as $function$
  select jsonb_agg(
    jsonb_build_object(
      'participant_id', participant.id,
      'present', true,
      'final_selection_status', case
        when player.position = 1 then 'starter'
        else 'substitute'
      end,
      'goals', 0,
      'clean_sheet', false
    ) order by player.position
  )
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  where participant.match_id = current_setting('test.exhaustive_motm_match')::uuid;
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_finalize_match_sport_postgame(
    current_setting('test.exhaustive_motm_match')::uuid,
    2,
    1,
    pg_temp.exhaustive_motm_payload(),
    'Initialisation de l’espace exhaustif HDM'
  ) #>> '{vote_state}',
  'open',
  'la finalisation ouvre le scrutin exhaustif'
);

reset role;

create temporary table pg_temp.motm_people (
  player_index integer primary key,
  profile_id uuid not null,
  participant_id uuid not null,
  season_player_id uuid not null
) on commit drop;

insert into pg_temp.motm_people(player_index, profile_id, participant_id, season_player_id)
select
  row_number() over (order by player.position)::integer - 1,
  player.profile_id,
  participant.id,
  player.id
from public.match_sport_participants participant
join public.season_players player on player.id = participant.season_player_id
where participant.match_id = current_setting('test.exhaustive_motm_match')::uuid
order by player.position;

create temporary table pg_temp.motm_state_space (
  case_number integer primary key,
  choices text not null,
  expected_total integer not null,
  observed_total integer not null,
  expected_max integer not null,
  observed_max integer not null,
  expected_winner_count integer not null,
  observed_winner_count integer not null,
  observed_stat_winner_count integer not null,
  result_rows integer not null,
  mismatch boolean not null
) on commit drop;

do $state_space$
declare
  v_case integer;
  v_voter_index integer;
  v_choice integer;
  v_candidate uuid;
  v_profile uuid;
  v_choices text;
  v_expected_total integer;
  v_expected_max integer;
  v_expected_winners integer;
  v_observed_total integer;
  v_observed_max integer;
  v_observed_winners integer;
  v_observed_stat_winners integer;
  v_result_rows integer;
begin
  for v_case in 0..255
  loop
    delete from public.match_sport_motm_votes
    where match_id = current_setting('test.exhaustive_motm_match')::uuid;
    delete from public.match_sport_motm_results
    where match_id = current_setting('test.exhaustive_motm_match')::uuid;
    delete from public.match_man_of_match
    where match_id = current_setting('test.exhaustive_motm_match')::uuid;

    update public.match_sport_motm_elections
    set state = 'open',
        opens_at = now() - interval '1 hour',
        closes_at = now() + interval '1 hour',
        closed_at = null,
        total_votes = 0,
        max_votes = 0,
        updated_at = now()
    where match_id = current_setting('test.exhaustive_motm_match')::uuid;

    v_choices := '';
    for v_voter_index in 0..3
    loop
      v_choice := (v_case / (4 ^ v_voter_index)::integer) % 4;
      v_choices := v_choices || v_choice::text;
      if v_choice = 0 then
        continue;
      end if;

      select person.profile_id into v_profile
      from pg_temp.motm_people person
      where person.player_index = v_voter_index;

      select candidate.participant_id into v_candidate
      from pg_temp.motm_people candidate
      where candidate.player_index <> v_voter_index
      order by candidate.player_index
      offset v_choice - 1
      limit 1;

      insert into public.match_sport_motm_votes(
        match_id,
        voter_profile_id,
        candidate_participant_id,
        finalization_version
      ) values (
        current_setting('test.exhaustive_motm_match')::uuid,
        v_profile,
        v_candidate,
        1
      );
    end loop;

    select count(*)::integer
    into v_expected_total
    from public.match_sport_motm_votes vote
    where vote.match_id = current_setting('test.exhaustive_motm_match')::uuid;

    with candidate_counts as (
      select person.participant_id,
        count(vote.voter_profile_id)::integer as votes_count
      from pg_temp.motm_people person
      left join public.match_sport_motm_votes vote
        on vote.match_id = current_setting('test.exhaustive_motm_match')::uuid
       and vote.candidate_participant_id = person.participant_id
      group by person.participant_id
    )
    select
      coalesce(max(votes_count), 0),
      case
        when coalesce(sum(votes_count), 0) = 0 then 0
        else count(*) filter (
          where votes_count = (select max(votes_count) from candidate_counts)
        )::integer
      end
    into v_expected_max, v_expected_winners
    from candidate_counts;

    perform private.close_match_motm_election(
      current_setting('test.exhaustive_motm_match')::uuid,
      false
    );

    select election.total_votes, election.max_votes
    into v_observed_total, v_observed_max
    from public.match_sport_motm_elections election
    where election.match_id = current_setting('test.exhaustive_motm_match')::uuid;

    select
      count(*) filter (where result.is_winner)::integer,
      count(*)::integer
    into v_observed_winners, v_result_rows
    from public.match_sport_motm_results result
    where result.match_id = current_setting('test.exhaustive_motm_match')::uuid;

    select count(*)::integer
    into v_observed_stat_winners
    from public.match_man_of_match winner
    where winner.match_id = current_setting('test.exhaustive_motm_match')::uuid;

    insert into pg_temp.motm_state_space values (
      v_case,
      v_choices,
      v_expected_total,
      v_observed_total,
      v_expected_max,
      v_observed_max,
      v_expected_winners,
      v_observed_winners,
      v_observed_stat_winners,
      v_result_rows,
      v_expected_total <> v_observed_total
        or v_expected_max <> v_observed_max
        or v_expected_winners <> v_observed_winners
        or v_expected_winners <> v_observed_stat_winners
        or v_result_rows <> 4
    );
  end loop;
end;
$state_space$;

select diag(format(
  'STATE_SPACE motm case=%s choices=%s expected_total=%s observed_total=%s expected_max=%s observed_max=%s expected_winners=%s observed_winners=%s stat_winners=%s rows=%s mismatch=%s',
  case_number,
  choices,
  expected_total,
  observed_total,
  expected_max,
  observed_max,
  expected_winner_count,
  observed_winner_count,
  observed_stat_winner_count,
  result_rows,
  mismatch
))
from pg_temp.motm_state_space
order by case_number;

select is(
  (select count(*) from pg_temp.motm_state_space),
  256::bigint,
  'les 256 répartitions possibles de quatre votants sont exécutées'
);

select is(
  (select count(*) from pg_temp.motm_state_space where mismatch),
  0::bigint,
  'chaque répartition produit les bons totaux, maximums et co-HDM'
);

select is(
  (
    select observed_winner_count
    from pg_temp.motm_state_space
    where expected_total = 0
    limit 1
  ),
  0,
  'zéro vote ne produit aucun Homme du Match'
);

select ok(
  exists (
    select 1 from pg_temp.motm_state_space
    where observed_winner_count = 1
  )
  and exists (
    select 1 from pg_temp.motm_state_space
    where observed_winner_count = 2
  )
  and exists (
    select 1 from pg_temp.motm_state_space
    where observed_winner_count = 3
  )
  and exists (
    select 1 from pg_temp.motm_state_space
    where observed_winner_count = 4
  ),
  'les victoires uniques et les égalités à deux, trois et quatre sont couvertes'
);

select is(
  (
    select count(*)
    from public.match_sport_motm_votes vote
    join pg_temp.motm_people voter on voter.profile_id = vote.voter_profile_id
    join pg_temp.motm_people candidate
      on candidate.participant_id = vote.candidate_participant_id
    where vote.match_id = current_setting('test.exhaustive_motm_match')::uuid
      and voter.player_index = candidate.player_index
  ),
  0::bigint,
  'aucun scénario ne contient d’auto-vote'
);

select * from finish();
rollback;
