-- Les fonctions internes sont utilisées uniquement par les triggers et les RPC
-- publiques prévues à cet effet. Elles ne doivent pas être appelables directement
-- depuis le client.
revoke all on function public.calculate_match_odds_v4(uuid, text)
  from public, anon, authenticated;
revoke all on function public.upsert_match_odds_v4(uuid)
  from public, anon, authenticated;
revoke all on function public.recalculate_upcoming_match_odds_v4()
  from public, anon, authenticated;
revoke all on function public.trigger_match_odds_v4()
  from public, anon, authenticated;

grant execute on function public.preview_match_odds(uuid, text)
  to authenticated;
grant execute on function public.create_match_with_odds(
  uuid, uuid, date, time without time zone, text, numeric, numeric, numeric
) to authenticated;
