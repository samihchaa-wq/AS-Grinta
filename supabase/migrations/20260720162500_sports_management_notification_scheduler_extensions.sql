-- The application already relies on Supabase Cron in production.
-- Keep local and fresh environments deterministic before scheduling the
-- optional sports-management availability worker.

create extension if not exists pg_cron;
