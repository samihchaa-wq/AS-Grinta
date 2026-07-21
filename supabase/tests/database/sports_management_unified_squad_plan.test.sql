begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select is(
  (
    select count(*)
    from unnest(array[
      'public.admin_save_match_squad_plan(uuid,text,jsonb,text)',
      'public.admin_publish_match_squad_plan(uuid,text,jsonb,text)'
    ]::text[]) expected(signature)
    join pg_proc procedure on procedure.oid = to_regprocedure(expected.signature)
    where procedure.prosecdef
  ),
  0::bigint,
  'les RPC publiques du plan unifié restent SECURITY INVOKER'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_save_match_squad_plan(uuid,text,jsonb,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.admin_save_match_squad_plan(uuid,text,jsonb,text)',
    'EXECUTE'
  ),
  'le plan unifié est réservé aux utilisateurs authentifiés'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'a1000000-0000-0000-0000-000000000001',
    'squad-plan-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Plan"}'::jsonb
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    'squad-plan-player@example.invalid',
    '{"first_name":"Joueur","last_name":"Plan"}'::jsonb
  );

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
values ('a2000000-0000-0000-0000-000000000001', '2100-2101', 'open');

insert into public.opponents(id, name)
values ('a3000000-0000-0000-0000-000000000001', 'Plan Unifié FC');

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position,
  profile_id
)
select
  md5('unified-squad-player-' || number)::uuid,
  'a2000000-0000-0000-0000-000000000001'::uuid,
  'Joueur ' || number,
  'Plan',
  number = 1,
  true,
  number,
  'a1000000-0000-0000-0000-000000000001'::uuid
from generate_series(1, 4) number;

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
set local role authenticated;

select set_config(
  'test.unified_squad_match',
  public.create_match_with_odds_and_sport_limit(
    'a2000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile',
    2.10,
    3.20,
    2.90,
    2
  )::text,
  true
);

reset role;

with ranked as (
  select participant.id,
    row_number() over (order by player.position, participant.id) as number
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  where participant.match_id = current_setting('test.unified_squad_match')::uuid
)
update public.match_sport_participants participant
set availability_status = case when ranked.number <= 3 then 'available' else 'absent' end,
    availability_updated_at = now(),
    availability_updated_by = 'a1000000-0000-0000-0000-000000000001',
    updated_at = now()
from ranked
where participant.id = ranked.id;

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.admin_recompute_match_convocations(
  current_setting('test.unified_squad_match')::uuid,
  false
);

create or replace function pg_temp.unified_squad_payload()
returns jsonb
language sql
stable
as $function$
  with ranked as (
    select participant.id,
      row_number() over (order by player.position, participant.id) as number
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    where participant.match_id = current_setting('test.unified_squad_match')::uuid
  )
  select jsonb_agg(
    jsonb_build_object(
      'participant_id', id,
      'zone', case
        when number = 1 then 'field'
        when number = 2 then 'bench'
        else 'not_selected'
      end,
      'x', case when number = 1 then 0.50 else null end,
      'y', case when number = 1 then 0.90 else null end,
      'slot_label', case when number = 1 then 'GK' else null end,
      'sort_order', number
    ) order by number
  )
  from ranked;
$function$;

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_save_match_squad_plan(
    current_setting('test.unified_squad_match')::uuid,
    '4-3-3',
    pg_temp.unified_squad_payload(),
    'Tentative joueur'
  )$$,
  '42501',
  'Active administrator role required',
  'un joueur ne peut pas enregistrer le plan de sélection'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_save_match_squad_plan(
    current_setting('test.unified_squad_match')::uuid,
    '4-3-3',
    pg_temp.unified_squad_payload(),
    'Brouillon unifié'
  ) #>> '{field_count}',
  '1',
  'le brouillon unifié enregistre le terrain et le banc'
);

select is(
  (
    select count(*)
    from public.match_sport_participants
    where match_id = current_setting('test.unified_squad_match')::uuid
      and availability_status = 'available'
      and convocation_status = 'convoked'
  ),
  2::bigint,
  'les deux joueurs placés sont sélectionnés'
);

select is(
  (
    select count(*)
    from public.match_sport_participants
    where match_id = current_setting('test.unified_squad_match')::uuid
      and availability_status = 'available'
      and convocation_status = 'not_convoked'
      and waitlist_turn_should_consume
  ),
  1::bigint,
  'le joueur présent laissé hors groupe consomme son tour'
);

select is(
  (
    select count(*)
    from public.match_sport_participants
    where match_id = current_setting('test.unified_squad_match')::uuid
      and availability_status = 'absent'
      and convocation_status = 'not_applicable'
      and selection_status = 'not_selected'
  ),
  1::bigint,
  'le joueur absent reste automatiquement hors groupe'
);

select is(
  public.admin_publish_match_squad_plan(
    current_setting('test.unified_squad_match')::uuid,
    '4-3-3',
    pg_temp.unified_squad_payload(),
    'Publication unifiée'
  ) #>> '{version}',
  '1',
  'la publication unifiée crée la première composition publique'
);

select is(
  (
    select convocation_state::text || '/' || composition_state::text
    from public.match_sport_workflows
    where match_id = current_setting('test.unified_squad_match')::uuid
  ),
  'published/published',
  'la sélection et la composition sont publiées ensemble'
);

reset role;
select * from finish();
rollback;
