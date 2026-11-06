# Règles de fonctionnement

Ce document décrit le fonctionnement attendu de l’application, module par
module. Il complète la présentation générale du `README.md`.

Le fonctionnement réel de la production prévaut sur ce document : en cas
d’écart, c’est la production qui fait foi, et ce document doit être corrigé.

## Comptes et rôles

- Auto-inscription puis validation du compte.
- Deux niveaux d’accès applicatifs : `pronostiqueur` (Utilisateur) et `admin`.
- Un Admin possède tous les droits d’administration du club.
- Gardien est un attribut sportif et n’accorde aucun droit applicatif supplémentaire.
- Coach est un attribut sportif : le coach garde toutes les fonctionnalités du
  club (notifications, disponibilités, pronostics, vote Homme du match) et peut
  piloter le Live des matchs de sa saison. Il apparaît dans l’effectif du match
  dès qu’il se dit présent, hors quota de convoqués, mais jamais dans la
  composition d’équipe, jamais dans la liste d’attente, et jamais dans les
  « Statistiques Joueurs » — il reste présent dans les « Statistiques Pronos ».
- Les anciennes valeurs `moderateur` sont converties en `admin` ; les anciens clients restent tolérés pendant la transition.
- Les comptes inactifs ne peuvent pas utiliser les fonctions métier protégées.
- Les joueurs de l’effectif peuvent être liés à un compte.
- Les invités de match n’ont pas besoin de compte permanent.

## Calendrier et historique

- La saison ouverte utilise le cycle complet des matchs.
- Le calendrier permet d’ouvrir les saisons archivées et d’afficher les anciens résultats en lecture seule.
- Les résultats importés restent volontairement séparés des matchs modernes afin de ne pas créer de faux pronostics, compositions, Live ou notifications.
- La saison actuelle peut être ajoutée à un agenda compatible par abonnement (flux `.ics`) : l’agenda se met à jour tout seul, et un match annulé en disparaît. L’ancien export local d’un fichier `.ics` a été retiré.
- La version PC/PWA limite la largeur utile du calendrier et utilise une navigation latérale sur les grands écrans.

## Cycle actuel d’un match

- **J-6 à 12 h, Europe/Paris** : le match entre dans la fenêtre « Prochain match » et les disponibilités s’ouvrent.
- **J-6 à 12 h → T-15** : pronostics, Effectif et Composition sont disponibles selon les droits de l’utilisateur.
- Une fois l’Effectif enregistré, la Composition propose de **simuler un onze** dans le dispositif choisi. La simulation ne remplit pas les postes un par un : elle cherche l’équipe entière la plus cohérente, chaque règle primant sur les suivantes — aucun poste vide tant qu’un convoqué peut l’occuper (un invité ne fait que compléter), personne hors de ses habitudes sans nécessité, ceux qui ont commencé remplaçants la dernière fois qu’ils ont joué dans la saison titularisés (même si ce n’était pas le dernier match de l’équipe), puis chacun au plus près de ses postes de référence ; à égalité parfaite, le plus souvent remplaçant passe devant. Dans l’éditeur, le compteur banc de ces joueurs prioritaires est bleu. Les buts ne reviennent qu’à un gardien déclaré. Un message dit ensuite qui revient du banc et ce qui mérite un coup d’œil : joueur hors de son poste habituel, poste à confirmer faute de matchs joués, poste resté vide. Les postes de référence se mettent à jour tout seuls au fil des matchs joués. La proposition n’est qu’un point de départ, entièrement modifiable, et n’est enregistrée que par le bouton Enregistrer.
- **T-15** : les pronostics ferment, Effectif/Composition sont gelés et le Live peut être ouvert.
- **Live** : chronomètre, événements, buts (avec leur passeur décisif), remplacements et gestion de la composition réelle.
- Un joueur ou invité ajouté tardivement pendant le Live arrive directement sur le banc.
- La validation du récapitulatif Live finalise le match avant son passage normal en match passé.
- Les « Faits du match » de la fiche viennent du compte rendu validé, pas de la
  saisie en direct : un Live mal rempli se corrige dans le compte rendu,
  pendant la fenêtre de correction, et la fiche suit aussitôt.
