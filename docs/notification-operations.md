# Exploitation des notifications Web Push

## Contrôle quotidien

Exécuter `supabase/diagnostics/notification_health.sql` et examiner :

- le taux de réussite des dernières 24 heures ;
- les codes HTTP et domaines d’endpoint associés aux échecs ;
- les événements métier sans tentative de livraison ;
- les abonnements rattachés à un profil non actif ;
- les doublons d’endpoint, qui doivent toujours être absents.

Le diagnostic n’affiche jamais l’URL complète, la clé `p256dh` ou le secret `auth`.

## Seuils d’intervention

- **Incident critique** : aucune tentative de livraison pendant six heures alors qu’un événement de notification a été créé.
- **Incident élevé** : taux de réussite inférieur à 90 % sur au moins vingt tentatives pendant une heure.
- **Nettoyage immédiat** : réponses HTTP 404 ou 410 répétées, car l’abonnement navigateur n’existe plus.
- **Investigation** : réponses 401, 403 ou 429, qui peuvent signaler un secret invalide, une mauvaise configuration VAPID ou une limitation du fournisseur.
- **Surveillance** : erreurs réseau isolées ou temporaires, sans suppression automatique de l’abonnement.

## Protection contre les doublons

- `push_subscriptions.endpoint` est unique ;
- le journal métier utilise une clé par match et type de notification ;
- les tests Supabase vérifient qu’un endpoint expiré peut être supprimé sans supprimer un abonnement actif ;
- toute nouvelle notification doit posséder une clé d’idempotence stable avant son déploiement.

## Validation sur appareils

À chaque modification du pipeline, tester au minimum :

- iPhone installé en PWA ;
- Android avec Chrome ;
- navigateur d’ordinateur ;
- refus puis acceptation de l’autorisation ;
- ouverture de la bonne page depuis une notification ;
- désactivation d’une préférence utilisateur ;
- expiration ou suppression volontaire d’un abonnement.

Les essais doivent utiliser un match de test clairement identifié et ne jamais envoyer un rappel trompeur à tout l’effectif.

## Rotation des secrets

Une rotation de la clé interne ou des clés VAPID doit être préparée avec :

1. enregistrement des anciennes valeurs dans le gestionnaire de secrets, jamais dans GitHub ;
2. déploiement de la fonction utilisant la nouvelle valeur ;
3. envoi contrôlé à un appareil de test ;
4. surveillance du taux d’échec ;
5. suppression de l’ancienne valeur après validation.
