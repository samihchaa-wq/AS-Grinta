# Changelog

Toutes les évolutions notables de Ma Petite Grinta sont documentées ici.

## Non publié

### Produit

- retrait du pari « Buteurs » (pronostic de saison) : saisie, verrouillage des
  paris, gel de l'effectif, classement Buteurs, bonus d'ordre, titres
  « meilleur prono joueurs » et « meilleur pronostiqueur global », et leurs
  badges ;
- le pronostic de match devient la seule compétition : les trois onglets de
  classement (Matchs, Buteurs, Global) laissent place à un classement unique.
- compte rendu d'un match terminé : la liste des buts s'affiche en entier dans
  la page et le bouton « Valider le compte rendu » redevient atteignable ; il
  n'y a plus de zone de défilement imbriquée qui coupait la saisie des buteurs
  et des passeurs.
- calendrier (« Défilé » et « Par mois ») : chaque rencontre s'affiche sur une
  ligne « Équipe 1  score – score  Équipe 2 », score (ou « VS ») pile au
  milieu de la carte, écusson à côté d'AS Grinta ; un nom trop long passe sur
  plusieurs lignes en police un peu plus petite. « Match entre nous » et le
  titre des événements sont centrés.

## 0.2.2+4 — 2026-07-27

### Sécurité et données

- verrouillage complet des permissions visiteur, compte en attente, joueur et administrateur ;
- couverture transactionnelle des politiques RLS, des RPC sensibles et des buckets Storage ;
- export personnel et documentation de confidentialité déployés ;
- propagation en temps réel des changements de feature flags aux sessions actives.

### Notifications et exploitation

- gestion reproductible de plusieurs appareils et des endpoints partagés ;
- nettoyage ciblé des abonnements expirés ;
- relance unique des échecs Web Push temporaires et journalisation du nombre d’essais ;
- indicateurs agrégés de santé du pipeline de notifications ;
- retrait du dépôt de l’ancienne fonction `import-match-background`.

### Tests et qualité

- scénario de charge automatisé sur huit saisons, 480 matchs et plus de 46 000 lignes métier ;
- mesure de la couverture Flutter avec un plancher initial de non-régression à 15 % ;
- installation verrouillée des dépendances et audit des paquets abandonnés, vulnérables ou retirés ;
- formatage de tous les fichiers Dart et analyse avec avertissements et informations bloquants.

## 0.2.1+3 — 2026-07-26

### Fiabilité et sécurité

- sécurisation des suppressions de joueurs et de comptes déjà liés à l’historique ;
- durcissement des fonctions Supabase privilégiées et des politiques RLS internes ;
- neutralisation des anciennes fonctions de maintenance ;
- contrôle systématique de la dérive des migrations de production ;
- diagnostic reproductible des erreurs, tâches planifiées et requêtes coûteuses ;
- validation binaire, limite de taille et nettoyage des photos téléversées.

### Tests et livraison

- passage obligatoire par les contrôles Flutter et Supabase avant déploiement ;
- exécution de l’ensemble des tests pgTAP présents dans le dépôt ;
- diagnostic Web sur mobile, paysage et ordinateur ;
- test de rechargement PWA hors ligne et d’ouverture d’un lien direct.

### Statistiques et saisons

- restauration des statistiques joueurs et équipe de la saison 2025-2026 ;
- bascule automatique de la saison actuelle vers « Saison précédente » ;
- conservation des statistiques historiques sans recréer de joueurs dans l’effectif.

### Interface

- amélioration des écrans Matchs, compositions et listes d’attente ;
- ajout d’un système de chargement propre à Ma Petite Grinta ;
- mise en évidence de la ligne de l’utilisateur connecté ;
- bandeau de mise à jour PWA accessible au clavier.

## 0.2.0+2 — 2026-07-14

### Fiabilité

- sécurisation des migrations Supabase et détection de dérive ;
- couverture des parcours Auth, routeur, administration et pronostics ;
- tests transactionnels des invariants critiques Supabase ;
- routeur conservé entre les changements de session.

### Architecture

- suppression d’un ancien écran de pronostics de saison inutilisé ;
- découpage du hub Pronos en composants spécialisés ;
- découpage de la page Administration ;
- centralisation de la configuration de build.

### Interface

- séparation des comptes administratifs entre « Validés » et « En attente de validation » ;
- renommage de l’onglet « Saison » en « Buteur » ;
- affichage de la version dans l’écran « Plus ».

## 0.1.0+1

- première version de l’application.
