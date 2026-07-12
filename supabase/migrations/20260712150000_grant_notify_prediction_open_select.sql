-- Le rôle `authenticated` dispose uniquement de droits SELECT au niveau colonne
-- sur public.profiles. preferences_repository.fetch lit directement la colonne
-- notify_prediction_open, ce qui échouait avec « permission denied for table
-- profiles ». On ajoute le droit SELECT manquant sur cette colonne.
grant select(notify_prediction_open) on public.profiles to authenticated;
