set local lock_timeout = '5s';

drop function public.featured_badges();

create function public.featured_badges()
returns table(
  profile_id uuid,
  code text,
  emoji text,
  image_url text,
  color text,
  metric text,
  threshold integer,
  current_value integer,
  has_star boolean,
  stars integer,
  category text,
  sort_order integer
)
language sql
stable
set search_path = ''
as $function$
  with featured_profiles as materialized (
    select distinct pb.profile_id
    from public.profile_badges pb
    where pb.featured
  ),
  profile_metrics as materialized (
    select
      fp.profile_id,
      to_jsonb(metric_row) as metrics
    from featured_profiles fp
    cross join lateral public.profile_badge_metrics(fp.profile_id) metric_row
  ),
  starred_featured as materialized (
    select distinct
      pb.profile_id,
      b.code
    from public.profile_badges pb
    join public.badges b on b.id = pb.badge_id
    where pb.featured
      and b.has_star
  ),
  starred_profiles as materialized (
    select distinct sf.profile_id
    from starred_featured sf
  ),
  featured_stars as materialized (
    select
      sp.profile_id,
      bs.badge_code,
      bs.stars
    from starred_profiles sp
    cross join lateral public.profile_badge_stars(sp.profile_id) bs
    join starred_featured sf
      on sf.profile_id = sp.profile_id
     and sf.code = bs.badge_code
  )
  select
    pb.profile_id,
    b.code,
    b.emoji,
    b.image_url,
    b.color,
    b.metric,
    b.threshold,
    case
      when b.metric is null then null
      else coalesce((pm.metrics ->> b.metric)::integer, 0)
    end as current_value,
    b.has_star,
    coalesce(fs.stars, 1) as stars,
    b.category,
    b.sort_order
  from public.profile_badges pb
  join public.badges b on b.id = pb.badge_id
  left join profile_metrics pm on pm.profile_id = pb.profile_id
  left join featured_stars fs
    on fs.profile_id = pb.profile_id
   and fs.badge_code = b.code
  where pb.featured
  order by pb.profile_id, b.sort_order;
$function$;

revoke all on function public.featured_badges() from public, anon;
grant execute on function public.featured_badges() to authenticated, service_role;
