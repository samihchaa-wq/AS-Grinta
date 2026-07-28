begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  ('a5100000-0000-0000-0000-000000000001', 'waitlist-space-admin@example.invalid', '{"first_name":"Admin"}'::jsonb),
  ('a5100000-0000-0000-0000-000000000002', 'waitlist-space-one@example.invalid', '{"first_name":"Convoqué"}'::jsonb),
  ('a5100000-0000-0000-0000-000000000003', 'waitlist-space-two@example.invalid', '{"first_name":"Remplaçant"}'::jsonb),
  ('a5100000-0000-0000-0000-000000000004', 'waitlist-space-three@example.invalid', '{"first_name":"Témoin"}'::jsonb);

update public.profiles
set role = case
      when id = 'a5100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'a5100000-0000-0000-0000-000000000001'
  and 'a5100000-0000-0000-0000-000000000004';

insert into public.seasons(id, name, status)
values ('a5200000-0000-0000-0000-000000000001', '2092-2093', 'open');
insert into public.opponents(id, name)
values ('a5300000-0000-0000-0000-000000000001', 'Waitlist State FC');
insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  (
    'a5400000-0000-0000-0000-000000000001',
    'a5200000-0000-0000-0000-000000000001',
    'Convoqué', 'State', false, true, 1,
    'a5100000-0000-0000-0000-000000000002'
  ),
  (
    'a5400000-0000-0000-0000-000000000002',
    'a5200000-0000-0000-0000-000000000001',
    'Remplaçant', 'State', false, true, 2,
    'a5100000-0000-0000-0000-000000000003'
  ),
  (
    'a5400000-0000-0000-0000-000000000003',
    'a5200000-0000-0000-0000-000000000001',
    'Témoin', 'State', false, true, 3,
    'a5100000-0000-0000-0000-000000000004'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'a5100000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"a5100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.waitlist_space_match',
  public.create_match_with_odds_and_sport_limit(
    'a5200000-0000-0000-0000-000000000001',
    'a5300000-0000-0000-0000-000000000001',
    ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '3 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 2
  )::text,
  true
);
reset role;

select set_config(
  'test.waitlist_space_withdrawn',
  (
    select participant.id::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.waitlist_space_match')::uuid
      and participant.season_player_id = 'a5400000-0000-0000-0000-000000000001'
  ),
  true
);
select set_config(
  'test.waitlist_space_candidate',
  (
    select participant.id::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.waitlist_space_match')::uuid
      and participant.season_player_id = 'a5400000-0000-0000-0000-000000000002'
  ),
  true
);
select set_config(
  'test.waitlist_space_witness',
  (
    select participant.id::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.waitlist_space_match')::uuid
      and participant.season_player_id = 'a5400000-0000-0000-0000-000000000003'
  ),
  true
);

create temporary table pg_temp.waitlist_withdrawal_state_space(
  case_number integer primary key,
  cutoff_mode text not null,
  convocation_state text not null,
  withdrawn_status text not null,
  initial_should_consume boolean not null,
  initial_turn_state text not null,
  expected_promotion boolean not null,
  observed_promotion boolean not null,
  expected_candidate_status text not null,
  observed_candidate_status text not null,
  expected_candidate_should_consume boolean not null,
  observed_candidate_should_consume boolean not null,
  expected_candidate_turn_state text not null,
  observed_candidate_turn_state text not null,
  expected_candidate_position integer not null,
  observed_candidate_position integer not null,
  expected_withdrawn_status text not null,
  observed_withdrawn_status text not null,
  observed_sqlstate text,
  observed_message text,
  mismatch boolean not null
) on commit drop;

