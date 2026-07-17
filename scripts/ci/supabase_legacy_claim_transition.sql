-- CI-only compatibility shim for a historical function return-type change.
-- PostgreSQL cannot change a function return type through CREATE OR REPLACE.
-- Drop the old uuid-returning version immediately before the tracked migration
-- recreates the same signature with a boolean return type.

drop function if exists public.claim_player_profile(uuid);
