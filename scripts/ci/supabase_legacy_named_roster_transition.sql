-- CI-only compatibility shim before 20260712140000_named_roster.sql.
-- The early tracked schema already contains season_players.is_active, while the
-- later named-roster migration assumes that column has not been introduced yet.
-- That migration deletes all season_players rows immediately before changing the
-- table shape, so dropping this legacy column in the disposable runner preserves
-- no data and only restores the historical precondition expected by the file.

alter table public.season_players
  drop column if exists is_active;
