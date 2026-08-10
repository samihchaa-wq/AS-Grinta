-- Retire l'accès anonyme aux nouvelles fonctions (elles restent protégées
-- par leurs contrôles internes is_admin/is_match_staff, mais on n'expose pas
-- l'endpoint au rôle anon).
revoke execute on function public.finalize_match_postgame(uuid, integer, jsonb, uuid) from public, anon;
grant execute on function public.finalize_match_postgame(uuid, integer, jsonb, uuid) to authenticated;

revoke execute on function public.set_season_predictions_lock(uuid, boolean) from public, anon;
grant execute on function public.set_season_predictions_lock(uuid, boolean) to authenticated;

-- is_active_profile est appelée dans les policies RLS : elle doit rester
-- exécutable par authenticated, mais pas par anon.
revoke execute on function public.is_active_profile() from public, anon;
grant execute on function public.is_active_profile() to authenticated;
