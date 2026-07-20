begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('public.match_sport_finalizations') is not null
  and to_regclass('public.match_sport_finalization_versions') is not null,
  'les tables de validation finale existent'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'match_sport_participants'
      and column_name = 'final_goals'
  )
  and exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'match_sport_participants'
      and column_name = 'final_selection_status'
  ),
  'les participants portent leur présence, rôle et statistiques réels'
);

select is(
  (
    select count(*)
    from unnest(array[
      'public.admin_get_match_sport_finalization(uuid)',
      'public.admin_finalize_match_sport_postgame(uuid,integer,integer,jsonb,text)',
      'public.get_match_sport_result(uuid)'
    ]::text[]) expected(signature)
    join pg_proc procedure on procedure.oid = to_regprocedure(expected.signature)
    where procedure.prosecdef
  ),
  0::bigint,
  'les RPC publiques restent SECURITY INVOKER'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_finalize_match_sport_postgame(uuid,integer,integer,jsonb,text)',
    'EXECUTE'
  )
  and not has_table_privilege(
    'authenticated', 'public.match_sport_finalizations', 'SELECT'
  ),
  'aucun accès anonyme ou écriture directe n’est exposé'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'b1000000-0000-0000-0000-000000000001',
    'final-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Final"}'::jsonb
  ),
  (
    'b1000000-0000-0000-0000-000000000002',
    'final-player@example.invalid',
    '{"first_name":"Joueur","last_name":"Final"}'::jsonb
  ),
  (
    'b1000000-0000-0000-0000-000000000003',
    'final-keeper@example.invalid',
    '{"first_name":"Gardien","last_name":"Final"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'b1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'b1000000-0000-0000-0000-000000000001',
  'b1000000-0000-0000-0000-000000000002',
  'b1000000-0000-0000-0000-000000000003'
);

insert into public.seasons(id, name, status)
values ('b2000000-0000-0000-0000-000000000001', '2096-2097', 'open');

insert into public.opponents(id, name)
values ('b3000000-0000-0000-0000-000000000001', 'Statistiques FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  (
    'b4000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000001',
    'Buteur', 'Permanent', false, true, 1,
    'b1000000-0000-0000-0000-000000000002'
  ),
  (
    'b4000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000001',
    'Remplaçant', 'Permanent', false, true, 2,
    'b1000000-0000-0000-0000-000000000001'
  ),
  (
    'b4000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000001',
    'Gardien', 'Permanent', true, true, 3,
    'b1000000-0000-0000-0000-000000000003'
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
  'test.final_match',
  public.create_match_with_odds_and_sport_limit(
    'b2000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    ((now() + interval '2 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '2 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 14
  )::text,
  true
);

select set_config(
  'test.final_guest_result',
  public.admin_add_or_reuse_match_guest(
    current_setting('test.final_match')::uuid,
    null,
    'Renfort',
    'Invité',
    false,
    'Test statistiques invité'
  )::text,
  true
);

reset role;

update public.matches
set kickoff_at = now() - interval '2 hours',
    match_date = (now() at time zone 'Europe/Paris')::date,
    match_time = ((now() - interval '2 hours') at time zone 'Europe/Paris')::time
where id = current_setting('test.final_match')::uuid;

update public.match_sport_workflows
set availability_state = 'closed'
where match_id = current_setting('test.final_match')::uuid;

update public.match_sport_participants participant
set selection_status = case
      when participant.season_player_id in (
        'b4000000-0000-0000-0000-000000000001',
        'b4000000-0000-0000-0000-000000000003'
      ) then 'starter'::public.sport_selection_status
      else 'substitute'::public.sport_selection_status
    end,
    convocation_status = 'convoked',
    availability_status = case
      when participant.guest_player_id is not null
        then 'not_applicable'::public.sport_availability_status
      else 'available'::public.sport_availability_status
    end
where participant.match_id = current_setting('test.final_match')::uuid;

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_get_match_sport_finalization(
    current_setting('test.final_match')::uuid
  )$$,
  '42501',
  'Active administrator role required',
  'un joueur ne peut pas lire la saisie administrative'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(
    public.admin_get_match_sport_finalization(
      current_setting('test.final_match')::uuid
    ) -> 'participants'
  ),
  4,
  'la saisie contient les trois permanents et l’invité'
);

