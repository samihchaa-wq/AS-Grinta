-- Le client Web versionné utilisant p_expected_lineup_revision est maintenant
-- publié et validé sur GitHub Pages. La signature historique sans verrou
-- optimiste ne doit plus rester appelable, sinon un ancien client pourrait
-- encore écraser silencieusement une composition plus récente.

begin;

drop function if exists public.coach_save_match_live_lineup(
  uuid,
  jsonb,
  jsonb
);

commit;
