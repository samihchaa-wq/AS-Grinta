# Supprimer un match en cours ou déjà joué

## Ce qui n'allait pas

Le menu d'administration proposait « Supprimer » sur tous les matchs, mais la
base refusait l'opération dans deux cas :

- dès l'ouverture du Live (15 minutes avant le coup d'envoi) ;
- pour tout match terminé ou archivé.

L'application affichait alors « Le match est verrouillé depuis l'ouverture du
Live. » ou « Un match passé ne peut pas être supprimé. », et le message
remplaçait toute la liste du calendrier par une carte « Matchs indisponibles ».

## Ce qui change

- `public.delete_match(uuid)`, réservée au staff, pose deux drapeaux valables
  uniquement pendant sa transaction. Le garde-fou `guard_match_lifecycle_write`
  et le garde-fou des compositions les reconnaissent et laissent passer la
  suppression complète, Live ouvert ou compte rendu validé compris.
- Toute suppression directe dans `public.matches` reste refusée exactement comme
  avant : le verrou T-15 et le verrou des matchs passés ne sont levés que par la
  RPC vérifiée.
- La fenêtre de correction de 24 h continue de protéger les corrections de
  compte rendu ; elle ne bloque plus la suppression du match entier.
- Côté application, l'échec d'une suppression s'affiche en bandeau temporaire et
  ne remplace plus la liste des matchs par une carte d'erreur.
- Le message de confirmation précise ce qui sera effacé quand le match est en
  cours (Live, composition, pronostics) ou déjà joué (classements recalculés).

## Migration et tests

- Migration : `20260828090000_allow_admin_delete_locked_match.sql`.
- Test pgTAP : `supabase/tests/database/admin_delete_locked_match.test.sql`.
- Validation : la suite pgTAP tourne dans la CI Supabase du dépôt. La migration
  n'a pas été appliquée sur staging depuis cette session.
