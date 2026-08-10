-- Sécurité : les fonctions internes du moteur de badges étaient exécutables par
-- n'importe qui (rôle anon, non connecté) via /rest/v1/rpc. Elles ne doivent
-- jamais être appelées directement depuis l'API : elles sont déclenchées par des
-- triggers ou l'administration. On révoque donc EXECUTE (PUBLIC/anon/authenticated).
-- Les triggers continuent de fonctionner : leur exécution ne dépend pas du droit
-- EXECUTE accordé aux rôles.
revoke execute on function
  public.award_season_titles(uuid),
  public.profile_mvp_count(uuid),
  public.recalculate_all_badges(),
  public.recalculate_profile_badges(uuid),
  public.trg_award_titles_on_season_close(),
  public.trg_badges_on_attendance(),
  public.trg_badges_on_match_result(),
  public.trg_badges_on_mvp(),
  public.trg_badges_on_player_stats(),
  public.trg_badges_on_prediction()
from public, anon, authenticated;

-- profile_badge_metrics : statistiques en lecture utilisées par l'armoire de la
-- personne connectée. Réservé aux comptes authentifiés (plus accessible à anon).
revoke execute on function public.profile_badge_metrics(uuid) from public, anon;
grant execute on function public.profile_badge_metrics(uuid) to authenticated;
