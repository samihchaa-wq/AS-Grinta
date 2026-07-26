# Stabilisation des 18 points d’audit

Ce document complète l’issue de suivi #511. Un point n’est considéré comme terminé qu’après réussite de la CI et, lorsqu’il touche Supabase, vérification de production.

## Socle critique

- Point 1 : fonction d’import de maintenance neutralisée ; suppression définitive à effectuer avec le nettoyage des fonctions temporaires.
- Point 2 : fonctions privilégiées et tables internes durcies ; matrice de tests maintenue dans les tests pgTAP.
- Point 3 : CI et déploiement conditionnel en place ; protection native de `main` encore manuelle, suivie dans #504.
- Point 4 : migrations isolées, garde de dérive et procédures de retour arrière en place ; restauration réelle suivie dans #506.

## Passe en cours

La PR #512 traite notamment :

- l’exécution exhaustive des tests Supabase présents dans le dépôt ;
- le versionnement unique et le fonctionnement hors ligne de la PWA ;
- la validation et le nettoyage des photos téléversées ;
- les contrôles responsive en paysage ;
- le nettoyage des imports inutilisés ;
- l’alignement du changelog sur la version de l’application.

## Actions nécessitant un accès manuel

- activer la protection native de `main` : #504 ;
- restaurer une sauvegarde dans un environnement non productif : #506 ;
- activer la protection Supabase contre les mots de passe compromis : #509 ;
- réaliser les validations VoiceOver, TalkBack et appareils physiques documentées dans la prochaine passe d’accessibilité.
