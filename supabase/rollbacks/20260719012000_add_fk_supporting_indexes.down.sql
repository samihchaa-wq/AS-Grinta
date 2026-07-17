-- Emergency rollback for 20260719012000_add_fk_supporting_indexes.sql.
-- Dropping these indexes does not remove business rows.

drop index if exists public.profile_badges_awarded_by_idx;
drop index if exists public.profile_badges_badge_id_idx;
drop index if exists public.season_awards_profile_id_idx;