-- L'ordre est réinitialisé à chaque scénario : candidat en première position,
-- convoqué en deuxième et témoin indisponible en troisième.
do $state_space$
declare
  v_case integer := 0;
  v_cutoff_mode text;
  v_convocation_state text;
  v_withdrawn_status text;
  v_should_consume boolean;
  v_turn_state text;
  v_returned_player uuid;
  v_sqlstate text;
  v_message text;
  v_expected_promotion boolean;
  v_expected_candidate_status text;
  v_expected_candidate_should boolean;
  v_expected_candidate_turn text;
  v_expected_candidate_position integer;
  v_expected_withdrawn_status text;
  v_observed_candidate_status text;
  v_observed_candidate_should boolean;
  v_observed_candidate_turn text;
  v_observed_candidate_position integer;
  v_observed_withdrawn_status text;
  v_mismatch boolean;
begin
  foreach v_cutoff_mode in array array['none', 'future', 'past'] loop
    foreach v_convocation_state in array array['draft', 'published', 'closed'] loop
      foreach v_withdrawn_status in array array['convoked', 'not_convoked', 'not_applicable'] loop
        foreach v_should_consume in array array[false, true] loop
          foreach v_turn_state in array array['not_applicable', 'pending', 'consumed', 'waived'] loop
            v_case := v_case + 1;
            v_returned_player := null;
            v_sqlstate := null;
            v_message := null;

            update public.sport_waitlist_entries
            set position = position + 1000
            where season_id = 'a5200000-0000-0000-0000-000000000001';
            update public.sport_waitlist_entries
            set position = case season_player_id
                  when 'a5400000-0000-0000-0000-000000000002'::uuid then 1
                  when 'a5400000-0000-0000-0000-000000000001'::uuid then 2
                  else 3
                end,
                source = 'manual',
                updated_by = 'a5100000-0000-0000-0000-000000000001',
                updated_at = now()
            where season_id = 'a5200000-0000-0000-0000-000000000001';

            update public.match_sport_workflows
            set convocation_state = v_convocation_state::public.sport_convocation_state,
                late_withdrawal_cutoff_at = case v_cutoff_mode
                  when 'none' then null
                  when 'future' then now() + interval '1 hour'
                  else now() - interval '1 hour'
                end,
                updated_by = 'a5100000-0000-0000-0000-000000000001',
                updated_at = now()
            where match_id = current_setting('test.waitlist_space_match')::uuid;

            update public.match_sport_participants
            set availability_status = 'available',
                convocation_status = v_withdrawn_status::public.sport_convocation_status,
                convocation_manual_override = false,
                waitlist_turn_should_consume = false,
                waitlist_turn_state = 'not_applicable',
                waitlist_turn_updated_at = null,
                promoted_after_withdrawal_at = null,
                promoted_from_participant_id = null,
                updated_at = now()
            where id = current_setting('test.waitlist_space_withdrawn')::uuid;

            update public.match_sport_participants
            set availability_status = 'available',
                convocation_status = 'not_convoked',
                convocation_manual_override = false,
                waitlist_turn_should_consume = v_should_consume,
                waitlist_turn_state = v_turn_state::public.sport_waitlist_turn_state,
                waitlist_turn_updated_at = null,
                promoted_after_withdrawal_at = null,
                promoted_from_participant_id = null,
                updated_at = now()
            where id = current_setting('test.waitlist_space_candidate')::uuid;

            update public.match_sport_participants
            set availability_status = 'absent',
                convocation_status = 'not_applicable',
                convocation_manual_override = false,
                waitlist_turn_should_consume = false,
                waitlist_turn_state = 'not_applicable',
                waitlist_turn_updated_at = null,
                promoted_after_withdrawal_at = null,
                promoted_from_participant_id = null,
                updated_at = now()
            where id = current_setting('test.waitlist_space_witness')::uuid;

            begin
              v_returned_player := private.handle_convoked_withdrawal(
                current_setting('test.waitlist_space_match')::uuid,
                current_setting('test.waitlist_space_withdrawn')::uuid,
                'a5100000-0000-0000-0000-000000000001',
                'staff'
              );
            exception when others then
              v_sqlstate := sqlstate;
              v_message := sqlerrm;
            end;

            v_expected_promotion :=
              v_convocation_state = 'published'
              and v_withdrawn_status = 'convoked';
            v_expected_candidate_status := case
              when v_expected_promotion then 'convoked'
              else 'not_convoked'
            end;
            v_expected_candidate_should := case
              when not v_expected_promotion then v_should_consume
              when v_cutoff_mode = 'past' then v_should_consume
              else false
            end;
            v_expected_candidate_turn := case
              when not v_expected_promotion then v_turn_state
              when v_cutoff_mode <> 'past' then 'waived'
              when v_turn_state = 'pending' and v_should_consume then 'consumed'
              else v_turn_state
            end;
            v_expected_candidate_position := case
              when v_expected_promotion
                and v_cutoff_mode = 'past'
                and v_turn_state = 'pending'
                and v_should_consume then 3
              else 1
            end;
            v_expected_withdrawn_status := case
              when v_expected_promotion then 'not_applicable'
              else v_withdrawn_status
            end;

            select participant.convocation_status::text,
              participant.waitlist_turn_should_consume,
              participant.waitlist_turn_state::text,
              waitlist.position
            into v_observed_candidate_status,
              v_observed_candidate_should,
              v_observed_candidate_turn,
              v_observed_candidate_position
            from public.match_sport_participants participant
            join public.sport_waitlist_entries waitlist
              on waitlist.season_player_id = participant.season_player_id
            where participant.id = current_setting('test.waitlist_space_candidate')::uuid;

            select participant.convocation_status::text
            into v_observed_withdrawn_status
            from public.match_sport_participants participant
            where participant.id = current_setting('test.waitlist_space_withdrawn')::uuid;

            v_mismatch :=
              v_sqlstate is not null
              or (v_returned_player is not null) is distinct from v_expected_promotion
              or (
                v_expected_promotion
                and v_returned_player is distinct from
                  'a5400000-0000-0000-0000-000000000002'::uuid
              )
              or v_observed_candidate_status is distinct from v_expected_candidate_status
              or v_observed_candidate_should is distinct from v_expected_candidate_should
              or v_observed_candidate_turn is distinct from v_expected_candidate_turn
              or v_observed_candidate_position is distinct from v_expected_candidate_position
              or v_observed_withdrawn_status is distinct from v_expected_withdrawn_status
              or (
                v_expected_promotion
                and not exists (
                  select 1
                  from public.match_sport_participants participant
                  where participant.id = current_setting('test.waitlist_space_candidate')::uuid
                    and participant.convocation_manual_override
                    and participant.promoted_after_withdrawal_at is not null
                    and participant.promoted_from_participant_id =
                      current_setting('test.waitlist_space_withdrawn')::uuid
                )
              );

            insert into pg_temp.waitlist_withdrawal_state_space values (
              v_case,
              v_cutoff_mode,
              v_convocation_state,
              v_withdrawn_status,
              v_should_consume,
              v_turn_state,
              v_expected_promotion,
              v_returned_player is not null,
              v_expected_candidate_status,
              v_observed_candidate_status,
              v_expected_candidate_should,
              v_observed_candidate_should,
              v_expected_candidate_turn,
              v_observed_candidate_turn,
              v_expected_candidate_position,
              v_observed_candidate_position,
              v_expected_withdrawn_status,
              v_observed_withdrawn_status,
              v_sqlstate,
              v_message,
              v_mismatch
            );
          end loop;
        end loop;
      end loop;
    end loop;
  end loop;
