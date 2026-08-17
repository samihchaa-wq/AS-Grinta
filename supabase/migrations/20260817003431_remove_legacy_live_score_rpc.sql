-- Le client Web idempotent est désormais déployé publiquement.
-- Retire l'ancienne surcharge sans operation_id afin qu'aucun appel direct
-- authentifié ne puisse contourner la déduplication des commandes de score.

drop function public.coach_adjust_match_live_score(uuid, text, integer, uuid);
