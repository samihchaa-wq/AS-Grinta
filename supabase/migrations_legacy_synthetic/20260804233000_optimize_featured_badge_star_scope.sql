begin;

-- featured_badges() n'a besoin des calculs de carrière coûteux que pour les
-- badges mis en avant qui supportent réellement des étoiles. Les badges sans
-- étoiles gardent leur valeur historique de 1 sans appeler
-- profile_badge_stars(), et chaque profil concerné par au moins un badge étoilé
-- n'est calculé qu'une seule fois.
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

commit;
