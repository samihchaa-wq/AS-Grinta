begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  ('a1000000-0000-0000-0000-000000000001', 'state-space-admin@example.invalid', '{"first_name":"Admin"}'::jsonb),
  ('a1000000-0000-0000-0000-000000000002', 'state-space-player@example.invalid', '{"first_name":"Player"}'::jsonb);

update public.profiles
set role = case
      when id = 'a1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'a1000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000002'
);

insert into public.seasons(id, name, status)
values ('a2000000-0000-0000-0000-000000000001', '2101-2102', 'open');

insert into public.opponents(id, name)
values ('a3000000-0000-0000-0000-000000000001', 'State Space FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
) values (
  'a4000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000001',
  'Player', 'StateSpace', false, true, 1,
  'a1000000-0000-0000-0000-000000000002'
);

insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, kickoff_at,
  location, planned_duration_minutes, status, created_by
) values (
  'a5000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000001',
  'a3000000-0000-0000-0000-000000000001',
  ((now() + interval '2 days') at time zone 'Europe/Paris')::date,
  ((now() + interval '2 days') at time zone 'Europe/Paris')::time,
  now() + interval '2 days',
  'domicile', 90, 'a_venir',
  'a1000000-0000-0000-0000-000000000001'
);

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'a1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
select private.sync_match_sport_workflow(
  'a5000000-0000-0000-0000-000000000001'
);

update public.match_sport_workflows
set availability_state = 'open',
    availability_opens_at = now() - interval '1 hour',
    availability_opened_at = now() - interval '1 hour'
where match_id = 'a5000000-0000-0000-0000-000000000001';

create temporary table pg_temp.availability_state_space (
  actor_kind text not null,
  initial_status text not null,
  target_status text not null,
  reason_kind text not null,
  expected_success boolean not null,
  observed_success boolean not null,
  observed_sqlstate text,
  observed_message text,
  observed_final_status text,
  observed_private_comment text
) on commit drop;

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);

do $state_space$
declare
  v_initial public.sport_availability_status;
  v_target text;
  v_success boolean;
  v_sqlstate text;
  v_message text;
begin
  foreach v_initial in array enum_range(null::public.sport_availability_status)
  loop
    foreach v_target in array array[
      'available', 'absent', 'no_response', 'not_applicable', 'invalid'
    ]
    loop
      update public.match_sport_participants
      set availability_status = v_initial,
          availability_comment_private = null,
          availability_updated_at = null,
          availability_updated_by = null,
          updated_at = now()
      where match_id = 'a5000000-0000-0000-0000-000000000001'
        and season_player_id = 'a4000000-0000-0000-0000-000000000001';

      v_success := true;
      v_sqlstate := null;
      v_message := null;
      begin
        perform private.set_my_match_availability(
          'a5000000-0000-0000-0000-000000000001',
          v_target,
          'raison joueur'
        );
      exception when others then
        v_success := false;
        v_sqlstate := sqlstate;
        v_message := sqlerrm;
      end;

      insert into pg_temp.availability_state_space
      select
        'player', v_initial::text, v_target, 'not_applicable',
        v_target in ('available', 'absent'),
        v_success, v_sqlstate, v_message,
        participant.availability_status::text,
        participant.availability_comment_private
      from public.match_sport_participants participant
      where participant.match_id = 'a5000000-0000-0000-0000-000000000001'
        and participant.season_player_id = 'a4000000-0000-0000-0000-000000000001';
    end loop;
  end loop;
end;
$state_space$;

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);

do $state_space$
declare
  v_initial public.sport_availability_status;
  v_target text;
  v_reason text;
  v_reason_kind text;
  v_success boolean;
  v_sqlstate text;
  v_message text;
begin
  foreach v_initial in array enum_range(null::public.sport_availability_status)
  loop
    foreach v_target in array array[
      'available', 'absent', 'no_response', 'not_applicable', 'invalid'
    ]
    loop
      foreach v_reason in array array[null::text, ''::text, 'motif valide'::text]
      loop
        v_reason_kind := case
          when v_reason is null then 'null'
          when v_reason = '' then 'empty'
          else 'valid'
        end;

        update public.match_sport_participants
        set availability_status = v_initial,
            availability_comment_private = null,
            availability_updated_at = null,
            availability_updated_by = null,
            updated_at = now()
        where match_id = 'a5000000-0000-0000-0000-000000000001'
          and season_player_id = 'a4000000-0000-0000-0000-000000000001';

        v_success := true;
        v_sqlstate := null;
        v_message := null;
        begin
          perform private.override_match_availability(
            'a5000000-0000-0000-0000-000000000001',
            'a4000000-0000-0000-0000-000000000001',
            v_target,
            'raison administrateur',
            v_reason
          );
        exception when others then
          v_success := false;
          v_sqlstate := sqlstate;
          v_message := sqlerrm;
        end;

        insert into pg_temp.availability_state_space
        select
          'admin', v_initial::text, v_target, v_reason_kind,
          v_target in ('available', 'absent', 'no_response')
            and v_reason_kind = 'valid',
          v_success, v_sqlstate, v_message,
          participant.availability_status::text,
          participant.availability_comment_private
        from public.match_sport_participants participant
        where participant.match_id = 'a5000000-0000-0000-0000-000000000001'
          and participant.season_player_id = 'a4000000-0000-0000-0000-000000000001';
      end loop;
    end loop;
  end loop;
