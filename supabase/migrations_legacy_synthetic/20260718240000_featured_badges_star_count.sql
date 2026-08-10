-- Les badges arborés (affichés à côté des prénoms) doivent refléter le nombre
-- d'étoiles obtenues, comme dans l'armoire : N fois le dernier palier atteint
-- => chiffre = seuil × N et N étoiles au-dessus. On expose donc le nombre
-- d'étoiles dans featured_badges().
drop function if exists public.featured_badges();

create function public.featured_badges()
returns table(
  profile_id uuid, code text, emoji text, image_url text, color text,
  metric text, threshold integer, has_star boolean, stars integer,
  sort_order integer
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select pb.profile_id, b.code, b.emoji, b.image_url, b.color, b.metric,
         b.threshold, b.has_star,
         coalesce(s.stars, 1) as stars,
         b.sort_order
  from public.profile_badges pb
  join public.badges b on b.id = pb.badge_id
  left join lateral (
    select st.stars
    from public.profile_badge_stars(pb.profile_id) st
    where st.badge_code = b.code
    limit 1
  ) s on true
  where pb.featured
  order by pb.profile_id, b.sort_order;
$function$;

revoke all on function public.featured_badges() from public;
grant execute on function public.featured_badges() to anon, authenticated, service_role;
