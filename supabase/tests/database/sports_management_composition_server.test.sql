begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('public.match_compositions') is not null
  and to_regclass('public.match_composition_entries') is not null
  and to_regclass('public.match_composition_publications') is not null,
  'les tables de composition existent'
);

select ok(
  (
    select bool_and(relrowsecurity)
    from pg_class
    where oid in (
      'public.match_compositions'::regclass,
      'public.match_composition_entries'::regclass,
      'public.match_composition_publications'::regclass
    )
  ),
  'RLS est activée sur toutes les tables de composition'
);

select ok(
  not has_table_privilege('authenticated', 'public.match_compositions', 'SELECT')
  and not has_table_privilege('authenticated', 'public.match_compositions', 'INSERT')
  and not has_table_privilege('authenticated', 'public.match_composition_entries', 'INSERT')
  and has_table_privilege('authenticated', 'public.match_composition_publications', 'SELECT'),
  'les clients lisent seulement les publications immuables et n’écrivent jamais directement'
);

select is(
  (
    select count(*)
    from unnest(array[
      'public.admin_save_match_composition(uuid,text,jsonb,boolean,text)',
      'public.admin_publish_match_composition(uuid,boolean,text)',
      'public.admin_get_match_composition(uuid)',
      'public.get_published_match_composition(uuid)'
    ]::text[]) expected(signature)
    join pg_proc procedure on procedure.oid = to_regprocedure(expected.signature)
    where procedure.prosecdef
  ),
  0::bigint,
  'les RPC publiques de composition restent SECURITY INVOKER'
);

select ok(
  not has_function_privilege(
    'anon', 'public.admin_save_match_composition(uuid,text,jsonb,boolean,text)', 'EXECUTE'
  )
  and not has_function_privilege(
    'anon', 'public.get_published_match_composition(uuid)', 'EXECUTE'
  ),
  'les RPC de composition ne sont jamais exposées au rôle anonyme'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '91000000-0000-0000-0000-000000000001',
    'composition-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Composition"}'::jsonb
  ),
  (
    '91000000-0000-0000-0000-000000000002',
    'composition-player@example.invalid',
    '{"first_name":"Joueur","last_name":"Composition"}'::jsonb
  );

update public.profiles
set role = case
      when id = '91000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  '91000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000002'
);

insert into public.seasons(id, name, status)
values ('92000000-0000-0000-0000-000000000001', '2098-2099', 'open');

insert into public.opponents(id, name)
values ('93000000-0000-0000-0000-000000000001', 'Composition FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
select
  md5('composition-player-' || number)::uuid,
  '92000000-0000-0000-0000-000000000001'::uuid,
  'Joueur ' || lpad(number::text, 2, '0'),
  'Composition',
  number = 1,
  true,
  number,
  '91000000-0000-0000-0000-000000000001'::uuid
from generate_series(1, 12) number;

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '91000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.composition_match',
  public.create_match_with_odds_and_sport_limit(
    '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 14
  )::text,
  true
);

reset role;

update public.match_sport_participants
set availability_status = 'available',
    availability_updated_at = now(),
    availability_updated_by = '91000000-0000-0000-0000-000000000001',
    convocation_status = 'convoked',
    updated_at = now()
where match_id = current_setting('test.composition_match')::uuid;

create or replace function pg_temp.composition_payload(p_mode text default 'valid')
returns jsonb
language sql
stable
as $function$
  with ranked as (
    select participant.id,
      player.is_goalkeeper,
      row_number() over (order by player.position, participant.id) as number
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    where participant.match_id = current_setting('test.composition_match')::uuid
  ), prepared as (
    select id, is_goalkeeper, number,
      case
        when p_mode = 'twelve_field' then 'field'
        when p_mode = 'unresolved' and number = 12 then 'available'
        when p_mode = 'goalkeeper_bench' and is_goalkeeper then 'bench'
        when p_mode = 'goalkeeper_bench' and number <= 11 then 'field'
        when number <= 11 then 'field'
        else 'bench'
      end as zone
    from ranked
  )
  select jsonb_agg(
    jsonb_build_object(
      'participant_id', id,
      'zone', zone,
      'x', case
        when zone = 'field' then least(0.95, 0.04 + number * 0.075)
        else null
      end,
      'y', case when zone = 'field' then 0.50 else null end,
      'slot_label', case when is_goalkeeper then 'GK' else null end,
      'sort_order', number
    ) order by number
  )
  from prepared;
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_save_match_composition(
    current_setting('test.composition_match')::uuid,
    '4-3-3',
    pg_temp.composition_payload('valid'),
    false,
    'Tentative joueur'
  )$$,
  '42501',
  'Active administrator role required',
  'un joueur ne peut pas enregistrer la composition'
);

select throws_ok(
  $$insert into public.match_compositions(
    match_id, formation_code, last_modified_by
  ) values (
    current_setting('test.composition_match')::uuid,
    '4-4-2',
    '91000000-0000-0000-0000-000000000002'
  )$$,
  '42501',
  null,
  'aucune écriture directe n’est possible'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_save_match_composition(
    current_setting('test.composition_match')::uuid,
    '4-3-3',
    pg_temp.composition_payload('twelve_field'),
    false,
    'Trop de titulaires'
  )$$,
  '22023',
  'A composition cannot contain more than 11 starters',
  'le serveur refuse douze titulaires'
);

