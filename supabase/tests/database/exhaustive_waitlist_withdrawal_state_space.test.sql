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

-- Chaque désistement recalcule les convocations : les X présents aux
-- positions les plus basses de la liste d'attente, sauf les joueurs que
-- l'admin a placés à la main dans « Effectif » (choix conservé). Le joueur
-- qui se désiste quitte toujours l'effectif.
create temporary table pg_temp.waitlist_three_rules_state_space (
  case_number integer primary key,
  cutoff_mode text not null,
  previous_status text not null,
  candidate_availability text not null,
  manual_override boolean not null,
  quota integer not null,
  old_turn_state text not null,
  actual_candidate text,
  expected_candidate text,
  actual_convoked integer,
  expected_convoked integer,
  sqlstate text,
  mismatch boolean not null
) on commit drop;

do $state_space$
declare
  v_case integer := 0;
  v_cutoff text;
  v_previous text;
  v_candidate text;
  v_manual boolean;
  v_quota integer;
  v_old_turn text;
  v_error text;
  v_actual text;
  v_expected text;
  v_candidate_manual boolean;
  v_candidate_should boolean;
  v_withdrawn text;
  v_witness text;
  v_convoked integer;
  v_expected_convoked integer;
begin
  foreach v_cutoff in array array['none', 'future', 'past'] loop
    foreach v_previous in array array[
      'convoked', 'not_convoked', 'not_applicable'
    ] loop
      foreach v_candidate in array array[
        'available', 'absent', 'no_response'
      ] loop
        foreach v_manual in array array[false, true] loop
          foreach v_quota in array array[1, 2] loop
            foreach v_old_turn in array array['pending', 'consumed'] loop
              v_case := v_case + 1;
              v_error := null;

              update public.match_sport_workflows
              set convocation_state = 'published',
                  squad_size_limit = v_quota,
                  late_withdrawal_cutoff_at = case v_cutoff
                    when 'none' then null
                    when 'future' then now() + interval '1 hour'
                    else now() - interval '1 hour' end
              where match_id = current_setting('test.waitlist_space_match')::uuid;

              -- Celui qui se désiste est absent, quel que soit son ancien statut.
              update public.match_sport_participants
              set availability_status = 'absent',
                  convocation_status = v_previous::public.sport_convocation_status,
                  convocation_manual_override = v_manual,
                  waitlist_turn_state = 'not_applicable',
                  waitlist_turn_should_consume = false
              where id = current_setting('test.waitlist_space_withdrawn')::uuid;

              update public.match_sport_participants
              set availability_status = v_candidate::public.sport_availability_status
              where id = current_setting('test.waitlist_space_candidate')::uuid;
              update public.match_sport_participants
              set convocation_status = 'not_convoked',
                  convocation_manual_override = v_manual,
                  waitlist_turn_state = v_old_turn::public.sport_waitlist_turn_state,
                  waitlist_turn_should_consume = true
              where id = current_setting('test.waitlist_space_candidate')::uuid;

              update public.match_sport_participants
              set availability_status = 'available',
                  convocation_status = 'not_convoked',
                  convocation_manual_override = false,
                  waitlist_turn_state = 'pending',
                  waitlist_turn_should_consume = true
              where id = current_setting('test.waitlist_space_witness')::uuid;

              begin
                perform private.handle_convoked_withdrawal(
                  current_setting('test.waitlist_space_match')::uuid,
                  current_setting('test.waitlist_space_withdrawn')::uuid,
                  'a5100000-0000-0000-0000-000000000001', 'staff'
                );
              exception when others then
                v_error := sqlstate;
              end;

              select p.convocation_status::text, p.convocation_manual_override,
                     p.waitlist_turn_should_consume
                into v_actual, v_candidate_manual, v_candidate_should
              from public.match_sport_participants p
              where p.id = current_setting('test.waitlist_space_candidate')::uuid;

              select p.convocation_status::text into v_withdrawn
              from public.match_sport_participants p
              where p.id = current_setting('test.waitlist_space_withdrawn')::uuid;

              select p.convocation_status::text into v_witness
              from public.match_sport_participants p
              where p.id = current_setting('test.waitlist_space_witness')::uuid;

              select count(*)::integer into v_convoked
              from public.match_sport_participants p
              where p.match_id = current_setting('test.waitlist_space_match')::uuid
                and p.is_eligible
                and p.convocation_status = 'convoked'
                and p.availability_status = 'available';

              -- Un joueur que l'admin a placé en attente le reste, même
              -- absent ou sans réponse ; il ne compte un tour que présent.
              v_expected := case
                when v_manual then 'not_convoked'
                when v_candidate <> 'available' then 'not_applicable'
                when v_quota = 1 then 'not_convoked'
                else 'convoked' end;
              v_expected_convoked := case
                when v_candidate = 'available' and not v_manual then v_quota
                else 1 end;

              insert into pg_temp.waitlist_three_rules_state_space
              values (
                v_case, v_cutoff, v_previous, v_candidate, v_manual,
                v_quota, v_old_turn, v_actual, v_expected,
                v_convoked, v_expected_convoked, v_error,
                v_error is not null
                or v_actual is distinct from v_expected
                or v_convoked is distinct from v_expected_convoked
                or v_withdrawn is distinct from 'not_applicable'
                or v_witness is distinct from 'convoked'
                or v_candidate_manual is distinct from v_manual
                or v_candidate_should is distinct from
                   (v_candidate = 'available' and (v_manual or v_quota = 1))
              );
            end loop;
          end loop;
        end loop;
      end loop;
    end loop;
  end loop;
end;
$state_space$;

select is(
  (select count(*) from pg_temp.waitlist_three_rules_state_space),
  216::bigint,
  '216 désistements combinatoires sont exécutés'
);
select diag(format(
  'cas=%s cutoff=%s initial=%s disponibilité=%s manuel=%s quota=%s tour=%s attendu=%s/%s obtenu=%s/%s sqlstate=%s',
  case_number, cutoff_mode, previous_status, candidate_availability,
  manual_override, quota, old_turn_state,
  expected_candidate, expected_convoked,
  actual_candidate, actual_convoked, coalesce(sqlstate,'-')
))
from pg_temp.waitlist_three_rules_state_space where mismatch
order by case_number;
select is(
  (select count(*) from pg_temp.waitlist_three_rules_state_space where mismatch),
  0::bigint,
  'les 216 combinaisons respectent le calcul et les choix manuels de l admin'
);
select is(
  (
    select count(*)::integer
    from public.match_sport_participant_events ev
    where ev.match_id = current_setting('test.waitlist_space_match')::uuid
      and ev.event_type = 'waitlist_turn_consumed'
  ), 0,
  'aucun +1 n est comptabilisé avant le coup d envoi'
);

-- Quand tous les joueurs se désistent, personne ne reçoit une place.
update public.match_sport_participants
set availability_status = 'absent'
where match_id = current_setting('test.waitlist_space_match')::uuid;
select private.recompute_match_convocations_internal(
  current_setting('test.waitlist_space_match')::uuid, false
);
select is(
  (
    select count(*)::integer
    from public.match_sport_participants p
    where p.match_id = current_setting('test.waitlist_space_match')::uuid
      and p.convocation_status = 'convoked'
  ), 0,
  'aucune convocation lorsque personne ne se déclare présent'
);

select * from finish();
rollback;
