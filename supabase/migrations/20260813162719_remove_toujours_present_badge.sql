delete from public.profile_badge_seen
where badge_code = 'seasons_complete__1';

delete from public.profile_badges
where badge_id in (
  select id
  from public.badges
  where code = 'seasons_complete__1'
);

delete from public.badges
where code = 'seasons_complete__1';
