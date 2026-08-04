# Données personnelles et conservation

Ce document décrit le comportement technique actuel de AS Grinta. Il ne remplace pas les obligations juridiques du responsable du club.

## Données rattachées à un compte

L’application peut conserver :

- identité affichée, identifiant, surnom et photo facultative ;
- rôle, statut et préférences de notification ;
- pronostics de matchs et de saison ;
- badges et sélections mises en avant ;
- liens avec les effectifs et les feuilles de match ;
- abonnements Web Push et journaux techniques de livraison ;
- bulletins Homme du match, isolés des lectures client et administrateur ordinaires.

Les mots de passe ne sont pas stockés dans les tables applicatives. L’authentification est gérée par Supabase Auth.

## Consultation, correction et demandes personnelles

L’application ne propose actuellement **aucune RPC d’export personnel automatique**. L’ancien `export_my_personal_data()` a été retiré de la surface publique.

La page **Données personnelles** indique au membre de contacter un administrateur du club pour consulter, corriger ou demander la suppression d’une donnée le concernant. Une demande doit être traitée en vérifiant séparément les données de compte et les faits sportifs historiques.

## Suppression d’un compte

La suppression administrative retire le compte de connexion et les données directement liées selon les contraintes réellement configurées, notamment les éléments personnels qui peuvent être supprimés par cascade.

Les faits sportifs déjà validés peuvent rester dans l’historique du club afin de préserver les feuilles de match et les statistiques. Lorsqu’un lien vers un compte est configuré en `ON DELETE SET NULL`, le fait sportif peut subsister sans compte associé.

Les noms présents dans les effectifs, invités ou imports historiques ne sont pas automatiquement anonymisés par la seule suppression du compte. Une demande d’anonymisation complète doit donc être traitée séparément et vérifiée sur les statistiques et feuilles de match.

## Photos

Les photos sont facultatives. Les uploads applicatifs sont limités à 5 Mo et aux formats JPEG, PNG ou WebP par les contrôles Storage concernés.

Lors d’un remplacement ou d’une suppression, le nettoyage des anciens objets doit rester cohérent avec la donnée métier. Un contrôle des objets orphelins doit précéder toute suppression en masse dans Storage.

## Notifications

La désinscription retire l’abonnement du navigateur concerné. La suppression d’un compte doit également supprimer ou rendre inexploitables les abonnements qui lui sont rattachés selon les contraintes courantes.

Les journaux de livraison ne doivent jamais contenir les secrets Web Push du navigateur. Ils ne doivent conserver que les informations techniques nécessaires au diagnostic et à l’idempotence prévues par le schéma actuel.

## Homme du match

La table des bulletins n’est directement lisible ni par `anon` ni par les clients `authenticated`. Les résultats exposés à l’application sont agrégés sans rendre l’identité des votants consultable.

## Contrôles périodiques

- vérifier qu’aucune vue ou RPC client n’expose l’identité d’un votant ;
- vérifier l’absence de secrets Push dans les journaux ;
- tester les parcours de suppression sur un environnement isolé avant toute modification sensible ;
- contrôler les fichiers photo orphelins ;
- revoir les durées de conservation avec le responsable du club ;
- consigner les demandes de consultation, correction, suppression ou anonymisation selon le processus du club.
