-- CI-only compatibility shim before 20260714014500_harden_internal_functions.sql.
-- The hosted historical schema still exposed the V3 odds entry points when the
-- hardening migration ran, but the tracked chain rebuilt directly to V4. Keep
-- the old signatures in the disposable runner as strict wrappers around V4 so
-- the hardening migration validates their search_path and grants as intended.

create or replace function public.calculate_match_odds_v3(
  p_opponent_id uuid,
  p_location text
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.calculate_match_odds_v4(p_opponent_id, p_location);
$$;

create or replace function public.recalculate_upcoming_match_odds_v3()
returns integer
language sql
security definer
set search_path = ''
as $$
  select public.recalculate_upcoming_match_odds_v4();
$$;
