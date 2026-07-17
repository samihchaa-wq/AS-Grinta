-- Supporting indexes for foreign-key lookups and deletion checks.
-- No business rows are changed.

create index if not exists profile_badges_awarded_by_idx
  on public.profile_badges (awarded_by)
  where awarded_by is not null;

create index if not exists profile_badges_badge_id_idx
  on public.profile_badges (badge_id);

create index if not exists season_awards_profile_id_idx
  on public.season_awards (profile_id);
