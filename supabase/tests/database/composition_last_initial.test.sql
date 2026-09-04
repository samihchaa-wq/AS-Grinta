begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Sans photo de profil, l'application affiche des initiales. Le nom
-- d'affichage n'est qu'un prénom ou un surnom : deux joueurs prénommés Julien
-- auraient donc la même pastille. Les compositions envoient « last_initial »,
-- l'initiale du nom de famille, pour les départager.

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'd1000000-0000-0000-0000-000000000001',
    'initiale-admin@example.invalid',
    '{"first_name":"Admin"}'::jsonb
  ),
  (
    'd1000000-0000-0000-0000-000000000002',
    'initiale-cesar@example.invalid',
    '{"first_name":"Julien"}'::jsonb
  ),
  (
    'd1000000-0000-0000-0000-000000000003',
    'initiale-durand@example.invalid',
    '{"first_name":"Julien"}'::jsonb
  ),
  (
    'd1000000-0000-0000-0000-000000000004',
    'initiale-surnom@example.invalid',
    '{"first_name":"Milan"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'd1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    surnom = case
      when id = 'd1000000-0000-0000-0000-000000000004' then 'Pipo'
      else surnom
    end,
    updated_at = now()
where id between
  'd1000000-0000-0000-0000-000000000001'
  and 'd1000000-0000-0000-0000-000000000004';

insert into public.seasons(id, name, status)
values ('d2000000-0000-0000-0000-000000000001', '2301-2302', 'open');

insert into public.opponents(id, name)
values ('d3000000-0000-0000-0000-000000000001', 'Initiale FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  (
    'd4000000-0000-0000-0000-000000000001',
    'd2000000-0000-0000-0000-000000000001',
    'Julien', 'Cesar', false, true, 1,
    'd1000000-0000-0000-0000-000000000002'
  ),
  (
    'd4000000-0000-0000-0000-000000000002',
    'd2000000-0000-0000-0000-000000000001',
    'Julien', 'Durand', false, true, 2,
    'd1000000-0000-0000-0000-000000000003'
  ),
  (
    'd4000000-0000-0000-0000-000000000003',
    'd2000000-0000-0000-0000-000000000001',
    'Milan', 'Couzin', false, true, 3,
    'd1000000-0000-0000-0000-000000000004'
  ),
  (
    'd4000000-0000-0000-0000-000000000004',
    'd2000000-0000-0000-0000-000000000001',
    'Philippe', '', false, true, 4,
    null
  );

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
  'test.initiale_match',
  public.create_match_with_odds_and_sport_limit(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 4
  )::text,
  true
);

reset role;

create or replace function pg_temp.lineup_field(
  p_season_player uuid,
  p_key text
)
returns text
language sql
stable
as $function$
  select entry ->> p_key
  from jsonb_array_elements(
    private.match_sport_report_lineup(
      current_setting('test.initiale_match')::uuid
    ) -> 'entries'
  ) entry
  where entry ->> 'season_player_id' = p_season_player::text;
$function$;

select is(
  pg_temp.lineup_field('d4000000-0000-0000-0000-000000000001', 'display_name'),
  'Julien',
  'le nom affiché reste le prénom'
);

select is(
  pg_temp.lineup_field('d4000000-0000-0000-0000-000000000001', 'last_initial'),
  'C',
  'le premier Julien porte l’initiale de son nom'
);

select is(
  pg_temp.lineup_field('d4000000-0000-0000-0000-000000000002', 'last_initial'),
  'D',
  'le second Julien porte une initiale différente'
);

select is(
  pg_temp.lineup_field('d4000000-0000-0000-0000-000000000003', 'display_name'),
  'Pipo',
  'un joueur affiché sous son surnom garde son surnom'
);

select is(
  pg_temp.lineup_field('d4000000-0000-0000-0000-000000000003', 'last_initial'),
  'C',
  'le surnom n’empêche pas l’initiale du nom de famille'
);

select is(
  pg_temp.lineup_field('d4000000-0000-0000-0000-000000000004', 'last_initial'),
  null,
  'sans nom de famille connu, aucune initiale n’est inventée'
);

-- Toutes les compositions envoyées à l'application portent la clé : sans elle,
-- un écran retomberait sur les deux premières lettres du prénom.
select is(
  (
    select count(*)
    from unnest(array[
      'private.composition_snapshot(uuid)',
      'private.get_published_match_composition(uuid)',
      'private.match_sport_report_lineup(uuid)',
      'private.match_sport_finalization_snapshot(uuid)',
      'private.get_match_live_add_player_options(uuid)',
      'public.get_internal_composition(uuid)'
    ]::text[]) expected(signature)
    join pg_proc procedure on procedure.oid = to_regprocedure(expected.signature)
    where procedure.prosrc like '%last_initial%'
  ),
  6::bigint,
  'chaque fonction de composition expose l’initiale du nom'
);

select * from finish();
rollback;
