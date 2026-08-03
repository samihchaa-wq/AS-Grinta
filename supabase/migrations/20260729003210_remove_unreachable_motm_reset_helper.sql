-- Remove a private helper left behind by the MOTM workflow rewrite.
--
-- Proof of non-use at removal time:
-- - no EXECUTE privilege for anon, authenticated or service_role;
-- - no PostgreSQL dependency;
-- - no reference from any current public/private function body;
-- - no cron job;
-- - no application reference outside historical migrations.

drop function if exists private.reset_match_motm_election(
  uuid,
  integer,
  timestamptz,
  uuid,
  text,
  text
);
