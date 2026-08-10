-- La migration waitlist_history_counts a créé ces deux fonctions private
-- sans leur accorder EXECUTE à authenticated, alors qu'elles sont appelées
-- par des wrappers publics SECURITY INVOKER (admin_get_match_convocations,
-- admin_get_sport_waitlist, admin_reorder_sport_waitlist). Résultat : tout
-- appel échouait avec "permission denied" pour n'importe quel admin.
grant execute on function private.enrich_sport_waitlist_history(jsonb) to authenticated;
grant execute on function private.enrich_match_convocation_history(jsonb) to authenticated;
