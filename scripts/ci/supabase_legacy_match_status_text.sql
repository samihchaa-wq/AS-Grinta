-- CI-only compatibility shim for the historical matches.status transition.
--
-- The hosted project had already converted public.matches.status from the
-- temporary public.match_status enum to text before the tracked migration
-- 20260710113000_remove_live_match_status.sql replaced its CHECK constraint.
-- The repository history does not contain that conversion. This file is copied
-- only into the disposable GitHub Actions migration chain immediately before
-- that migration and is never applied to a hosted Supabase project.

alter table public.matches
  alter column status drop default,
  alter column status type text using status::text,
  alter column status set default 'a_venir';