- Le vote Homme du match ouvre après cette validation et ferme **24 h après le coup d’envoi**.

## Pronostics

- Pronostics de match ouverts dans la fenêtre active du match jusqu’à T-15.
- Les pronostics restent privés avant la validation du résultat.
- Le multiplicateur / portefeuille **×2 ne fait plus partie du produit actuel**.
- Les anciennes migrations et certaines signatures de compatibilité peuvent encore contenir des traces de ×2.

## Gestion sportive

Le module actuel comprend notamment :

- disponibilités ;
- indisponibilités déclarées à l’avance ;
- liste d’attente et rotation ;
- convocations ;
- joueurs de l’effectif et invités ;
- composition tactique et simulation de composition ;
- Live ;
- présence finale, buts, passes décisives et clean sheets ;
- statistiques ;
- vote collectif et anonyme de l’Homme du match.

### Indisponibilité déclarée

Depuis Paramètres, chaque joueur déclare lui-même les périodes où il ne sera pas
là, avec une raison en texte libre. Les bornes sont des dates pleines, incluses,
lues en Europe/Paris.

- Un match dont le coup d’envoi tombe dans la période pose automatiquement le
  joueur **absent** : il sort de l’effectif convocable, et les notifications qui
  en découlent ne lui sont plus envoyées (`docs/NOTIFICATIONS_V2.md`).
- S’il était déjà convoqué sur un match publié, il se retire exactement comme
  une désistement ordinaire : le suivant de la liste d’attente monte, et son
  tour n’est pas consommé avant l’heure limite.
- Pendant la période, ni lui ni un administrateur ne peut répondre à la
  disponibilité des matchs concernés : la période est la seule source de vérité.
- La période reste modifiable et annulable tant qu’elle n’est pas terminée.
  L’annulation rend les matchs concernés à « sans réponse », sauf ceux où le
  joueur s’était déjà déclaré absent lui-même : cette réponse lui appartient.
- Un match programmé après coup, ou déplacé vers une autre date, est rattrapé
  automatiquement.
- Seuls les administrateurs voient l’ensemble des indisponibilités du club, en
  lecture seule, avec l’auteur, la date de saisie, la période et la raison.

Les postes de référence utilisés par la simulation de composition ne sont saisis nulle part : ils sont **déduits des compositions réellement alignées**, et suivent donc l’évolution des joueurs.

- Le socle est `lib/features/sports_management/domain/player_position_profiles.dart`, produit par `tool/derive_position_profiles.py` depuis l’archive du club, qui couvre les compositions jusqu’au 21 mai 2026.
- Les matchs joués depuis viennent s’y ajouter au chargement de l’écran, via `admin_get_player_position_history`. Un joueur qui change durablement de poste voit son profil basculer sans redéploiement ; une recrue absente de l’archive s’en construit un à partir de ses seuls matchs.
- Les deux sources utilisent la même pondération par récence, ancrée sur la même saison de référence, ce qui permet de les additionner directement.
- Tout est indexé sur l’identité canonique `players.id`, stable d’une saison à l’autre et insensible aux changements de nom.

## Notifications

Les notifications automatiques actuelles comprennent notamment :

- ouverture des disponibilités ;
- changements importants d’un match ;
- rappel de pronostic le jour du match à 16 h si activé et nécessaire ;
- entrée en liste d’attente, et passage de la liste d’attente aux convoqués ;
- ouverture du vote HDM si activée ;
- résultat du vote HDM sous le même réglage utilisateur.

Le contrat détaillé est dans `docs/NOTIFICATIONS_V2.md`.

## Statistiques, badges et profils

- Statistiques individuelles et collectives.
- Buts, passes décisives, clean sheets, matchs joués et Homme du match.
- Les passes décisives sont suivies depuis leur mise en service : les saisons
  importées et les matchs validés avant restent à zéro, sans reconstitution.
- Saison actuelle, saison précédente et historique toutes saisons.
- Badges automatiques et manuels.
- Photos de profil, de joueur et d’invité.