end;
$state_space$;

select diag(format(
  'STATE_SPACE waitlist_withdrawal case=%s cutoff=%s workflow=%s withdrawn=%s should=%s turn=%s expected_promotion=%s observed_promotion=%s expected_candidate=%s/%s/%s/pos%s observed_candidate=%s/%s/%s/pos%s expected_withdrawn=%s observed_withdrawn=%s sqlstate=%s message=%s',
  case_number,
  cutoff_mode,
  convocation_state,
  withdrawn_status,
  initial_should_consume,
  initial_turn_state,
  expected_promotion,
  observed_promotion,
  expected_candidate_status,
  expected_candidate_should_consume,
  expected_candidate_turn_state,
  expected_candidate_position,
  observed_candidate_status,
  observed_candidate_should_consume,
  observed_candidate_turn_state,
  observed_candidate_position,
  expected_withdrawn_status,
  observed_withdrawn_status,
  coalesce(observed_sqlstate, '-'),
  coalesce(observed_message, '-')
))
from pg_temp.waitlist_withdrawal_state_space
order by case_number;

select is(
  (select count(*) from pg_temp.waitlist_withdrawal_state_space),
  216::bigint,
  '216 retraits combinatoires sont exécutés'
);
select is(
  (
    select count(*)
    from pg_temp.waitlist_withdrawal_state_space
    where expected_promotion
  ),
  24::bigint,
  '24 scénarios publient et promeuvent un remplaçant'
);
select is(
  (
    select count(*)
    from pg_temp.waitlist_withdrawal_state_space
    where expected_candidate_turn_state = 'consumed'
      and initial_turn_state = 'pending'
  ),
  1::bigint,
  'un seul scénario consomme immédiatement le tour pendant un retrait tardif'
);
select is(
  (
    select count(*)
    from pg_temp.waitlist_withdrawal_state_space
    where mismatch
  ),
  0::bigint,
  'tous les retraits suivent le contrat de promotion et de rotation'
);
select is(
  (
    select count(*)
    from public.match_sport_participant_events event
    where event.match_id = current_setting('test.waitlist_space_match')::uuid
      and event.event_type = 'convoked_player_withdrew'
  ),
  24::bigint,
  'chaque promotion journalise le retrait du convoqué'
);
select is(
  (
    select count(*)
    from public.match_sport_participant_events event
    where event.match_id = current_setting('test.waitlist_space_match')::uuid
      and event.event_type = 'waitlisted_player_promoted'
  ),
  24::bigint,
  'chaque promotion journalise le remplaçant choisi'
);
select is(
  (
    select count(*)
    from public.match_sport_participant_events event
    where event.match_id = current_setting('test.waitlist_space_match')::uuid
      and event.event_type = 'waitlist_turn_consumed'
  ),
  1::bigint,
  'seul le tour tardif pending et consommable est déplacé en fin de liste'
);