end;
$state_space$;

select diag(format(
  'STATE_SPACE availability actor=%s initial=%s target=%s reason=%s expected=%s observed=%s sqlstate=%s final=%s comment=%s message=%s',
  actor_kind, initial_status, target_status, reason_kind,
  expected_success, observed_success, coalesce(observed_sqlstate, '-'),
  coalesce(observed_final_status, '-'),
  coalesce(observed_private_comment, '-'),
  coalesce(observed_message, '-')
))
from pg_temp.availability_state_space
order by actor_kind, initial_status, target_status, reason_kind;

select is(
  (select count(*) from pg_temp.availability_state_space where actor_kind = 'player'),
  20::bigint,
  'les 20 transitions joueur sont exécutées'
);
select is(
  (select count(*) from pg_temp.availability_state_space where actor_kind = 'admin'),
  60::bigint,
  'les 60 transitions administrateur sont exécutées'
);
select is(
  (select count(*) from pg_temp.availability_state_space
   where observed_success is distinct from expected_success),
  0::bigint,
  'toutes les transitions suivent le contrat attendu'
);
select is(
  (select count(*) from pg_temp.availability_state_space
   where not observed_success and observed_sqlstate <> '22023'),
  0::bigint,
  'les entrées invalides utilisent une erreur de validation stable'
);
select is(
  (select count(*) from pg_temp.availability_state_space
   where observed_success and target_status = 'available'
     and observed_private_comment is not null),
  0::bigint,
  'disponible efface toujours le commentaire privé'
);
select is(
  (select count(*) from pg_temp.availability_state_space
   where observed_success and target_status = 'absent'
     and observed_private_comment is null),
  0::bigint,
  'absent conserve toujours le commentaire fourni'
);

-- Frontières : l'administrateur prépare l'état, le joueur tente l'action.
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
update public.match_sport_workflows
set availability_state = 'open', availability_opens_at = now() + interval '1 hour'
where match_id = 'a5000000-0000-0000-0000-000000000001';
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
select throws_ok(
  $$select private.set_my_match_availability(
    'a5000000-0000-0000-0000-000000000001','available',null
  )$$,
  '22023',
  'la réponse avant ouverture est refusée'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
update public.match_sport_workflows
set availability_state = 'closed', availability_opens_at = now() - interval '1 hour'
where match_id = 'a5000000-0000-0000-0000-000000000001';
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
select throws_ok(
  $$select private.set_my_match_availability(
    'a5000000-0000-0000-0000-000000000001','available',null
  )$$,
  '22023',
  'un workflow fermé refuse la réponse'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
update public.match_sport_workflows
set availability_state = 'open', availability_opens_at = now() - interval '1 hour'
where match_id = 'a5000000-0000-0000-0000-000000000001';
update public.matches
set match_date = ((now() - interval '1 minute') at time zone 'Europe/Paris')::date,
    match_time = ((now() - interval '1 minute') at time zone 'Europe/Paris')::time,
    kickoff_at = now() - interval '1 minute'
where id = 'a5000000-0000-0000-0000-000000000001';
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
select throws_ok(
  $$select private.set_my_match_availability(
    'a5000000-0000-0000-0000-000000000001','available',null
  )$$,
  '22023',
  'une réponse après le coup d’envoi est refusée'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
update public.matches
set match_date = ((now() + interval '2 days') at time zone 'Europe/Paris')::date,
    match_time = ((now() + interval '2 days') at time zone 'Europe/Paris')::time,
    kickoff_at = now() + interval '2 days'
where id = 'a5000000-0000-0000-0000-000000000001';
update public.profiles
set status = 'pending'
where id = 'a1000000-0000-0000-0000-000000000002';
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
select throws_ok(
  $$select private.set_my_match_availability(
    'a5000000-0000-0000-0000-000000000001','available',null
  )$$,
  '42501',
  'un profil inactif ne peut pas répondre'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
update public.profiles
set status = 'active'
where id = 'a1000000-0000-0000-0000-000000000002';
update private.app_feature_flags
set enabled = false, updated_at = now()
where key = 'sports_management';
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
select throws_ok(
  $$select private.set_my_match_availability(
    'a5000000-0000-0000-0000-000000000001','available',null
  )$$,
  '42501',
  'le feature flag désactivé refuse toute réponse'
);

select * from finish();
rollback;
