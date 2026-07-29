-- The v3 odds functions have no database dependants and are no longer
-- referenced by the application. The active trigger chain still uses the v4
-- wrappers, which feed the current compact-history model.
drop function if exists public.calculate_match_odds_v3(uuid, text);
drop function if exists public.recalculate_upcoming_match_odds_v3();
