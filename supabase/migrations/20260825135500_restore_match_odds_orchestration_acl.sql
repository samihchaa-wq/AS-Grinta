-- Keep the legacy staff orchestration RPCs callable by authenticated clients.
-- They enforce is_match_staff() internally and ignore caller-provided odds.
-- Only the low-level odds writers/recalculators remain service-role only.

grant execute on function public.create_match_with_odds(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric) to authenticated;

grant execute on function public.update_match_with_odds(uuid, uuid, uuid, date, time without time zone, text, text, numeric, numeric, numeric) to authenticated;
