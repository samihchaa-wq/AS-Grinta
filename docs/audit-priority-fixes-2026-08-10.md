# Correctifs prioritaires issus de l’audit — 10 août 2026

Cette branche traite les correctifs validés après l’audit, hors reconstruction historique complète, nettoyage des anciens comptes, migration d’hébergement et micro-optimisations non prioritaires.

## Corrigé

- Vote Homme du Match protégé contre une clôture avant l’échéance prévue.
- Disponibilité d’un compte non joueur traitée comme « non concerné » au lieu d’une erreur.
- Session conservée lors d’une indisponibilité temporaire du profil.
- Historique de postes restauré.
- Pronostics de saison enregistrés en une opération atomique.
- Cache persistant des événements invalidé après écriture.
- Rechargement des matchs forcé après écriture et protégé contre les réponses anciennes.
- Rapport d’intégrité corrigé pour les matchs « entre nous ».
- Création simultanée d’un même invité sérialisée et protégée par unicité.
- Suppression de compte rendue répétable et vérifiée.
- Anciens types de rappel J−3/J−1 acceptés par le journal de livraison.
- Inscription protégée sans quota global partagé pouvant bloquer tout le club.
- Tests de non-régression ajoutés.
- Diagnostic périodique de rejeu complet ajouté sans bloquer les livraisons tant que la réparation historique est volontairement différée.

## Volontairement différé

- Réparation complète du rejeu historique depuis une base vide.
- Nettoyage des anciens comptes incomplets.
- Changement d’hébergement pour des en-têtes Web supplémentaires.
- Micro-optimisations non justifiées par les temps mesurés.
