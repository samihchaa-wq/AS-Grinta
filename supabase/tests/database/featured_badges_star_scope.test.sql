begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Le bootstrap métier léger de la CI peut ne pas contenir cette dépendance.
-- Elle est créée uniquement dans la transaction pgTAP puis annulée.
do $bootstrap$
begin
  if to_regprocedure('public.profile_badge_stars(uuid)') is null then
    execute $ddl$
      create function public.profile_badge_stars(p_profile_id uuid)
      returns table(badge_code text, stars integer)
      language sql
      stable
      security invoker
      set search_path to 'public'
      as $function$
        select null::text, null::integer
        where false
      $function$
    $ddl$;
  end if;
end
$bootstrap$;

-- Le bootstrap CI ne rejoue pas automatiquement les nouvelles migrations.
-- Ce remplacement reproduit donc la migration de cette PR dans la transaction.
create or replace function public.featured_badges()
returns table(
  profile_id uuid,
  code text,
  emoji text,
  image_url text,
  color text,
  metric text,
  threshold integer,
  has_star boolean,
  stars integer,
  category text,
  sort_order integer
)
language sql
stable
security invoker
set search_path to 'public'
as $function$
  with starred_featured as materialized (
    select distinct
      profile_badge.profile_id,
      badge.code
    from public.profile_badges profile_badge
    join public.badges badge on badge.id = profile_badge.badge_id
    where profile_badge.featured
      and badge.has_star
  ),
  starred_profiles as materialized (
    select distinct starred_featured.profile_id
    from starred_featured
  ),
  featured_stars as materialized (
    select
      starred_profile.profile_id,
      badge_star.badge_code,
      badge_star.stars
    from starred_profiles starred_profile
    cross join lateral public.profile_badge_stars(
      starred_profile.profile_id
    ) badge_star
    join starred_featured
      on starred_featured.profile_id = starred_profile.profile_id
     and starred_featured.code = badge_star.badge_code
  )
  select
    profile_badge.profile_id,
    badge.code,
    badge.emoji,
    badge.image_url,
    badge.color,
    badge.metric,
    badge.threshold,
    badge.has_star,
    coalesce(featured_star.stars, 1) as stars,
    badge.category,
    badge.sort_order
  from public.profile_badges profile_badge
  join public.badges badge on badge.id = profile_badge.badge_id
  left join featured_stars featured_star
    on featured_star.profile_id = profile_badge.profile_id
   and featured_star.badge_code = badge.code
  where profile_badge.featured
  order by profile_badge.profile_id, badge.sort_order;
$function$;

revoke execute on function public.featured_badges() from public, anon;
grant execute on function public.featured_badges() to authenticated, service_role;

select ok(
  (
    select function.provolatile = 's'
      and not function.prosecdef
      and 'search_path=public' = any(coalesce(function.proconfig, '{}'::text[]))
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'featured_badges'
      and function.pronargs = 0
  ),
  'featured_badges reste stable, SECURITY INVOKER et avec un search_path fixe'
);

select ok(
  not has_function_privilege('anon', 'public.featured_badges()', 'EXECUTE')
  and has_function_privilege(
    'authenticated', 'public.featured_badges()', 'EXECUTE'
  )
  and has_function_privilege(
    'service_role', 'public.featured_badges()', 'EXECUTE'
  ),
  'les permissions de featured_badges restent inchangées'
);

select ok(
  (
    select lower(function.prosrc) like '%starred_featured as materialized%'
      and lower(function.prosrc) like '%and badge.has_star%'
      and lower(function.prosrc) like '%starred_profiles as materialized%'
      and lower(function.prosrc) like '%profile_badge_stars(%'
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'featured_badges'
      and function.pronargs = 0
  ),
  'le calcul lourd est limité aux profils ayant un badge mis en avant étoilé'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  ('fe000000-0000-0000-0000-000000000001', 'featured-star@example.invalid',
   '{"first_name":"Featured","last_name":"Star"}'::jsonb),
  ('fe000000-0000-0000-0000-000000000002', 'featured-plain@example.invalid',
   '{"first_name":"Featured","last_name":"Plain"}'::jsonb);

update public.profiles
set status = 'active', updated_at = now()
where id in (
  'fe000000-0000-0000-0000-000000000001',
  'fe000000-0000-0000-0000-000000000002'
);

insert into public.badges(
  id, code, name, description, emoji, family, auto, sort_order, kind,
  category, metric, threshold, has_star
)
values
  ('fe100000-0000-0000-0000-000000000001', 'test_featured_starred',
   'Test starred', 'Badge de test étoilé', 'S', 'joueur', false, 9201,
   'titre', 'joueur_all_time', 'goals', 10, true),
  ('fe100000-0000-0000-0000-000000000002', 'test_featured_plain_same_profile',
   'Test plain same', 'Badge de test simple', 'P', 'joueur', false, 9202,
   'titre', 'joueur_all_time', null, null, false),
  ('fe100000-0000-0000-0000-000000000003', 'test_featured_plain_other_profile',
   'Test plain other', 'Badge de test simple autre profil', 'Q', 'joueur',
   false, 9203, 'titre', 'joueur_all_time', null, null, false);

insert into public.profile_badges(profile_id, badge_id, source, featured)
values
  ('fe000000-0000-0000-0000-000000000001',
   'fe100000-0000-0000-0000-000000000001', 'manual', true),
  ('fe000000-0000-0000-0000-000000000001',
   'fe100000-0000-0000-0000-000000000002', 'manual', true),
  ('fe000000-0000-0000-0000-000000000002',
   'fe100000-0000-0000-0000-000000000003', 'manual', true);

-- Le helper de test échoue volontairement si le profil qui n'a que des badges
-- sans étoile est calculé. Le succès des assertions suivantes prouve donc que
-- ce calcul inutile est réellement évité.
create or replace function public.profile_badge_stars(p_profile_id uuid)
returns table(badge_code text, stars integer)
language plpgsql
stable
security invoker
set search_path to 'public'
as $function$
begin
  if p_profile_id = 'fe000000-0000-0000-0000-000000000002'::uuid then
    raise exception 'un profil sans badge étoilé ne doit pas être calculé';
  end if;

  if p_profile_id = 'fe000000-0000-0000-0000-000000000001'::uuid then
    return query
      select 'test_featured_starred'::text, 7::integer;
  end if;

  return;
end;
$function$;

select is(
  (select count(*) from public.featured_badges()
   where code like 'test_featured_%'),
  3::bigint,
  'les trois badges de test restent exposés'
);

select is(
  (select stars from public.featured_badges()
   where code = 'test_featured_starred'),
  7,
  'le badge étoilé conserve son nombre réel d étoiles'
);

select results_eq(
  $$
    select code, stars
    from public.featured_badges()
    where code in (
      'test_featured_plain_same_profile',
      'test_featured_plain_other_profile'
    )
    order by code
  $$,
  $$
    values
      ('test_featured_plain_other_profile'::text, 1::integer),
      ('test_featured_plain_same_profile'::text, 1::integer)
  $$,
  'les badges sans étoiles gardent la valeur historique de 1 sans calcul lourd'
);

select * from finish();
rollback;
