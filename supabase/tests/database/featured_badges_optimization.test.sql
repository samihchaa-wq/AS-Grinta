begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Le bootstrap métier s'arrête à la dernière migration déjà déployée.
-- Ce remplacement est exécuté dans la transaction pgTAP puis annulé.
create or replace function public.featured_badges()
returns table(
  profile_id uuid, code text, emoji text, image_url text, color text,
  metric text, threshold integer, has_star boolean, stars integer,
  category text, sort_order integer
)
language sql
stable
security invoker
set search_path to 'public'
as $function$
  with featured_profiles as materialized (
    select distinct profile_badge.profile_id
    from public.profile_badges profile_badge
    where profile_badge.featured
  ),
  featured_stars as materialized (
    select featured_profile.profile_id, badge_star.badge_code, badge_star.stars
    from featured_profiles featured_profile
    cross join lateral public.profile_badge_stars(
      featured_profile.profile_id
    ) badge_star
  )
  select
    profile_badge.profile_id, badge.code, badge.emoji, badge.image_url,
    badge.color, badge.metric, badge.threshold, badge.has_star,
    coalesce(featured_star.stars, 1) as stars,
    badge.category, badge.sort_order
  from public.profile_badges profile_badge
  join public.badges badge on badge.id = profile_badge.badge_id
  left join featured_stars featured_star
    on featured_star.profile_id = profile_badge.profile_id
   and featured_star.badge_code = badge.code
  where profile_badge.featured
  order by profile_badge.profile_id, badge.sort_order;
$function$;

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
  ),
  'les permissions de featured_badges restent inchangées'
);

select ok(
  (
    select lower(function.prosrc) like '%featured_profiles as materialized%'
      and lower(function.prosrc) like '%select distinct profile_badge.profile_id%'
      and lower(function.prosrc) like '%featured_stars as materialized%'
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'featured_badges'
      and function.pronargs = 0
  ),
  'les étoiles sont calculées une seule fois par profil distinct'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  ('fd000000-0000-0000-0000-000000000001', 'featured-one@example.invalid',
   '{"first_name":"Featured","last_name":"One"}'::jsonb),
  ('fd000000-0000-0000-0000-000000000002', 'featured-two@example.invalid',
   '{"first_name":"Featured","last_name":"Two"}'::jsonb);

update public.profiles
set status = 'active', updated_at = now()
where id in (
  'fd000000-0000-0000-0000-000000000001',
  'fd000000-0000-0000-0000-000000000002'
);

insert into public.badges(
  id, code, name, description, emoji, family, auto, sort_order, kind, category
)
values
  ('fd100000-0000-0000-0000-000000000001', 'test_featured_alpha',
   'Test alpha', 'Badge de test alpha', 'A', 'joueur', false, 9101,
   'manual', 'all_time'),
  ('fd100000-0000-0000-0000-000000000002', 'test_featured_beta',
   'Test beta', 'Badge de test beta', 'B', 'joueur', false, 9102,
   'manual', 'all_time'),
  ('fd100000-0000-0000-0000-000000000003', 'test_featured_gamma',
   'Test gamma', 'Badge de test gamma', 'C', 'joueur', false, 9103,
   'manual', 'all_time');

insert into public.profile_badges(profile_id, badge_id, source, featured)
values
  ('fd000000-0000-0000-0000-000000000001',
   'fd100000-0000-0000-0000-000000000001', 'manual', true),
  ('fd000000-0000-0000-0000-000000000001',
   'fd100000-0000-0000-0000-000000000002', 'manual', true),
  ('fd000000-0000-0000-0000-000000000002',
   'fd100000-0000-0000-0000-000000000003', 'manual', true);

select is(
  (select count(*) from public.featured_badges()
   where code like 'test_featured_%'),
  3::bigint,
  'les trois badges de test restent exposés'
);

select results_eq(
  $$
    select * from public.featured_badges()
    where code like 'test_featured_%'
    order by profile_id, sort_order
  $$,
  $$
    select
      profile_badge.profile_id, badge.code, badge.emoji, badge.image_url,
      badge.color, badge.metric, badge.threshold, badge.has_star,
      coalesce(badge_star.stars, 1) as stars,
      badge.category, badge.sort_order
    from public.profile_badges profile_badge
    join public.badges badge on badge.id = profile_badge.badge_id
    left join lateral (
      select star.stars
      from public.profile_badge_stars(profile_badge.profile_id) star
      where star.badge_code = badge.code
      limit 1
    ) badge_star on true
    where profile_badge.featured
      and badge.code like 'test_featured_%'
    order by profile_badge.profile_id, badge.sort_order
  $$,
  'la version optimisée renvoie exactement le résultat historique'
);

select * from finish();
rollback;
