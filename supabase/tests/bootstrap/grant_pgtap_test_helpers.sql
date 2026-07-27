-- Les tests changent volontairement de rôle en cours de transaction. Le verrou
-- applicatif ne doit pas empêcher l’exécution des assertions pgTAP dans la base
-- éphémère de CI. Production ne possède pas cette extension.
grant usage on schema extensions to anon, authenticated;
grant execute on all functions in schema extensions to anon, authenticated;

-- Signature de compatibilité créée uniquement pour les tests historiques.
grant execute on function public.like(text, text, text)
  to anon, authenticated;
