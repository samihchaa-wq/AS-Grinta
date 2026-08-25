-- Keep only the staff-facing orchestration RPCs exposed to authenticated clients.
-- Low-level odds writers/recalculators remain server-only.

revoke all on function public.create_match_with_odds(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric) from public, anon, authenticated;
grant execute on function public.create_match_with_odds(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric) to service_role;

revoke all on function public.update_match_with_odds(uuid, uuid, uuid, date, time without time zone, text, text, numeric, numeric, numeric) from public, anon, authenticated;
grant execute on function public.update_match_with_odds(uuid, uuid, uuid, date, time without time zone, text, text, numeric, numeric, numeric) to service_role;

revoke all on function public.set_match_odds(uuid, numeric, numeric, numeric) from public, anon, authenticated;
grant execute on function public.set_match_odds(uuid, numeric, numeric, numeric) to service_role;

revoke all on function public.upsert_match_odds_v4(uuid) from public, anon, authenticated;
grant execute on function public.upsert_match_odds_v4(uuid) to service_role;

revoke all on function public.recalculate_upcoming_match_odds_v4() from public, anon, authenticated;
grant execute on function public.recalculate_upcoming_match_odds_v4() to service_role;

revoke all on function public.trigger_match_odds_v4() from public, anon, authenticated;
grant execute on function public.trigger_match_odds_v4() to service_role;

revoke all on function public.admin_create_match_complete(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric, integer, text, boolean, text, text) from public, anon;
grant execute on function public.admin_create_match_complete(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric, integer, text, boolean, text, text) to authenticated, service_role;

revoke all on function public.admin_update_match_complete(uuid, uuid, uuid, date, time without time zone, text, text, numeric, numeric, numeric, timestamp with time zone, integer, text, boolean, text, text) from public, anon;
grant execute on function public.admin_update_match_complete(uuid, uuid, uuid, date, time without time zone, text, text, numeric, numeric, numeric, timestamp with time zone, integer, text, boolean, text, text) to authenticated, service_role;
