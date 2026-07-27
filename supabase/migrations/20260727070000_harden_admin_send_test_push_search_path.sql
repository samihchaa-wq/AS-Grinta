-- Évite qu'un objet créé dans un schéma de recherche détourne les appels
-- effectués par cette fonction SECURITY DEFINER.
alter function public.admin_send_test_push()
  set search_path = '';
