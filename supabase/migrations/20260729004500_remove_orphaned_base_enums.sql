-- Remove enum types left behind by the initial schema.
--
-- At removal time each type had:
-- - zero table-column usage;
-- - zero function-signature usage;
-- - zero casts;
-- - zero PostgreSQL dependents.

drop type if exists public.app_role;
drop type if exists public.goal_side;
drop type if exists public.match_status;
