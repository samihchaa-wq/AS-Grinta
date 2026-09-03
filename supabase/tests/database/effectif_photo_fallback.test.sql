begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- L'effectif administrateur affiche l'avatar du joueur. La photo peut être
-- portée par le profil du joueur (il l'a envoyée lui-même) ou par sa ligne
-- d'effectif (un admin l'a envoyée pour lui depuis la gestion d'effectif).
-- Les deux doivent remonter, sinon le joueur reste bloqué sur ses initiales.

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'c1000000-0000-0000-0000-000000000001',
    'photo-admin@example.invalid',
    '{"first_name":"Admin"}'::jsonb
  ),
  (
    'c1000000-0000-0000-0000-000000000002',
    'photo-profil@example.invalid',
    '{"first_name":"Prisca"}'::jsonb
  ),
  (
    'c1000000-0000-0000-0000-000000000003',
    'photo-effectif@example.invalid',
    '{"first_name":"Eliot"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'c1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    photo_url = case
      when id = 'c1000000-0000-0000-0000-000000000002'
        then 'c1000000-0000-0000-0000-000000000002/avatar_1.jpg'
      else null
    end,
    updated_at = now()
where id between
  'c1000000-0000-0000-0000-000000000001'
  and 'c1000000-0000-0000-0000-000000000003';

insert into public.seasons(id, name, status)
values ('c2000000-0000-0000-0000-000000000001', '2201-2202', 'open');

insert into public.opponents(id, name)
values ('c3000000-0000-0000-0000-000000000001', 'Photo FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id, photo_url
)
values
  (
    'c4000000-0000-0000-0000-000000000001',
    'c2000000-0000-0000-0000-000000000001',
    'Prisca', 'Photo', false, true, 1,
    'c1000000-0000-0000-0000-000000000002',
    null
  ),
  (
    'c4000000-0000-0000-0000-000000000002',
    'c2000000-0000-0000-0000-000000000001',
    'Eliot', 'Photo', false, true, 2,
    'c1000000-0000-0000-0000-000000000003',
    'season/c4000000-0000-0000-0000-000000000002/avatar_1.jpg'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'c1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

create or replace function pg_temp.effectif_photo(p_season_player uuid)
returns text
language sql
stable
as $function$
  select entry ->> 'photo_url'
  from jsonb_array_elements(
    public.admin_get_match_convocations(
      current_setting('test.photo_match')::uuid
    ) -> 'players'
  ) entry
  where entry ->> 'season_player_id' = p_season_player::text;
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.photo_match',
  public.create_match_with_odds_and_sport_limit(
    'c2000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 2
  )::text,
  true
);

select is(
  pg_temp.effectif_photo('c4000000-0000-0000-0000-000000000001'),
  'c1000000-0000-0000-0000-000000000002/avatar_1.jpg',
  'la photo envoyée par le joueur depuis son profil remonte dans l’effectif'
);

select is(
  pg_temp.effectif_photo('c4000000-0000-0000-0000-000000000002'),
  'season/c4000000-0000-0000-0000-000000000002/avatar_1.jpg',
  'la photo envoyée par un admin sur la ligne d’effectif remonte aussi'
);

reset role;

-- La photo du profil reste prioritaire quand les deux existent : c'est celle
-- que le joueur a choisie lui-même.
update public.season_players
set photo_url = 'season/c4000000-0000-0000-0000-000000000001/avatar_1.jpg'
where id = 'c4000000-0000-0000-0000-000000000001';

set local role authenticated;

select is(
  pg_temp.effectif_photo('c4000000-0000-0000-0000-000000000001'),
  'c1000000-0000-0000-0000-000000000002/avatar_1.jpg',
  'la photo du profil reste prioritaire sur celle de l’effectif'
);

reset role;

select * from finish();
rollback;
