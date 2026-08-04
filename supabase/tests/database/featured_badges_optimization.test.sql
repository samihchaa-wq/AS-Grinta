begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'featured_badges'
      and function.pronargs = 0
      and function.provolatile = 's'
      and not function.prosecdef
      and 'search_path=public' = any(coalesce(function.proconfig, '{}'::text[]))
  ),
  'featured_badges reste stable, SECURITY INVOKER et avec un search_path fixe'
);

select ok(
  not has_function_privilege(
    'anon', 'public.featured_badges()', 'EXECUTE'
  )
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
      and lower(function.prosrc) like
        '%profile_badge_stars(%featured_profile.profile_id%'
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'featured_badges'
      and function.pronargs = 0
  ),
  'les étoiles sont calculées une seule fois par profil arborant un badge'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'fd000000-0000-0000-0000-000000000001',
    'featured-one@example.invalid',
    '{"first_name":"Featured","last_name":"One"}'::jsonb
  ),
  (
    'fd000000-0000-0000-0000-000000000002',
    'featured-two@example.invalid',
    '{"first_name":"Featured","last_name":"Two"}'::jsonb
  );

update public.profiles
set status = 'active', updated_at = now()
where id in (
  'fd000000-0000-0000-0000-000000000001',
  'fd000000-0000-0000-0000-000000000002'
);

insert into public.badges(
  id,
  code,
  name,
  description,
  emoji,
  family,
  auto,
  metric,
  threshold,
  sort_order,
  kind,
  category,
  has_star
)
values
  (
    'fd100000-0000-0000-0000-000000000001',
    'test_featured_alpha',
    'Test featured alpha',
    'Badge de test alpha',
    'A',
    'joueur',
    false,
    null,
    null,
    9101,
    'manual',
    'all_time',
    false
  ),
  (
    'fd100000-0000-0000-0000-000000000002',
    'test_featured_beta',
    'Test featured beta',
    'Badge de test beta',
    'B',
    'joueur',
    false,
    null,
    null,
    9102,
    'manual',
    'all_time',
    false
  ),
  (
    'fd100000-0000-0000-0000-000000000003',
    'test_featured_gamma',
    'Test featured gamma',
    'Badge de test gamma',
    'C',
    'joueur',
    false,
    null,
    null,
    9103,
    'manual',
    'all_time',
    false
  );

insert into public.profile_badges(
  profile_id,
  badge_id,
  source,
  featured
)
values
  (
    'fd000000-0000-0000-0000-000000000001',
    'fd100000-0000-0000-0000-000000000001',
    'manual',
    true
  ),
  (
    'fd000000-0000-0000-0000-000000000001',
    'fd100000-0000-0000-0000-000000000002',
    'manual',
    true
  ),
  (
    'fd000000-0000-0000-0000-000000000002',
    'fd100000-0000-0000-0000-000000000003',
    'manual',
    true
  );

select is(
  (
    select count(*)
    from public.featured_badges()
    where code like 'test_featured_%'
  ),
  3::bigint,
  'les trois badges de test restent exposés'
);

select results_eq(
  $$
    select
      profile_id,
      code,
      emoji,
      image_url,
      color,
      metric,
      threshold,
      has_star,
      stars,
      category,
      sort_order
    from public.featured_badges()
    where code like 'test_featured_%'
    order by profile_id, sort_order
  $$,
  $$
    select
      profile_badge.profile_id,
      badge.code,
      badge.emoji,
      badge.image_url,
      badge.color,
      badge.metric,
      badge.threshold,
      badge.has_star,
      coalesce(badge_star.stars, 1) as stars,
      badge.category,
      badge.sort_order
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
