-- Retour arrière d'urgence uniquement.
-- Réintroduit les autorisations qui existaient avant la migration
-- 20260726210500_restrict_public_definer_execution.sql.

-- admin_set_match_address était exécutable par PUBLIC, donc notamment anon.
grant execute on function public.admin_set_match_address(uuid, text)
  to public;

-- cleanup_replaced_photo était également exécutable par PUBLIC.
grant execute on function public.cleanup_replaced_photo()
  to public;
