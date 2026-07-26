-- Réduit la surface des fonctions SECURITY DEFINER exposées par PostgREST.
-- Les contrôles métier restent inchangés : l'application authentifiée conserve
-- l'accès à la mise à jour d'adresse, tandis que la fonction de trigger photo
-- n'est plus appelable directement par un client.

revoke execute on function public.admin_set_match_address(uuid, text)
  from public, anon;
grant execute on function public.admin_set_match_address(uuid, text)
  to authenticated, service_role;

revoke execute on function public.cleanup_replaced_photo()
  from public, anon, authenticated;
grant execute on function public.cleanup_replaced_photo()
  to service_role;

comment on function public.admin_set_match_address(uuid, text) is
  'Met à jour une adresse de match. Appel client authentifié, contrôle admin dans la fonction.';
comment on function public.cleanup_replaced_photo() is
  'Fonction de trigger interne : supprime les anciennes photos remplacées.';
