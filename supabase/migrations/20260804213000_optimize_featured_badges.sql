-- featured_badges() était recalculée une fois par badge arboré. Un même profil
-- arborant plusieurs badges répétait donc profile_badge_stars(profile_id), qui
-- agrège elle-même plusieurs tables statistiques.
--
-- Le contrat public reste strictement identique. Les étoiles sont désormais
-- calculées une seule fois par profil distinct, puis jointes aux badges arborés.
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
  with featured_profiles as materialized (
    select distinct profile_badge.profile_id
    from public.profile_badges profile_badge
    where profile_badge.featured
  ),
  featured_stars as materialized (
    select
      featured_profile.profile_id,
      badge_star.badge_code,
      badge_star.stars
    from featured_profiles featured_profile
    cross join lateral public.profile_badge_stars(
      featured_profile.profile_id
    ) badge_star
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

comment on function public.featured_badges() is
  'Badges arborés, avec étoiles calculées une seule fois par profil distinct.';
