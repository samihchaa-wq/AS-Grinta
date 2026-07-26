# Données personnelles et conservation

Ce document décrit le comportement technique actuel de Ma Petite Grinta. Il ne remplace pas les obligations juridiques du responsable du club.

## Données rattachées à un compte

L’application peut conserver :

- identité affichée, identifiant, surnom et photo facultative ;
- rôle, statut et préférences de notification ;
- pronostics de matchs et de saison ;
- badges et sélections mises en avant ;
- liens avec les effectifs et les feuilles de match ;
- abonnements Web Push et journaux techniques de livraison ;
- bulletins Homme du match, isolés des lectures client et administrateur ordinaires.

Les mots de passe ne sont jamais stockés dans les tables applicatives. Supabase Auth conserve uniquement les éléments nécessaires à l’authentification.

## Export personnel

`public.export_my_personal_data()` retourne uniquement les données du profil identifié par `auth.uid()`.

L’export exclut :

- les données des autres utilisateurs ;
- les clés `p256dh` et `auth` des abonnements Web Push ;
- les URL complètes des endpoints Push ;
- les secrets, jetons et données internes du service.

Le profil peut préparer cet export depuis **Paramètres → Données personnelles**.

## Suppression d’un compte

La suppression administrative retire le compte Supabase Auth et les données directement liées par cascade, notamment les pronostics, abonnements Push et badges personnels. Avant la suppression, les références d’audit indispensables sont réattribuées au profil technique ou rendues nulles.

Les faits sportifs déjà validés peuvent rester dans l’historique du club afin de préserver les feuilles de match et les statistiques. Le lien `profile_id` est supprimé lorsqu’il est configuré en `ON DELETE SET NULL`. Les noms inscrits dans les effectifs ou imports historiques ne sont pas automatiquement anonymisés : une demande d’anonymisation complète doit être traitée séparément et vérifiée sur les statistiques et feuilles de match.

## Photos

Les photos sont facultatives. Le client limite chaque image à 5 Mo et vérifie sa signature JPEG, PNG ou WebP. Lors d’un remplacement, un trigger supprime l’ancien fichier. Si l’écriture métier échoue après l’upload, le nouveau fichier est supprimé immédiatement.

Un contrôle d’objets orphelins doit être exécuté périodiquement avant toute suppression en masse du stockage.

## Notifications

La désinscription retire l’abonnement du navigateur. Une suppression de compte supprime les abonnements liés. Les journaux de livraison ne doivent pas contenir la clé d’authentification du navigateur et peuvent conserver uniquement l’hôte, le statut, l’erreur résumée et la date nécessaires au diagnostic.

## Homme du match

La table des bulletins n’est directement lisible ni par `anon` ni par `authenticated`. Les résultats agrégés sont exposés sans identité du votant. L’export personnel peut restituer au membre ses propres bulletins, mais aucun bulletin d’un autre profil.

## Contrôles périodiques

- vérifier qu’aucune vue ou RPC client n’expose `voter_profile_id` ;
- vérifier l’absence de secrets Push dans les exports et journaux ;
- tester une suppression de compte dans une transaction annulée ;
- contrôler les fichiers photo orphelins ;
- revoir les durées de conservation avec le responsable du club ;
- consigner toute demande d’export, correction, suppression ou anonymisation.
