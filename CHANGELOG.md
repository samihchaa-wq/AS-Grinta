# Changelog

Toutes les évolutions notables de Ma Petite Grinta sont documentées ici.

## Non publié

### Produit

- fiche joueur, onglet Carrière : une carte « Évolution » sous le Bilan
  montre une barre par saison pour la statistique choisie (Matchs,
  % Victoires, Buts, HDM, Buts / match ; les buts d'abord, les matchs pour
  un gardien). La meilleure saison est en or ; pour une moyenne, il lui faut
  au moins cinq matchs, comme pour être classé sur une saison. La saison en
  cours, plus pâle, est signalée. Une saison manquée entre deux autres
  apparaît vide. Les passes décisives n'y figurent pas : elles ne sont
  comptées que depuis cette saison. Les saisons archivées sont recalculées
  match par match ; pour cinq joueurs, il manque à l'archive un homme du
  match (et, pour deux d'entre eux, un ou deux buts), si bien que leurs
  barres totalisent un peu moins que leurs chiffres de carrière. La carte
  n'apparaît qu'à partir de deux saisons, et seulement une fois la mise à
  jour de la base de données déployée ;
- icône de l'application : le blason sans sa bordure remplit tout le bouton
  (fond bleu et bandes or jusqu'aux bords, banderole, « 2020 », ballon). La
  croix occitane est redessinée fidèlement ; sur les téléphones Android qui
  découpent l'icône en rond, elle est plus petite et rapprochée du centre
  pour rester entière. L'icône est redessinée proprement, donc plus nette
  qu'avant. Sur iPhone, une application déjà ajoutée à l'écran d'accueil
  garde l'ancienne icône tant qu'elle n'est pas retirée puis rajoutée ; sur
  Android, la nouvelle icône peut mettre un peu de temps à apparaître. L'icône
  de l'onglet du navigateur ne change pas ;
- calendrier, vue Défilé : un match annulé ne s'ouvre plus, même une fois sa
  date passée, et sa carte affiche « Match annulé ». Avant, dès l'heure du
  match passée, il rejoignait les matchs terminés sans plus rien indiquer que
  sa couleur, et ouvrait une fiche de match à venir. La mention, déjà présente
  avant la date sous la forme « Annulé », passe aussi dans un rouge plus
  lisible ;
- notifications : « Match annulé » ouvre le calendrier, sur la carte du match
  annulé, au milieu des autres matchs, au lieu de l'onglet Info de sa fiche.
  Les « Match annulé » déjà reçus, et toute notification sur ce match envoyée
  avant l'annulation, mènent aussi au calendrier ;
- fiche du match : quand un admin ouvre les disponibilités avant J-6
  (« maintenant » ou à une date choisie), les onglets Effectif, Compo et
  Prono apparaissent dès cette ouverture, au lieu d'attendre J-6 à 12 h. Le
  prono est accepté à partir du même moment. Une ouverture plus tardive que
  J-6 ne retarde rien ;
- notifications : une cloche à côté du trophée ouvre l'écran Notifications,
  en deux onglets. « Historique » liste toutes les notifications envoyées
  par le club au joueur, la plus récente en premier, même celles que son
  téléphone n'a pas affichées (notifications bloquées, appareil désabonné ou
  sans abonnement) ; glisser une ligne vers la gauche la supprime, sur tous
  ses appareils. « Paramètres » reprend l'ancien écran des réglages, qui
  quitte la roue dentée. Un petit chiffre sur la cloche compte les
  notifications non lues ; il disparaît quand le joueur ouvre l'écran ou
  fait ce que la notification demandait (répondre à la disponibilité,
  remplir son prono, voter pour l'Homme du match). L'historique garde
  90 jours et démarre vide : les notifications envoyées avant cette version
  n'y figurent pas. Les envois d'essai n'y entrent jamais ;
- notifications : la cloche n'est plus verte quand le téléphone bloque
  l'affichage des notifications dans ses réglages. Un bandeau en haut de
  l'application prévient le joueur quand son appareil ne recevra rien sans
  qu'il l'ait choisi (affichage bloqué par le téléphone, ou appareil
  désabonné après une déconnexion) et le réabonne en un geste. Chaque
  téléphone signale aussi au serveur les notifications qu'il a réellement
  affichées : un envoi accepté par Apple ou Google mais jamais montré se voit
  enfin ;
- fiche joueur : le prénom et le surnom se placent à égale distance de la
  photo et du badge. Une photo détourée (fond transparent) ne remplit pas
  son carré : seule la partie visible de la photo compte désormais ;
- fiche joueur : dans les derniers matchs, le score d'un match nul est en
  orange, comme une victoire en vert et une défaite en rouge ;
- compte rendu de match : l'onglet Effectif n'affiche plus de texte
  d'explication sur le terrain et le banc, et Faits du match n'affiche plus
  « Maintiens un but pour changer son ordre » (le geste reste possible) ;
- compte rendu de match : la passe décisive porte le crampon de la
  composition au lieu de la poignée de main ;
- Homme du match : la liste de vote affiche, pour chaque joueur, les icônes
  de la composition (ballon et nombre de buts, puis crampon et nombre de
  passes décisives) au lieu de « 0 but », « Clean sheet » ou « A
  encaissé » ; un joueur sans but ni passe n'affiche plus rien. Le crampon
  de passe décisive a désormais la même taille que le ballon, sur le
  terrain comme sur la fiche joueur ;
- Homme du match : la notification d'ouverture du vote annonce le score
  final (« Fin du match » — « AS Grinta 2 - 1 Positive Vibration » — « Pense
  à voter pour l'Homme du match. »), équipe à domicile en premier ;
- notifications : sur iPhone, l'icône de l'application affiche une pastille
  avec le nombre de notifications non lues, le même que la cloche ;
- liste d'attente : un joueur est prévenu (« Tu passes en liste
  d'attente ») dès qu'il entre en liste d'attente, et plus seulement quand
  il perd une place de convoqué. Cela vaut pour les joueurs déjà en attente
  à la première publication de l'effectif et pour une réponse « Présent »
  qui tombe directement en attente. Entrer directement chez les convoqués
  reste silencieux ; passer de la liste d'attente aux convoqués envoie
  toujours « Tu es convoqué » ;
- notifications : quand cet appareil ne reçoit rien (cloche du haut grise),
  les cloches réglables passent en gris, inactives, avec « Coupées sur cet
  appareil ». Elles restaient vertes alors que rien n'arrivait ;
- notifications : l'abonnement de l'appareil est réenregistré à chaque
  ouverture de l'application. La cloche du haut ne peut plus rester verte
  pour un téléphone que le serveur ne connaît plus (autre compte connecté
  sur ce téléphone, appareil remplacé par un plus récent) ;
- notifications : convocation, liste d'attente, composition, résultat Homme
  du match, badges, messages libres et tests laissent désormais une trace de
  livraison par appareil, comme les autres notifications. Un refus d'Apple
  ou de Google ne passe plus inaperçu ;

- fiche joueur : le surnom s'affiche entre guillemets (« Poulain ») au lieu
  de « SURNOM Poulain » ; dans « Derniers matchs », le score s'écrit dans
  l'ordre domicile – extérieur (une victoire 5-0 à l'extérieur devient 0-5)
  et toucher un match ouvre sa fiche, la flèche retour ramenant à la fiche
  joueur ;
- passes décisives : le crampon cerclé blanc est posé sur un disque noir,
  pour rester lisible sur le terrain et sur les photos ;
- photos de profil : une photo à fond transparent (joueur détouré) garde sa
  transparence au lieu de prendre un fond blanc ; elle est alors enregistrée
  en PNG, les photos ordinaires restant en JPEG ;
- calendrier : plus d'espace entre deux cartes de match ;
- Android : glisser depuis le bord gauche de l'écran revient à la page
  précédente, comme sur iPhone ;
- fiche joueur : « Derniers matchs » montre les 5 derniers matchs amicaux
  ou de championnat, même s'ils s'étendent sur la saison précédente ; les
  matchs « entre nous » n'y figurent plus. Le rang au club sur le % de
  victoires et les buts par match n'est donné qu'à partir d'un nombre de
  matchs joués (20 en carrière, 5 sur la saison précédente, 5 sur la saison
  en cours une fois que l'équipe a joué plus de 5 matchs) ; en dessous, la
  fiche affiche N/A, et le joueur ne compte pas dans le classement des
  autres ;
- notifications : les interrupteurs des notifications réglables (rappel
  pronostic, vote Homme du match, composition, badge, changement de
  disponibilité côté admin) deviennent des cloches, vertes quand la
  notification est activée et grises sinon, comme celle des notifications
  essentielles ;
- fiche joueur : l'en-tête affiche le vrai prénom (« François », plus en
  majuscules), et en dessous « Surnom » suivi du surnom s'il existe, le tout
  centré entre la photo et le badge. Le badge arboré est réduit à la hauteur
  de la photo ;
- liste d'attente : un joueur qui passe des convoqués à la liste d'attente
  reçoit « Tu passes en liste d'attente », sur le modèle de « Tu es
  convoqué ». Les deux notifications (convoqué ↔ liste d'attente) deviennent
  essentielles : elles partent toujours et ne se règlent plus une par une.
  Seuls le coupe-circuit général et la désactivation complète sur l'appareil
  les arrêtent ;
- armoire à badges : un badge mystère déjà gagné par au moins un membre du
  club n'est plus caché. Il apparaît en noir et blanc, sous cadenas, et
  s'ouvre comme les autres badges pour lire son nom et sa condition. Le
  détail d'un badge, dans l'armoire comme sur une fiche joueur, liste les
  joueurs qui l'ont obtenu ;
- fiche joueur : « Bilan avec lui » devient « Bilan ». Dans « Derniers
  matchs », buts, passes décisives et Homme du match reprennent les icônes
  des compositions (ballon, crampon, couronne) ;
- compositions : l'emoji 👟 des passes décisives est remplacé par un vrai
  crampon dessiné (tige blanche, liseré jaune, semelle à crampons), lisible
  sur le terrain comme sur fond sombre ;
- fiche joueur : en-tête allégé (photo comme sur les compositions, sans
  poste ni nombre de matchs) et badge arboré nettement plus grand. Les six
  statistiques suivent l'ordre Matchs, % Victoires, Buts, Passes D., HDM,
  Buts / match, chacune avec le rang du joueur au club ; le chiffre passe en
  or, argent ou bronze pour les trois premiers. Nouveau module « Badges »
  qui reprend tous les badges gagnés, secrets compris ;
- statistiques : toucher le nom d'un joueur, dans l'onglet Joueurs comme
  dans l'onglet Prono, ouvre sa fiche joueur. On y trouve son poste, son
  nombre de matchs au club, ses chiffres par période (saison, précédente,
  carrière) avec son rang au club, son bilan victoires/nuls/défaites, sa
  forme sur les cinq derniers matchs et la liste de ses derniers matchs
  suivis dans l'application. Ailleurs (classement des pronos dans le
  Calendrier), les noms ne sont pas cliquables ;
- liste d'attente : enregistrer l'effectif d'un match ne fige plus que les
  joueurs qu'un admin a réellement déplacés. Jusqu'ici, chaque enregistrement
  figeait aussi tous les joueurs déjà disponibles : ceux qui répondaient
  ensuite se partageaient les seules places restantes, quel que soit leur
  rang. Le surplus passe désormais en attente selon l'ordre de la liste, même
  si un joueur déjà convoqué doit céder sa place à une réponse plus tardive.
  Ce joueur est prévenu par la notification « Tu passes en liste
  d'attente » ;
- fiches de match (passées, archivées, à venir, version admin) : plus de
  barre en haut. L'écusson, le titre « Fiche du match » et le bouton
  d'actualisation disparaissent ; le bandeau du match se place à droite de la
  flèche retour et tout le contenu remonte. Noms d'équipes et écusson du
  bandeau sont plus petits, à la même taille sur toutes les fiches, et un
  texte trop long passe à la ligne au lieu d'être coupé par « … ». Tirer
  l'écran vers le bas recharge toujours la fiche ;
- abonnement au calendrier : ouvert dans un navigateur, le lien affiche une
  page qui mène à l'abonnement au lieu de proposer « Ajouter tous les
  événements », une copie unique qui ne se mettait jamais à jour. Pour Apple
  Calendrier, le lien copié est désormais un lien d'abonnement (webcal) ;
- abonnement au calendrier sur iPhone : le bouton « Apple Calendrier » ouvre
  l'abonnement dans la page en cours et tout de suite, avant de copier le
  lien. Ouvert jusqu'ici dans une nouvelle fenêtre après la copie, il pouvait
  être bloqué par Safari sans aucun message. Si l'abonnement ne s'affiche
  pas, le message propose d'ouvrir la page d'abonnement. Outlook s'ouvre
  depuis le bouton du message, une fois le lien copié. Si l'appareil refuse
  la copie du lien, un message le dit et mène à la page d'abonnement au lieu
  de ne rien afficher. Plusieurs appuis rapides n'empilent plus les fenêtres
  de choix ;
- tableaux (Statistiques, Prono…) : la flèche de tri disparaît de la colonne
  sélectionnée, signalée seulement par la couleur de son libellé ;
- notifications de disponibilité (ouverture, relance, match reporté) : elles
  ouvrent le calendrier directement sur la carte du match, là où se choisit
  Présent / Absent, au lieu de l'onglet Effectif de la fiche du match ;
- badge « Traître » : décerné seulement si l'AS Grinta perd réellement, comme
  l'annonce sa description (« … et avoir raison »). La règle comptait jusqu'ici
  tout pronostic de défaite, même faux ; le badge attribué ainsi à tort est
  retiré ;
- badge « Triplé Chrono » : décerné automatiquement à qui marque trois buts
  ou plus dans la même mi-temps (mi-temps notée par le Live, sinon déduite de
  la minute) ; les matchs déjà validés sont rattrapés ;
- notifications : chacune ouvre l'écran qu'elle annonce. Convocation,
  composition en ligne, résultat Homme du match, badges débloqués et
  changement de disponibilité (admin) ouvraient jusqu'ici l'accueil ;
- « Francois » devient « François » sur le profil, l'effectif, l'identité du
  joueur et les statistiques d'archives ; l'identifiant de connexion ne change
  pas ;
- Statistiques → Prono : nouvelle colonne « Prono » (pronostics remplis sur
  les matchs terminés) avant « Bons », et points centrés ;
- fiche d'un match à venir : « 5 dernières rencontres » devient « Dernières
  rencontres », et la date de chaque rencontre passe en blanc (Info et
  Prono), le score et le cadre gardant la couleur du résultat ;
- Live : seul le coach de la saison pilote. Il arrive directement sur le
  pilotage, sans la barre « Spectateur | Piloter » ; tous les autres,
  administrateurs compris, arrivent directement en spectateur. Le serveur
  refuse la place de pilote à tout autre profil ;
- compte rendu : un coach qui n'est pas administrateur peut de nouveau le
  valider après le Live (la validation échouait sur un contrôle réservé aux
  administrateurs) ;
- fiche du match : « Faits du match » adopte la présentation des sites de
  résultats (minute au bord, pastille ⚽ avec le score, buteur puis
  passeur entre parenthèses en gris, buts adverses en miroir à droite) ;
- statistiques d'équipe : le graphique « Écart de score » regroupe les écarts
  par tranches de 3 buts (1-3, 4-6, 7-9, 10 et plus) au lieu de 1 en 1, pour
  que les larges victoires ne s'entassent plus dans une seule colonne ;
- écran Badges : retrait des phrases d'explication et des barres de recherche
  dans les onglets Mystères (Manuel et Automatique) et Communs ;
- archives : les 15 matchs joués avec Samih qui n'avaient qu'une liste de
  présents affichent désormais une composition reconstituée (formation des
  matchs voisins, joueurs à leur poste habituel, postes vides quand l'effectif
  était incomplet) ;
- notifications sur Android : la petite icône de la barre d'état montre la
  silhouette du blason au lieu d'un carré blanc ou noir ;
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
- calendrier : le score a la même taille que les noms d'équipes, sur la même
  ligne ; les cartes sont plus aérées (plus d'espace entre les lignes d'une
  carte et entre deux cartes).
- calendrier : les noms d'équipes gardent toujours leur taille normale et
  passent à la ligne s'ils ne tiennent pas ; chaque équipe est à la même
  distance du score.
- paramètres : les sous-titres « Déclarer une période d’absence »
  (Indisponibilité) et « Adversaires, stades et adresses » (Équipes & stades)
  sont retirés.
- calendrier : un nom d'équipe sur plusieurs lignes est centré sur lui-même ;
  le type (Amical, Championnat · J20, Événement…) suit l'heure sur la ligne de
  la date ; l'icône devant l'adresse est retirée.
- calendrier : un nom d'équipe trop long est réparti sur des lignes de
  longueur équilibrée (« TOAC Foot / Loisir 2 » au lieu d'un « 2 » seul en
  dessous).
- calendrier : chaque nom d'équipe est centré dans sa moitié de carte (comme
  les boutons Présent / Absent), l'écusson d'AS Grinta restant côté extérieur.
- calendrier : nouvelles couleurs (bleu marine championnat, bleu clair amical,
  violet match entre nous, or événement) ; chaque carte est découpée en trois
  zones, avec la date et l'adresse dans des bandeaux plus foncés.
- calendrier : le championnat repasse en bleu (au lieu de bleu marine),
  l'amical s'éclaircit pour rester distinct, et le score a la même épaisseur
  visuelle que les noms d'équipes.
- calendrier « Par mois » : la saison se choisit avec des flèches gauche/droite,
  comme le mois, au lieu d'un menu déroulant ; nom centré, sans icône ni
  intitulé « Saison ».
- calendrier : les matchs amicaux passent au bleu #153D66.
- paramètres : une carte du compte (photo, nom, identifiant, rôle) remplace
  la ligne « Profil » et ouvre le profil ; les réglages sont regroupés en
  « Mon compte » et « Club · admin » (admins seulement), une seule carte par
  groupe ; « Se déconnecter » est aussi proposé en bas des paramètres, avec
  la même confirmation que dans le profil.

### Performance

- les tâches planifiées chaque minute (ouverture/fermeture des disponibilités,
  fin des matchs internes) ne déclenchent plus le signal de synchronisation
  quand elles n'ont rien à faire : les applications ouvertes ne rechargent
  plus toutes leurs données à chaque minute ronde. Voir
  `docs/changes/idle-cron-shared-data-signal.md`.

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
