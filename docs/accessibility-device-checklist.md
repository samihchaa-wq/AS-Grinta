# Validation accessibilité sur appareils

Les contrôles automatisés vérifient déjà les affichages mobile étroit, mobile standard, paysage et ordinateur. Cette fiche couvre les comportements qu’un navigateur sans lecteur d’écran ne peut pas valider.

## Préparation

- Utiliser la dernière version déployée après une CI verte.
- Tester avec un compte joueur actif et un compte administrateur.
- Noter la version de l’application, l’appareil, le système et le navigateur.
- Joindre une capture ou un enregistrement à toute anomalie.

## iPhone et iPad — VoiceOver

- Activer VoiceOver puis ouvrir l’application installée en PWA.
- Parcourir Connexion, Accueil, Matchs, Pronostics, Stats, Paramètres et Profil uniquement par balayage.
- Vérifier que chaque bouton à icône annonce une action compréhensible.
- Vérifier que le focus suit l’ordre visuel et ne reste pas bloqué dans une boîte de dialogue.
- Créer ou modifier un pronostic, puis confirmer que les champs et erreurs sont annoncés.
- Ouvrir une composition et vérifier que le nom, le rôle et l’état de chaque joueur sont compréhensibles sans la position visuelle seule.
- Tester le bandeau de mise à jour PWA et le bouton Réessayer hors connexion.

## Android — TalkBack

- Répéter les parcours VoiceOver avec TalkBack et Chrome.
- Vérifier le clavier, le bouton Retour et la fermeture des boîtes de dialogue.
- Vérifier que les messages temporaires restent annoncés assez longtemps.
- Tester l’autorisation des notifications et l’ouverture d’une notification reçue.

## Grande taille de texte

Tester à 150 % puis 200 % :

- aucun texte essentiel coupé ;
- aucun bouton inaccessible ;
- les tableaux statistiques restent défilables ;
- les cartes de match conservent le score, les équipes et l’action principale ;
- les formulaires restent utilisables en portrait et en paysage.

## Clavier et ordinateur

- Parcourir toutes les actions avec Tabulation et Majuscule+Tabulation.
- Vérifier un indicateur de focus visible.
- Valider les formulaires avec Entrée sans déclencher deux envois.
- Fermer les dialogues avec Échap lorsque cela ne supprime pas une donnée sans confirmation.
- Vérifier que le bandeau de mise à jour est un vrai bouton activable au clavier.

## Contraste et mouvement

- Contrôler les textes secondaires, états désactivés, badges et graphiques avec un outil de contraste.
- Activer la réduction des animations du système et vérifier qu’aucune information ne dépend d’une animation.
- Vérifier que victoire, nul, défaite, présence et absence ne sont jamais distingués uniquement par une couleur.

## Critère de validation

Le point est validé sur appareils uniquement lorsque les parcours essentiels sont réalisables sans assistance visuelle, sans perte d’information à 200 % et sans blocage clavier. Toute exception doit être documentée avec une issue dédiée, sa gravité et un contournement temporaire.
