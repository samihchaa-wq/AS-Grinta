-- Suppression complète de la fonctionnalité « Matchs entre nous ».
-- La migration de création reste dans l'historique afin que les environnements
-- neufs rejouent correctement la chronologie avant de supprimer ces objets.

drop function if exists public.admin_delete_internal_match(uuid);

drop function if exists public.admin_save_internal_match(
  uuid,
  uuid,
  timestamptz,
  text,
  text,
  text,
  integer,
  integer,
  jsonb
);

drop table if exists public.internal_match_players;
drop table if exists public.internal_matches;