-- Sans remplaçant disponible, le désistement reste enregistré mais aucune
-- promotion artificielle n'est créée.
update public.match_sport_workflows
set convocation_state = 'published',
    late_withdrawal_cutoff_at = now() + interval '1 hour'
where match_id = current_setting('test.waitlist_space_match')::uuid;
update public.match_sport_participants
set availability_status = 'available',
    convocation_status = 'convoked'
where id = current_setting('test.waitlist_space_withdrawn')::uuid;
update public.match_sport_participants
set availability_status = 'absent',
    convocation_status = 'not_applicable'
where id in (
  current_setting('test.waitlist_space_candidate')::uuid,
  current_setting('test.waitlist_space_witness')::uuid
);
select is(
  private.handle_convoked_withdrawal(
    current_setting('test.waitlist_space_match')::uuid,
    current_setting('test.waitlist_space_withdrawn')::uuid,
    'a5100000-0000-0000-0000-000000000001',
    'staff'
  ),
  null::uuid,
  'un désistement sans remplaçant ne retourne aucune promotion'
);
select is(
  (
    select convocation_status::text
    from public.match_sport_participants
    where id = current_setting('test.waitlist_space_withdrawn')::uuid
  ),
  'not_applicable',
  'le convoqué désisté est retiré même sans remplaçant disponible'
);

select * from finish();
rollback;