create or replace function pg_temp.final_payload(p_correction boolean default false)
returns jsonb
language sql
stable
as $function$
  select jsonb_agg(
    jsonb_build_object(
      'participant_id', participant.id,
      'present', case
        when participant.season_player_id = 'b4000000-0000-0000-0000-000000000002'
          then p_correction
        else true
      end,
      'final_selection_status', case
        when participant.season_player_id in (
          'b4000000-0000-0000-0000-000000000001',
          'b4000000-0000-0000-0000-000000000003'
        ) then 'starter'
        when participant.season_player_id = 'b4000000-0000-0000-0000-000000000002'
          and not p_correction then 'not_selected'
        else 'substitute'
      end,
      'goals', case
        when participant.season_player_id = 'b4000000-0000-0000-0000-000000000001'
          then case when p_correction then 2 else 1 end
        when participant.guest_player_id is not null
          then case when p_correction then 0 else 1 end
        else 0
      end,
      'clean_sheet',
        not p_correction
        and participant.season_player_id = 'b4000000-0000-0000-0000-000000000003'
    ) order by participant.id
  )
  from public.match_sport_participants participant
  where participant.match_id = current_setting('test.final_match')::uuid
    and participant.is_eligible;
$function$;

select is(
  public.admin_finalize_match_sport_postgame(
    current_setting('test.final_match')::uuid,
    2,
    0,
    pg_temp.final_payload(false),
    'Validation initiale'
  ) #>> '{version}',
  '1',
  'la première validation crée la version 1'
);

select is(
  (
    select status::text from public.matches
    where id = current_setting('test.final_match')::uuid
  ),
  'termine',
  'le match passe à terminé'
);

select is(
  (
    select presence_state::text from public.match_sport_workflows
    where match_id = current_setting('test.final_match')::uuid
  ),
  'confirmed',
  'la présence finale devient la source confirmée'
);

select is(
  (
    select count(*) from public.match_attendance
    where match_id = current_setting('test.final_match')::uuid
  ),
  2::bigint,
  'seuls les permanents présents alimentent la table historique de présence'
);

select is(
  (
    select goals from public.match_player_stats
    where match_id = current_setting('test.final_match')::uuid
      and season_player_id = 'b4000000-0000-0000-0000-000000000001'
  ),
  1,
  'le but permanent alimente immédiatement les statistiques existantes'
);

select ok(
  exists (
    select 1 from public.match_player_stats
    where match_id = current_setting('test.final_match')::uuid
      and season_player_id = 'b4000000-0000-0000-0000-000000000003'
      and clean_sheet
  ),
  'le clean sheet permanent alimente les statistiques existantes'
);

select is(
  (
    select final_goals
    from public.match_sport_participants
    where match_id = current_setting('test.final_match')::uuid
      and guest_player_id is not null
  ),
  1::smallint,
  'le but invité reste lié au même résultat validé'
);

select is(
  public.admin_finalize_match_sport_postgame(
    current_setting('test.final_match')::uuid,
    2,
    1,
    pg_temp.final_payload(true),
    'Correction du rapport de match'
  ) #>> '{version}',
  '2',
  'une correction crée la version 2'
);

select is(
  (
    select count(*) from public.match_attendance
    where match_id = current_setting('test.final_match')::uuid
  ),
  3::bigint,
  'la correction remplace proprement les présences sans doublon'
);

select is(
  (
    select goals from public.match_player_stats
    where match_id = current_setting('test.final_match')::uuid
      and season_player_id = 'b4000000-0000-0000-0000-000000000001'
  ),
  2,
  'les statistiques du buteur sont recalculées par la correction'
);

select is(
  (
    select count(*) from public.match_player_stats
    where match_id = current_setting('test.final_match')::uuid
      and clean_sheet
  ),
  0::bigint,
  'l’ancien clean sheet est supprimé par la correction'
);

select is(
  (
    select final_goals
    from public.match_sport_participants
    where match_id = current_setting('test.final_match')::uuid
      and guest_player_id is not null
  ),
  0::smallint,
  'l’ancienne statistique invité est également remplacée'
);

reset role;
select is(
  (
    select count(*) from public.match_sport_finalization_versions
    where match_id = current_setting('test.final_match')::uuid
  ),
  2::bigint,
  'les deux versions restent immuables dans l’historique'
);

select ok(
  exists (
    select 1 from private.sport_admin_audit_log
    where match_id = current_setting('test.final_match')::uuid
      and action = 'correct_final_attendance'
      and reason = 'Correction du rapport de match'
  ),
  'la correction est auditée avec son motif'
);

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = 'b1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.get_match_sport_result(
    current_setting('test.final_match')::uuid
  )$$,
  '42501',
  'Sports-management module is disabled',
  'le résultat sportif disparaît derrière le feature flag'
);

reset role;
select * from finish();
rollback;