select is(
  public.admin_save_match_composition(
    current_setting('test.composition_match')::uuid,
    '4-3-3',
    pg_temp.composition_payload('valid'),
    false,
    'Premier brouillon'
  ) #>> '{field_count}',
  '11',
  'un brouillon complet avec onze titulaires est enregistré'
);

select is(
  (
    select count(*)
    from public.match_sport_participants
    where match_id = current_setting('test.composition_match')::uuid
      and selection_status = 'starter'
  ),
  11::bigint,
  'les décisions Titulaire sont synchronisées atomiquement'
);

select is(
  public.admin_get_match_composition(
    current_setting('test.composition_match')::uuid
  ) #>> '{bench_count}',
  '1',
  'l’administration relit le brouillon normalisé'
);

select is(
  public.admin_publish_match_composition(
    current_setting('test.composition_match')::uuid,
    false,
    'Première publication'
  ) #>> '{version}',
  '1',
  'la première publication crée la version 1'
);

select is(
  (
    select composition_state::text
    from public.match_sport_workflows
    where match_id = current_setting('test.composition_match')::uuid
  ),
  'published',
  'le workflow passe à published'
);

select is(
  (
    select count(*)
    from public.match_composition_publications
    where match_id = current_setting('test.composition_match')::uuid
  ),
  1::bigint,
  'un snapshot immuable est conservé'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.get_published_match_composition(
    current_setting('test.composition_match')::uuid
  ) #>> '{version}',
  '1',
  'un profil actif lit uniquement la publication courante'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_save_match_composition(
    current_setting('test.composition_match')::uuid,
    '4-4-2',
    pg_temp.composition_payload('goalkeeper_bench'),
    false,
    'Gardien sur le banc pour tester l’avertissement'
  ) #>> '{has_unpublished_changes}',
  'true',
  'une modification après publication reste un brouillon non publié'
);

select is(
  (
    select count(*)
    from public.match_composition_publications
    where match_id = current_setting('test.composition_match')::uuid
  ),
  1::bigint,
  'modifier le brouillon ne change jamais le snapshot déjà publié'
);

select is(
  public.admin_publish_match_composition(
    current_setting('test.composition_match')::uuid,
    false,
    'Republication'
  ) #>> '{version}',
  '2',
  'la republication crée une nouvelle version'
);

select is(
  public.admin_get_match_composition(
    current_setting('test.composition_match')::uuid
  ) #>> '{has_goalkeeper_warning}',
  'true',
  'l’absence de gardien titulaire produit un avertissement non bloquant'
);

reset role;
update public.match_sport_workflows
set squad_size_limit = 11
where match_id = current_setting('test.composition_match')::uuid;
set local role authenticated;

select throws_ok(
  $$select public.admin_save_match_composition(
    current_setting('test.composition_match')::uuid,
    '4-3-3',
    pg_temp.composition_payload('valid'),
    false,
    'Limite dépassée'
  )$$,
  '22023',
  'Selected squad exceeds the configured match limit',
  'la limite choisie pour le match reste bloquante par défaut'
);

select is(
  public.admin_save_match_composition(
    current_setting('test.composition_match')::uuid,
    '4-3-3',
    pg_temp.composition_payload('valid'),
    true,
    'Exception de douzième joueur autorisée'
  ) #>> '{squad_size_exception_approved}',
  'true',
  'une exception explicite autorise le dépassement de la limite'
);

reset role;
select ok(
  exists (
    select 1
    from private.sport_admin_audit_log
    where match_id = current_setting('test.composition_match')::uuid
      and action = 'save_composition_exception'
      and reason = 'Exception de douzième joueur autorisée'
  ),
  'l’exception est auditée avec son motif'
);
set local role authenticated;

reset role;
update public.match_sport_workflows
set squad_size_limit = 14
where match_id = current_setting('test.composition_match')::uuid;
set local role authenticated;

select public.admin_save_match_composition(
  current_setting('test.composition_match')::uuid,
  '4-3-3',
  pg_temp.composition_payload('unresolved'),
  false,
  'Brouillon volontairement incomplet'
);

select throws_ok(
  $$select public.admin_publish_match_composition(
    current_setting('test.composition_match')::uuid,
    false,
    'Publication incomplète'
  )$$,
  '22023',
  'Every convoked player must be placed on the field or bench before publication',
  'un joueur convoqué non placé bloque la publication'
);

reset role;
update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = '91000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.get_published_match_composition(
    current_setting('test.composition_match')::uuid
  )$$,
  '42501',
  'Sports-management module is disabled',
  'le flag désactivé bloque la lecture RPC des compositions'
);

select is(
  (
    select count(*)
    from public.match_composition_publications
    where match_id = current_setting('test.composition_match')::uuid
  ),
  0::bigint,
  'RLS masque aussi directement les publications lorsque le flag est désactivé'
);

reset role;
select * from finish();
rollback;
