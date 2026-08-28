begin;

-- `season_wrapped_read` était la seule règle de lecture du schéma à appeler
-- ses fonctions de contrôle sans les envelopper dans un sous-select : PostgreSQL
-- les réévaluait donc une fois par ligne au lieu d'une fois par requête.
--
-- Le périmètre autorisé est strictement identique avant et après : profil actif,
-- et soit son propre bilan, soit un administrateur. Seul le moment d'évaluation
-- change. Les appels sont en plus qualifiés explicitement, pour ne plus
-- dépendre du `search_path` en vigueur à la création de la règle.

drop policy if exists season_wrapped_read on public.season_wrapped;

create policy season_wrapped_read
  on public.season_wrapped
  for select
  to authenticated
  using (
    (select public.is_active_profile())
    and (
      profile_id = (select auth.uid())
      or (select public.is_admin())
    )
  );

commit;
