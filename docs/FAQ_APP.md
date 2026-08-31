# FAQ AS Grinta — base de référence de l’application

> **Statut :** source éditoriale destinée à alimenter la future FAQ intégrée à l’application.  
> **Audit de référence :** 31 août 2026.  
> **Code audité :** `main` au commit `0558748cffab1abab8813a9477d5600f8d087aa2`.  
> **Production auditée :** Supabase `AS-Grinta`, 552 migrations, dernière version `20260831012022`.  
> **Principe :** lorsque le code, une ancienne migration et la production divergent, le comportement réellement déployé en production prévaut.

## Convention d’intégration

Chaque question possède un identifiant stable et une audience :

- `Tous` : tout membre actif ;
- `Utilisateur` : compte actif standard / pronostiqueur ;
- `Joueur` : personne présente dans l’effectif sportif, éventuellement liée à un compte ;
- `Coach` : joueur actif de l’effectif marqué comme coach ;
- `Admin` : compte administrateur actif.

Les réponses doivent rester compréhensibles sans vocabulaire technique. Les détails d’exploitation placés dans la dernière section sont destinés principalement aux administrateurs.

---

# 1. Général

### FAQ-GEN-001 — À quoi sert AS Grinta ?
**Audience : Tous**

AS Grinta centralise la vie sportive du groupe : matchs, calendrier, disponibilités, effectifs, convocations, compositions, Live, compte rendu, Homme du match, pronostics, classements, statistiques, badges, profils, notifications et historique des saisons.

### FAQ-GEN-002 — Est-ce une application mobile native ?
**Audience : Tous**

AS Grinta est une application Flutter Web installable comme PWA. Elle peut être utilisée depuis le navigateur et ajoutée à l’écran d’accueil sur les appareils compatibles.

### FAQ-GEN-003 — Quelle heure fait foi dans l’application ?
**Audience : Tous**

Les échéances métier importantes sont calculées avec l’heure `Europe/Paris`, notamment l’ouverture des disponibilités et des pronostics ainsi que la fermeture à T-15.

### FAQ-GEN-004 — Pourquoi certaines fonctions n’apparaissent-elles pas ?
**Audience : Tous**

L’affichage dépend de ton statut, de ton rôle, de ton lien éventuel avec l’effectif, de l’état du match et des fonctions activées. Une action sensible n’est jamais autorisée uniquement parce qu’un bouton est visible : le serveur revérifie aussi les droits.

### FAQ-GEN-005 — Un ancien lien peut-il encore fonctionner ?
**Audience : Tous**

Oui. Plusieurs anciennes routes redirigent vers les écrans actuels afin de conserver la compatibilité avec d’anciens favoris ou liens partagés.

### FAQ-GEN-006 — L’application utilise-t-elle des données historiques ?
**Audience : Tous**

Oui. Les matchs et statistiques historiques sont conservés séparément des matchs modernes. Ils alimentent l’historique et certaines statistiques sans créer artificiellement de pronostics, disponibilités, compositions ou Live.

---

# 2. Inscription, connexion et compte

### FAQ-AUTH-001 — Comment créer un compte ?
**Audience : Tous**

Utilise l’écran d’inscription, renseigne les informations demandées et choisis un mot de passe conforme aux règles affichées. Le compte est créé en attente de validation.

### FAQ-AUTH-002 — Pourquoi mon compte est-il « en attente » ?
**Audience : Utilisateur**

Une nouvelle inscription doit être validée par un administrateur. Tant que le profil n’est pas actif, l’accès métier à l’application reste bloqué.

### FAQ-AUTH-003 — Puis-je accéder à l’application avant validation ?
**Audience : Utilisateur**

Non. Une session peut techniquement exister après l’inscription, mais le compte reste limité à l’écran d’attente jusqu’à son activation.

### FAQ-AUTH-004 — Que se passe-t-il dès que mon compte est validé ?
**Audience : Utilisateur**

Le routeur recharge l’état du profil et donne accès aux écrans correspondant au rôle actif, sans qu’une manipulation particulière soit nécessaire au-delà d’un éventuel rafraîchissement si le navigateur ne l’a pas déjà fait.

### FAQ-AUTH-005 — J’ai oublié mon mot de passe. Que faire ?
**Audience : Tous**

Utilise le parcours de récupération de mot de passe. Le lien de récupération ouvre l’écran prévu pour définir un nouveau mot de passe.

### FAQ-AUTH-006 — Pourquoi l’application m’oblige-t-elle à changer mon mot de passe ?
**Audience : Utilisateur**

Un administrateur ou un flux de sécurité peut marquer le compte comme nécessitant un changement de mot de passe. Tant que le nouveau mot de passe n’est pas enregistré, les autres écrans restent bloqués.

### FAQ-AUTH-007 — Mon mot de passe est-il stocké dans les tables de l’application ?
**Audience : Tous**

Non. L’authentification et les mots de passe sont gérés par Supabase Auth. Les tables métier d’AS Grinta ne stockent pas les mots de passe en clair.

### FAQ-AUTH-008 — Puis-je avoir un compte sans être joueur de l’effectif ?
**Audience : Tous**

Oui. Le compte applicatif et l’identité sportive sont deux notions distinctes. Un profil peut être pronostiqueur sans être joueur actif de l’effectif.

### FAQ-AUTH-009 — Un joueur peut-il être lié à un compte ?
**Audience : Tous**

Oui. Un joueur de l’effectif peut être relié à un profil afin d’associer correctement son identité, sa photo, ses statistiques et certaines expériences personnalisées.

### FAQ-AUTH-010 — Que signifie un compte archivé ?
**Audience : Tous**

Un compte archivé n’est plus un compte actif pour les opérations courantes. Ses participations historiques peuvent toutefois rester visibles lorsque cela est nécessaire pour préserver les classements et l’historique.

---

# 3. Rôles et permissions

### FAQ-ROLE-001 — Quels sont les rôles visibles dans l’application ?
**Audience : Tous**

Les deux rôles principaux sont `Utilisateur` / pronostiqueur et `Admin`. L’administration complète est réservée aux administrateurs actifs.

### FAQ-ROLE-002 — Être gardien donne-t-il des droits supplémentaires ?
**Audience : Joueur**

Non. Gardien est un attribut sportif utilisé pour l’effectif, les statistiques et certains pronostics/badges. Ce n’est pas un rôle d’administration.

### FAQ-ROLE-003 — Être coach donne-t-il des droits supplémentaires ?
**Audience : Coach**

Oui, mais uniquement dans le périmètre sportif prévu. Un joueur actif marqué comme coach pour la saison peut piloter les opérations Live autorisées pour les matchs de cette saison. Cela ne lui ouvre pas automatiquement les pages générales d’administration, de gestion des comptes ou de badges.

### FAQ-ROLE-004 — Un utilisateur peut-il ouvrir directement une URL Admin ?
**Audience : Utilisateur**

Non. Le routeur redirige les comptes non autorisés et le serveur revérifie les droits sur les opérations sensibles.

### FAQ-ROLE-005 — Un utilisateur non connecté peut-il lire les données du club ?
**Audience : Tous**

Non. Les tables, vues et RPC métier ne sont pas accessibles anonymement. Il faut un profil authentifié et autorisé.

### FAQ-ROLE-006 — Pourquoi une action peut-elle être refusée alors que le bouton était visible ?
**Audience : Tous**

L’interface n’est pas la barrière de sécurité finale. Le serveur contrôle à nouveau le rôle, l’état du profil, l’état du match et les échéances au moment de l’enregistrement.

---

# 4. Navigation, installation et fonctionnement hors ligne

### FAQ-PWA-001 — Puis-je installer AS Grinta sur mon téléphone ?
**Audience : Tous**

Oui, sur les navigateurs compatibles avec l’installation PWA. L’installation exacte dépend du système et du navigateur.

### FAQ-PWA-002 — Puis-je utiliser l’application sans réseau ?
**Audience : Tous**

Certaines ressources déjà chargées peuvent rester disponibles grâce au cache PWA, mais une action qui doit modifier la base nécessite une connexion. Ne considère jamais une modification comme enregistrée tant que l’application n’a pas confirmé son succès.

### FAQ-PWA-003 — Que faire si une page reste sur un ancien état ?
**Audience : Tous**

Rafraîchis la page puis vérifie la connexion. Les données autoritaires sont rechargées depuis Supabase et plusieurs modules reçoivent aussi des signaux Realtime de rafraîchissement.

### FAQ-PWA-004 — Les boutons Retour du navigateur sont-ils supportés ?
**Audience : Tous**

Oui. La navigation est conçue pour fonctionner avec l’historique du navigateur et des traitements spécifiques évitent certains artefacts connus de WebKit sur iOS/macOS.

### FAQ-PWA-005 — Pourquoi un lien profond m’envoie-t-il vers la connexion ?
**Audience : Tous**

Parce que la page demandée nécessite une session. Après authentification, l’application essaie de restaurer la destination locale demandée lorsqu’elle est sûre et compatible.

---

# 5. Matchs et calendrier

### FAQ-MATCH-001 — Quels types de matchs existent ?
**Audience : Tous**

L’application distingue notamment les matchs amicaux, les matchs de championnat et les matchs `entre nous`.

### FAQ-MATCH-002 — Quels statuts un match peut-il avoir ?
**Audience : Tous**

Un match moderne peut notamment être à venir, terminé, archivé ou annulé. Les transitions ne sont pas de simples modifications de texte : elles suivent le workflow métier du match.

### FAQ-MATCH-003 — Où voir le prochain match ?
**Audience : Tous**

L’écran Matchs met en avant le prochain match pertinent et permet d’ouvrir son détail, son pronostic et les modules sportifs accessibles.

### FAQ-MATCH-004 — Où voir les anciens matchs ?
**Audience : Tous**

Le calendrier et l’historique donnent accès aux matchs des saisons précédentes ainsi qu’aux anciens résultats importés.

### FAQ-MATCH-005 — Pourquoi certains anciens matchs ont-ils moins de détails ?
**Audience : Tous**

Les imports historiques ne disposent pas toujours des mêmes données que les matchs modernes. Seules les informations vérifiées et disponibles sont affichées.

### FAQ-MATCH-006 — Quelle différence entre « annulé » et « supprimé » ?
**Audience : Admin**

Annuler conserve l’existence métier du match avec un statut d’annulation. Supprimer efface le match moderne et ses données associées. Ce sont donc deux opérations très différentes.

### FAQ-MATCH-007 — Jusqu’à quand un administrateur peut-il annuler un match ?
**Audience : Admin**

L’annulation normale est réservée à un match encore `à venir` et doit intervenir avant le verrou T-15 / ouverture du Live.

### FAQ-MATCH-008 — Jusqu’à quand un administrateur peut-il supprimer un match ?
**Audience : Admin**

La suppression est limitée à la fenêtre autorisée par le serveur et n’est plus possible à partir de 24 heures après le coup d’envoi.

### FAQ-MATCH-009 — Puis-je modifier la date ou l’heure d’un match ?
**Audience : Admin**

Oui tant que le workflow l’autorise. Une modification peut recalculer les échéances, rouvrir certains états et déclencher le traitement prévu pour les disponibilités et notifications.

### FAQ-MATCH-010 — Que se passe-t-il si la date change ?
**Audience : Tous**

Lorsque la date change et que les disponibilités doivent être redemandées, elles peuvent être remises à `sans réponse`. Le système traite ensuite le match selon sa nouvelle chronologie.

### FAQ-MATCH-011 — Que se passe-t-il si seule l’heure change ?
**Audience : Tous**

Les disponibilités existantes sont conservées selon le contrat actuel, tandis que les échéances temporelles du match sont recalculées.

### FAQ-MATCH-012 — Le lieu du match est-il mémorisé ?
**Audience : Tous**

Oui. Le match peut avoir sa propre adresse. À domicile l’adresse du club peut servir de référence et, à l’extérieur, l’adresse mémorisée de l’adversaire peut être réutilisée.

### FAQ-MATCH-013 — L’heure de rendez-vous peut-elle être différente du coup d’envoi ?
**Audience : Tous**

Oui. Le match possède une heure de rendez-vous. Lorsqu’aucune valeur spécifique n’est définie, le comportement par défaut correspond au rendez-vous prévu avant le coup d’envoi.

### FAQ-MATCH-014 — Un match de championnat peut-il avoir une journée ?
**Audience : Tous**

Oui. La journée de championnat peut être enregistrée et corrigée afin d’enrichir le calendrier et l’historique.

---

# 6. Disponibilités

### FAQ-AVA-001 — Quand les disponibilités ouvrent-elles ?
**Audience : Joueur**

Le cycle standard ouvre les disponibilités à J-6 à 12 h, heure Europe/Paris.

### FAQ-AVA-002 — Quels choix puis-je faire ?
**Audience : Joueur**

Selon le workflow du match, un joueur peut répondre disponible ou absent. Tant qu’aucune réponse n’a été enregistrée, son état reste `sans réponse`.

### FAQ-AVA-003 — Puis-je modifier ma disponibilité ?
**Audience : Joueur**

Oui pendant la fenêtre autorisée. Une fois le match verrouillé, les changements ordinaires sont refusés et les éventuelles corrections passent par les outils du staff.

### FAQ-AVA-004 — Puis-je préciser pourquoi je suis absent ?
**Audience : Joueur**

Oui lorsque l’interface propose le commentaire d’absence. Ce commentaire est privé : il n’est pas destiné à être visible publiquement par les autres joueurs.

### FAQ-AVA-005 — Qui peut voir mon commentaire d’absence ?
**Audience : Joueur**

Il est réservé au joueur concerné et au staff autorisé par les règles serveur.

### FAQ-AVA-006 — Y a-t-il encore des rappels automatiques J-3 et J-1 ?
**Audience : Tous**

Non. Ces rappels automatiques ont été retirés. Le staff peut toutefois envoyer un rappel manuel de disponibilité.

### FAQ-AVA-007 — Les disponibilités dépendent-elles du fonctionnement des notifications ?
**Audience : Tous**

Non. Les transitions de disponibilité continuent même si les notifications Push sont temporairement suspendues.

### FAQ-AVA-008 — Pourquoi ma disponibilité est-elle revenue à « sans réponse » ?
**Audience : Joueur**

Une modification importante du match, en particulier un changement de date qui nécessite de redemander les disponibilités, peut réinitialiser les réponses.

---

# 7. Liste d’attente, effectif et convocations

### FAQ-SQUAD-001 — Quelle différence entre disponibilité, effectif et convocation ?
**Audience : Tous**

La disponibilité indique si un joueur peut venir. L’Effectif correspond au groupe retenu/organisé pour le match. La convocation formalise ensuite les joueurs convoqués selon le workflow sportif.

### FAQ-SQUAD-002 — Pourquoi suis-je en liste d’attente alors que je suis disponible ?
**Audience : Joueur**

Le nombre de places peut être limité et la rotation de la liste d’attente utilise les règles de la saison. Être disponible ne garantit donc pas automatiquement une place dans le groupe final.

### FAQ-SQUAD-003 — La liste d’attente repart-elle de zéro à chaque match ?
**Audience : Joueur**

Non. Elle s’appuie sur un ordre et un historique de rotation liés à la saison afin de conserver une logique d’équité dans le temps.

### FAQ-SQUAD-004 — L’administrateur peut-il intervenir sur la liste d’attente ?
**Audience : Admin**

Oui. Les outils de gestion permettent de contrôler l’ordre, le nombre de places et les décisions prévues par le workflow, avec les garde-fous serveur correspondants.

### FAQ-SQUAD-005 — Puis-je consulter la liste d’attente sans être Admin ?
**Audience : Utilisateur**

Une vue en lecture seule existe pour les profils autorisés. Les actions de modification restent réservées au staff.

### FAQ-SQUAD-006 — Que se passe-t-il lorsqu’une place se libère ?
**Audience : Joueur**

Le workflow peut promouvoir un joueur de la liste d’attente vers les convoqués selon les règles en vigueur. Si la préférence correspondante est activée et que les Push sont autorisés, une notification peut être envoyée.

### FAQ-SQUAD-007 — L’effectif se fige-t-il avant le match ?
**Audience : Tous**

Oui. Le cycle actuel verrouille les changements prématch ordinaires à T-15.

### FAQ-SQUAD-008 — Peut-on ajouter quelqu’un après T-15 ?
**Audience : Coach, Admin**

Le Live prévoit un flux spécifique pour ajouter tardivement un joueur ou un invité lorsque le match est déjà dans son espace Live. Cette personne est intégrée avec une base de banc afin de ne pas modifier rétroactivement la composition de départ.

### FAQ-SQUAD-009 — Un joueur déclaré absent peut-il quand même être sélectionné par le staff ?
**Audience : Admin**

Le système permet au staff de prendre certaines décisions d’effectif indépendamment de la réponse brute de disponibilité lorsque le workflow l’exige, tout en conservant la traçabilité des états.

---

# 8. Composition classique

### FAQ-COMPO-001 — Quelle différence entre Effectif et Composition ?
**Audience : Tous**

L’Effectif détermine qui fait partie du groupe. La Composition organise ensuite les joueurs retenus sur le terrain, le banc et les autres zones prévues.

### FAQ-COMPO-002 — La composition est-elle automatiquement enregistrée pendant que je la déplace ?
**Audience : Admin**

Non. La simulation peut être modifiée librement à l’écran ; l’état métier n’est enregistré que lorsque l’action d’enregistrement prévue est utilisée.

### FAQ-COMPO-003 — Les positions proposées sont-elles aléatoires ?
**Audience : Admin**

Non. La simulation peut utiliser les positions de référence et l’historique récent des titulaires/banc pour proposer une base cohérente, qui reste modifiable.

### FAQ-COMPO-004 — Quand la composition se fige-t-elle ?
**Audience : Tous**

Les modifications prématch ordinaires sont verrouillées à T-15. Le Live prend ensuite le relais pour la composition réellement jouée.

### FAQ-COMPO-005 — Une composition publiée peut-elle être différente de la composition réelle ?
**Audience : Tous**

Oui. La publication représente la composition annoncée à un instant donné ; le Live enregistre ensuite les changements réellement effectués pendant le match.

### FAQ-COMPO-006 — Les anciennes publications sont-elles écrasées ?
**Audience : Tous**

Le système conserve des snapshots de publication afin de préserver l’historique plutôt que de transformer silencieusement une publication passée.

### FAQ-COMPO-007 — Que se passe-t-il si deux personnes modifient la composition en même temps ?
**Audience : Admin, Coach**

Le serveur utilise des révisions/versions pour détecter les modifications concurrentes. Si ta version est devenue obsolète, l’application doit recharger l’état récent avant un nouvel enregistrement.

---

# 9. Match « entre nous »

### FAQ-INT-001 — Qu’est-ce qu’un match « entre nous » ?
**Audience : Tous**

C’est un match interne au groupe, sans adversaire externe classique. Il possède un workflow spécifique pour répartir les joueurs entre deux équipes.

### FAQ-INT-002 — Y a-t-il des pronostics sur un match « entre nous » ?
**Audience : Tous**

Non. Les matchs `entre nous` sont exclus du parcours de pronostic afin de ne pas mélanger compétition de pronostics et match interne.

### FAQ-INT-003 — Comment affecter un joueur à une équipe ?
**Audience : Admin**

Dans l’éditeur interne, sélectionne le joueur puis la destination/équipe prévue. Les joueurs non affectés restent regroupés par familles de postes pour faciliter la répartition.

### FAQ-INT-004 — Puis-je remettre un joueur en « Non affectés » ?
**Audience : Admin**

Oui. Un joueur déjà placé peut être replacé dans la zone `Non affectés` tant que l’édition est encore autorisée.

### FAQ-INT-005 — À quoi servent les maillots d’équipe ?
**Audience : Tous**

Chaque équipe interne peut recevoir un maillot distinct afin de rendre la répartition immédiatement compréhensible. Le système évite les combinaisons incompatibles prévues par le workflow.

### FAQ-INT-006 — Puis-je réinitialiser la répartition ?
**Audience : Admin**

Oui. Une action de réinitialisation confirmée remet les affectations de joueurs à zéro tout en conservant les paramètres d’équipe prévus, puis l’état est sauvegardé via le flux normal.

### FAQ-INT-007 — Jusqu’à quand puis-je modifier les équipes ?
**Audience : Admin**

Les modifications de composition interne sont verrouillées à T-15. Le serveur bloque aussi les écritures directes qui tenteraient de contourner cette limite.

### FAQ-INT-008 — Pourquoi les joueurs sont-ils regroupés en Gardiens, Défenseurs, Milieux, Attaquants ou Autre ?
**Audience : Tous**

Le regroupement utilise les informations de poste disponibles pour rendre l’affectation plus rapide. `Autre` sert de repli lorsqu’un profil ne correspond pas proprement aux groupes principaux.

---

# 10. Live du match

### FAQ-LIVE-001 — Quand le Live devient-il disponible ?
**Audience : Coach, Admin**

Le Live prend le relais autour du verrou T-15 et du démarrage du match, selon l’état du workflow. Les opérations serveur refusent les actions incohérentes avec la chronologie réelle.

### FAQ-LIVE-002 — Qui peut piloter le Live ?
**Audience : Coach, Admin**

Un administrateur actif peut le piloter. Un joueur actif marqué comme coach pour la saison peut également utiliser les commandes Live autorisées pour les matchs de cette saison.

### FAQ-LIVE-003 — Le Coach peut-il pour autant gérer les comptes ou les badges ?
**Audience : Coach**

Non. Ses droits Live ne transforment pas son compte en administrateur général.

### FAQ-LIVE-004 — Que peut enregistrer le Live ?
**Audience : Coach, Admin**

Le Live gère notamment l’horloge, les scores, les buts, les buteurs, les passes décisives, les buts contre son camp adverses, les remplacements, la composition réellement jouée et certains changements de dispositif.

### FAQ-LIVE-005 — Puis-je démarrer le Live sans composition publiée ?
**Audience : Coach, Admin**

Oui lorsque le workflow actuel le permet. Le serveur construit alors l’état Live à partir des informations disponibles plutôt que de bloquer systématiquement le match.

### FAQ-LIVE-006 — Puis-je modifier la composition juste avant le coup d’envoi ?
**Audience : Coach, Admin**

Le Live possède un flux spécifique de composition réelle qui tient compte du verrou prématch. Les modifications doivent passer par les opérations Live prévues.

### FAQ-LIVE-007 — Comment ajouter un but ?
**Audience : Coach, Admin**

Utilise la commande de score du Live puis attribue le buteur lorsque c’est applicable. Les opérations de score sont protégées contre le double envoi grâce à un identifiant d’opération.

### FAQ-LIVE-008 — Puis-je renseigner le buteur plus tard ?
**Audience : Coach, Admin**

Oui. Un événement de but peut être complété ensuite avec son buteur tant que le Live n’a pas franchi l’état qui interdit cette correction.

### FAQ-LIVE-009 — Puis-je ajouter une passe décisive ?
**Audience : Coach, Admin**

Oui sur un but de notre équipe lorsque les conditions sont valides. Le passeur ne peut pas être le buteur du même but et un but contre son camp adverse n’a pas de passe décisive attribuée.

### FAQ-LIVE-010 — Comment enregistrer un remplacement ?
**Audience : Coach, Admin**

La composition Live enregistre le joueur qui entre et celui qui sort. Les changements sont versionnés afin d’éviter qu’une modification concurrente écrase une autre.

### FAQ-LIVE-011 — Puis-je changer de formation sans faire un remplacement ?
**Audience : Coach, Admin**

Oui. Un changement de dispositif peut réorganiser les positions sans inventer artificiellement un événement de remplacement.

### FAQ-LIVE-012 — Puis-je mettre le chrono en pause ?
**Audience : Coach, Admin**

Oui. Les états prévus comprennent notamment en cours, pause et mi-temps. Le serveur valide que l’action demandée est compatible avec l’état actuel.

### FAQ-LIVE-013 — Que fait la mi-temps ?
**Audience : Coach, Admin**

Elle change l’état de l’horloge et conserve un temps cohérent avec la durée prévue du match. La seconde période dispose ensuite de son action de reprise.

### FAQ-LIVE-014 — Puis-je supprimer un événement Live saisi par erreur ?
**Audience : Coach, Admin**

Oui tant que le compte rendu n’a pas été exporté/finalisé de manière irréversible pour cet événement. Le serveur recalcule les informations dépendantes afin de garder score et chronologie cohérents.

### FAQ-LIVE-015 — Puis-je rouvrir un Live terminé ?
**Audience : Coach, Admin**

Oui seulement tant que le Live terminé n’a pas encore été exporté vers le compte rendu final. Une fois exporté, il ne peut plus être rouvert par ce flux.

### FAQ-LIVE-016 — À quoi sert « Recommencer le Live » ?
**Audience : Coach, Admin**

Cette action remet le Live dans un état de reprise contrôlé lorsque le workflow l’autorise. Elle ne doit pas être utilisée après export définitif du compte rendu.

### FAQ-LIVE-017 — Que se passe-t-il si deux coachs enregistrent en même temps ?
**Audience : Coach, Admin**

Les révisions de composition et l’idempotence des commandes de score protègent contre les écrasements silencieux et les doublons. Une révision devenue obsolète doit être rechargée.

---

# 11. Compte rendu, finalisation et corrections

### FAQ-REPORT-001 — Quand le match devient-il officiellement terminé ?
**Audience : Tous**

Le match moderne est finalisé par le workflow post-match, directement ou via l’export du récapitulatif Live. Les scores et statistiques sont alors enregistrés de manière cohérente.

### FAQ-REPORT-002 — Qui peut utiliser l’écran final de compte rendu ?
**Audience : Admin**

La route générale de finalisation est réservée aux administrateurs. Un coach peut contribuer au flux Live autorisé, mais n’obtient pas pour autant la page d’administration de finalisation.

### FAQ-REPORT-003 — Quelles informations sont finalisées ?
**Audience : Admin**

Le compte rendu consolide notamment le score, les présences réelles, les buts, les passes décisives, les clean sheets et la composition réellement jouée selon les données disponibles.

### FAQ-REPORT-004 — Puis-je corriger un match après validation ?
**Audience : Admin**

Oui dans la fenêtre de correction prévue par le workflow. Les corrections importantes sont versionnées afin de conserver la cohérence des statistiques et des traitements dépendants.

### FAQ-REPORT-005 — Que deviennent les statistiques après une correction ?
**Audience : Tous**

Les vues et traitements de statistiques utilisent les données validées les plus récentes. Une correction autorisée doit donc se refléter dans les statistiques et éléments dérivés concernés.

### FAQ-REPORT-006 — Puis-je enlever uniquement les « Faits du match » après une mauvaise manipulation Live ?
**Audience : Admin**

Oui. Un flux spécifique permet de supprimer les faits/timeline Live sans modifier automatiquement le score final, les statistiques validées, la composition finale ou le résultat Homme du match.

### FAQ-REPORT-007 — Qu’est-ce qu’une version de finalisation ?
**Audience : Admin**

C’est un snapshot immuable du compte rendu validé à un instant donné. Il permet de distinguer la validation initiale des corrections suivantes.

### FAQ-REPORT-008 — Quand puis-je archiver un match ?
**Audience : Admin**

Seul un match terminé peut être archivé via le workflow prévu.

---

# 12. Homme du match (HDM)

### FAQ-MOTM-001 — Quand ouvre le vote Homme du match ?
**Audience : Tous**

Le vote ouvre après la validation du match. La date de validation du compte rendu sert d’ancre au scrutin.

### FAQ-MOTM-002 — Combien de temps le vote reste-t-il ouvert ?
**Audience : Tous**

24 heures exactement à partir de la validation qui ouvre le scrutin.

### FAQ-MOTM-003 — Qui peut voter ?
**Audience : Joueur**

Le workflow autorise les profils concernés par le match selon les règles de présence et d’éligibilité actuelles.

### FAQ-MOTM-004 — Pour qui puis-je voter ?
**Audience : Joueur**

La liste des candidats est construite à partir des participants éligibles réellement présents selon le compte rendu.

### FAQ-MOTM-005 — Mon vote est-il anonyme ?
**Audience : Tous**

Oui du point de vue de l’application. Les bulletins ne sont pas directement lisibles par les utilisateurs ni par les administrateurs ordinaires ; l’application expose le résultat agrégé, pas l’identité des votants.

### FAQ-MOTM-006 — Puis-je modifier mon vote ?
**Audience : Joueur**

Le bulletin est conçu comme un vote unique et immuable pour le scrutin concerné. Vérifie donc ton choix avant validation.

### FAQ-MOTM-007 — Que se passe-t-il en cas d’égalité ?
**Audience : Tous**

L’égalité est un résultat valide. Plusieurs joueurs peuvent être déclarés co-Hommes du match.

### FAQ-MOTM-008 — Un invité peut-il être élu ?
**Audience : Tous**

Oui s’il est éligible comme participant du match. Un invité sans compte peut apparaître dans le résultat mais ne peut évidemment pas recevoir une notification personnelle sur un compte inexistant.

### FAQ-MOTM-009 — Puis-je désactiver les notifications HDM ?
**Audience : Utilisateur**

Oui. Le même réglage couvre actuellement la notification d’ouverture et celle du résultat.

### FAQ-MOTM-010 — Y a-t-il un rappel juste avant la fermeture ?
**Audience : Tous**

Non. L’ancien rappel avant fermeture a été retiré.

---

# 13. Pronostics de match

### FAQ-PRM-001 — Quand puis-je pronostiquer un match ?
**Audience : Utilisateur**

La fenêtre actuelle commence à J-6 à 12 h et se ferme à T-15, heure Europe/Paris, pour les matchs éligibles.

### FAQ-PRM-002 — Puis-je modifier mon pronostic ?
**Audience : Utilisateur**

Oui pendant la fenêtre ouverte. Après T-15, le serveur refuse toute modification ordinaire.

### FAQ-PRM-003 — Les autres voient-ils mon pronostic avant le résultat ?
**Audience : Utilisateur**

Non. Les pronostics sont protégés avant leur révélation selon le workflow afin d’éviter de copier les choix des autres.

### FAQ-PRM-004 — Peut-on pronostiquer un match « entre nous » ?
**Audience : Tous**

Non. Ce type de match est exclu des pronostics.

### FAQ-PRM-005 — Comment sont calculés les points d’un pronostic de match ?
**Audience : Tous**

Il faut d’abord avoir le bon résultat global : victoire AS Grinta, nul ou défaite. Si le résultat global est faux, le pronostic vaut 0. Sinon, la cote correspondant au résultat réel sert de base, puis un multiplicateur de précision est appliqué.

### FAQ-PRM-006 — Quel est le multiplicateur pour un score exact ?
**Audience : Tous**

Un score exact applique un multiplicateur ×2 à la cote du résultat réel.

### FAQ-PRM-007 — Et si je n’ai pas le score exact ?
**Audience : Tous**

Avec le bon résultat global, une différence de buts exacte ou le score exact d’une des deux équipes applique actuellement ×1,5. Sinon le bon résultat simple applique ×1.

### FAQ-PRM-008 — Le bonus/ticket ×2 existe-t-il encore ?
**Audience : Tous**

Non. L’ancien mécanisme de jeton ou bonus ×2 a été retiré. Le ×2 du score exact est simplement la règle normale de précision du barème actuel.

### FAQ-PRM-009 — D’où viennent les cotes ?
**Audience : Tous**

Ce sont des cotes internes calculées par AS Grinta à partir des données et de l’historique disponibles. Elles ne constituent pas des cotes de bookmaker ni un service de pari d’argent.

### FAQ-PRM-010 — Pourquoi mon pronostic n’apparaît-il pas dans les points ?
**Audience : Utilisateur**

Les points nécessitent un pronostic rempli sur un match terminé/archivé et une cote disponible pour ce match. Un match encore à venir ne produit pas encore de points définitifs.

### FAQ-PRM-011 — Y a-t-il un rappel automatique pour pronostiquer ?
**Audience : Utilisateur**

Si la préférence Pronostics est activée, un rappel peut être envoyé à J-5 à 12 h lorsqu’aucun pronostic n’est rempli. Aucun rappel n’est envoyé après T-15.

---

# 14. Pronostics de saison

### FAQ-PRS-001 — Que pronostique-t-on sur la saison ?
**Audience : Utilisateur**

Le module prévoit notamment les buts des joueurs de champ et les clean sheets des gardiens selon l’effectif figé pour la compétition de pronostics.

### FAQ-PRS-002 — Pourquoi les valeurs sont-elles pensées sur une base de 30 matchs ?
**Audience : Tous**

Pendant une saison non archivée, les performances courantes sont projetées sur 30 matchs afin de comparer les pronostics sur une base stable. Une fois la saison archivée, la métrique finale réelle sert de référence.

### FAQ-PRS-003 — Dois-je remplir toute la grille ?
**Audience : Utilisateur**

Oui pour être éligible au calcul complet actuel : la grille attendue doit être entièrement remplie pour que ses lignes entrent dans le classement de saison.

### FAQ-PRS-004 — L’effectif de référence peut-il changer après le verrouillage ?
**Audience : Tous**

Le système capture un roster de référence au verrouillage afin qu’une activation/désactivation ultérieure d’un joueur ne réécrive pas rétroactivement la compétition.

### FAQ-PRS-005 — Comment sont calculés les points de proximité ?
**Audience : Tous**

Pour chaque joueur/catégorie, les pronostiqueurs sont classés par distance à la valeur cible. Avec `N` participants, le meilleur rang reçoit le plus de blocs de 3 points et les rangs suivants décroissent ; une valeur exacte double les points de cette ligne.

### FAQ-PRS-006 — Que se passe-t-il en cas d’égalité de proximité ?
**Audience : Tous**

Le calcul serveur utilise un rang de compétition : des distances identiques partagent le même rang.

### FAQ-PRS-007 — Existe-t-il un bonus sur l’ordre des buteurs ?
**Audience : Tous**

Oui. Le classement de saison peut ajouter un bonus récompensant la qualité de l’ordre relatif prévu entre les buteurs. Il devient positif lorsque plus de la moitié des comparaisons d’ordre sont correctes et il est plafonné par le nombre de participants.

### FAQ-PRS-008 — Quand les pronostics de saison sont-ils révélés ?
**Audience : Tous**

Ils sont protégés jusqu’au verrouillage prévu par la saison, puis deviennent exploitables dans les vues de classement selon les règles de révélation.

---

# 15. Classements

### FAQ-RANK-001 — Quels classements existent ?
**Audience : Tous**

L’application distingue les performances de pronostics de matchs, les pronostics de saison et le classement général qui les combine, en plus des classements/statistiques sportives.

### FAQ-RANK-002 — Comment est calculé le classement général des pronostics ?
**Audience : Tous**

Le calcul serveur actuel additionne `points de matchs × 100` et `points de saison` pour produire le total général.

### FAQ-RANK-003 — Les comptes de test apparaissent-ils dans les classements ?
**Audience : Tous**

Non. Les comptes marqués comme comptes de test sont exclus des classements et des titres concernés.

### FAQ-RANK-004 — Un ancien membre archivé disparaît-il de tout l’historique ?
**Audience : Tous**

Non. Un vrai profil archivé qui a effectivement participé peut rester éligible à l’historique des classements, contrairement à un compte de test.

### FAQ-RANK-005 — Un match non terminé compte-t-il dans le classement ?
**Audience : Tous**

Non pour les points définitifs de pronostic match. Le calcul utilise les matchs terminés ou archivés.

### FAQ-RANK-006 — Pourquoi les totaux peuvent-ils évoluer après une correction de match ?
**Audience : Tous**

Une correction autorisée du résultat ou des statistiques peut modifier les données servant aux calculs. Les vues de classement reflètent alors la source de vérité corrigée.

---

# 16. Statistiques

### FAQ-STATS-001 — Quelles statistiques individuelles sont suivies ?
**Audience : Tous**

Selon la période et les données disponibles : matchs joués, buts, passes décisives, clean sheets, distinctions Homme du match et autres métriques dérivées utilisées par les classements et badges.

### FAQ-STATS-002 — Les passes décisives existent-elles sur tout l’historique ?
**Audience : Tous**

Non. La collecte des passes décisives a été introduite plus tard. Les anciens matchs qui ne disposaient pas de cette donnée ne doivent pas être interprétés comme une preuve qu’aucune passe décisive n’a réellement eu lieu.

### FAQ-STATS-003 — Quelles périodes puis-je consulter ?
**Audience : Tous**

Les vues prévoient notamment la saison courante, la saison précédente et des agrégats historiques/all-time selon la statistique.

### FAQ-STATS-004 — Les invités comptent-ils dans les statistiques ?
**Audience : Tous**

Un invité peut apparaître dans les faits d’un match et dans les données sportives lorsqu’il a réellement participé. L’identité canonique permet d’éviter de créer inutilement plusieurs personnes pour le même joueur lorsque les liens sont connus.

### FAQ-STATS-005 — Pourquoi deux noms historiques ont-ils été regroupés ?
**Audience : Tous**

L’application possède une identité joueur canonique et des alias/liens historiques. Lorsque deux variantes de nom correspondent à la même personne et que le lien est vérifié, les statistiques peuvent être réunies.

### FAQ-STATS-006 — Les statistiques historiques modifient-elles les matchs modernes ?
**Audience : Tous**

Non. Elles enrichissent les agrégats et l’historique sans créer de faux événements métier sur les anciens matchs.

---

# 17. Badges et Armoire

### FAQ-BADGE-001 — À quoi servent les badges ?
**Audience : Tous**

Les badges matérialisent des accomplissements, records, rôles ou faits particuliers. Ils peuvent être automatiques ou attribués manuellement selon leur définition.

### FAQ-BADGE-002 — Où voir mes badges ?
**Audience : Utilisateur**

Dans l’Armoire et sur les surfaces de profil prévues par l’application.

### FAQ-BADGE-003 — Puis-je mettre un badge en avant ?
**Audience : Utilisateur**

Oui lorsque le badge et l’écran le permettent. Le système applique la limite actuelle de badges mis en avant.

### FAQ-BADGE-004 — Un badge peut-il être secret ?
**Audience : Tous**

Oui. Certains badges sont conçus pour n’être découverts qu’au moment où ils sont obtenus.

### FAQ-BADGE-005 — Qui peut créer ou attribuer manuellement un badge ?
**Audience : Admin**

Le staff disposant du droit de modération/admin prévu peut créer certains badges manuels et attribuer ou révoquer les badges autorisés. Ces opérations sont journalisées côté serveur.

### FAQ-BADGE-006 — Une image de badge peut-elle être remplacée ?
**Audience : Admin**

Oui via le flux prévu. Les fichiers de badge sont limités aux formats et tailles acceptés par le stockage.

### FAQ-BADGE-007 — Un badge automatique déjà gagné peut-il disparaître après une simple correction d’historique ?
**Audience : Tous**

Le moteur a été durci pour préserver les badges déjà légitimement acquis dans plusieurs scénarios de reliaison historique. Les règles exactes restent celles du badge concerné.

---

# 18. Profil, joueurs, invités et photos

### FAQ-PROFILE-001 — Puis-je changer mon surnom ?
**Audience : Utilisateur**

Oui dans le périmètre de champs que ton profil est autorisé à modifier. Les champs sensibles restent protégés côté serveur.

### FAQ-PROFILE-002 — Pourquoi mon prénom affiché peut-il venir de mon compte plutôt que d’une ancienne fiche joueur ?
**Audience : Joueur**

Lorsqu’un compte est correctement lié à une identité joueur, l’application privilégie la source d’identité prévue pour éviter les doublons et variantes historiques.

### FAQ-PROFILE-003 — Quelle taille maximale pour une photo ?
**Audience : Tous**

5 Mo.

### FAQ-PROFILE-004 — Quels formats de photo sont acceptés ?
**Audience : Tous**

JPEG, PNG et WebP.

### FAQ-PROFILE-005 — Puis-je modifier la photo d’un autre utilisateur ?
**Audience : Utilisateur**

Non. Un utilisateur actif ne peut écrire que dans le périmètre de photo qui lui est autorisé. Les opérations de support disposent de règles séparées.

### FAQ-PROFILE-006 — Qu’est-ce qu’un invité ?
**Audience : Tous**

Un invité est une personne qui peut participer à un match sans faire partie de l’effectif permanent et sans devoir posséder un compte applicatif.

### FAQ-PROFILE-007 — Un invité peut-il avoir une photo ?
**Audience : Tous**

Oui. Les invités réutilisables peuvent posséder une photo et une identité sportive afin d’être affichés correctement dans les matchs et l’historique.

### FAQ-PROFILE-008 — Un invité peut-il être gardien ?
**Audience : Tous**

Oui. Le modèle invité prévoit l’attribut gardien.

### FAQ-PROFILE-009 — Peut-on archiver un invité au lieu de le supprimer ?
**Audience : Admin**

Oui. Les invités disposent d’un cycle de vie permettant de les retirer des choix courants tout en conservant les références historiques nécessaires.

---

# 19. Notifications

### FAQ-NOTIF-001 — Dois-je autoriser les notifications dans mon navigateur ?
**Audience : Tous**

Oui pour recevoir les Web Push sur cet appareil. Sans permission du navigateur, l’application ne peut pas forcer la réception.

### FAQ-NOTIF-002 — Mes réglages s’appliquent-ils à toutes les notifications ?
**Audience : Utilisateur**

Non. Certaines notifications essentielles au fonctionnement du match n’ont pas de réglage individuel dans l’application, tandis que d’autres catégories sont facultatives.

### FAQ-NOTIF-003 — Quelles notifications essentielles existent actuellement ?
**Audience : Tous**

Le contrat actuel prévoit notamment l’ouverture des disponibilités, l’annulation d’un match et certains changements importants de date/heure, sous réserve de l’autorisation Push de l’appareil et de l’état opérationnel du service.

### FAQ-NOTIF-004 — Quelles notifications puis-je choisir ?
**Audience : Utilisateur**

Les préférences couvrent notamment les rappels de pronostics, l’Homme du match et les convocations/promotions de liste d’attente selon les écrans actuels.

### FAQ-NOTIF-005 — Pourquoi je ne reçois plus les rappels J-3/J-1 de disponibilité ?
**Audience : Tous**

Parce qu’ils ont été retirés du produit. Le rappel de disponibilité est désormais une action manuelle du staff.

### FAQ-NOTIF-006 — Reçois-je automatiquement le score final par Push ?
**Audience : Tous**

Non. L’ancienne notification automatique de score final a été retirée.

### FAQ-NOTIF-007 — Pourquoi je n’ai pas reçu une notification alors que le workflow a bien avancé ?
**Audience : Tous**

Une transition métier et une livraison Push sont deux choses distinctes. Vérifie les permissions du navigateur, tes préférences, l’abonnement de l’appareil et l’état global des notifications ; l’absence de Push ne signifie pas que l’action métier a échoué.

### FAQ-NOTIF-008 — Les notifications peuvent-elles être suspendues globalement ?
**Audience : Admin**

Oui. Un coupe-circuit opérationnel permet de suspendre les envois Push sans arrêter les disponibilités, pronostics, scrutins ou autres transitions métier.

### FAQ-NOTIF-009 — Que fait le système lorsqu’une livraison Push échoue temporairement ?
**Audience : Tous**

Le pipeline prévoit des retries/rattrapages pour plusieurs erreurs temporaires. Les abonnements définitivement invalides peuvent être nettoyés lorsqu’ils répondent comme expirés.

### FAQ-NOTIF-010 — Puis-je recevoir les notifications sur plusieurs appareils ?
**Audience : Utilisateur**

Oui si chaque navigateur/appareil possède son abonnement autorisé. Les préférences et abonnements doivent rester cohérents sur les appareils concernés.

### FAQ-NOTIF-011 — Désactiver les notifications supprime-t-il mon compte ?
**Audience : Utilisateur**

Non. Cela concerne uniquement les abonnements/préférences de notification.

### FAQ-NOTIF-012 — Un administrateur peut-il envoyer un Push de test ?
**Audience : Admin**

Oui via l’outil prévu, afin de vérifier la chaîne de livraison sans simuler un événement métier qui n’a pas eu lieu.

### FAQ-NOTIF-013 — Un administrateur peut-il envoyer un message Push personnalisé ?
**Audience : Admin**

Oui via le flux autorisé. Le serveur conserve les protections nécessaires pour éviter qu’un utilisateur standard n’utilise cet endpoint comme outil d’envoi.

---

# 20. Météo

### FAQ-WEATHER-001 — Quand la météo apparaît-elle ?
**Audience : Tous**

La météo du prochain match est éligible à partir de J-6 et jusqu’au coup d’envoi. Avant J-6 et après le début du match, aucun nouveau rafraîchissement n’est demandé.

### FAQ-WEATHER-002 — Quelle est la source météo ?
**Audience : Tous**

Open-Meteo, appelée côté serveur. Les téléphones ne contactent pas directement le fournisseur météo.

### FAQ-WEATHER-003 — À quelle fréquence la météo est-elle rafraîchie ?
**Audience : Tous**

La fréquence augmente à l’approche du match : environ toutes les 12 h à plus de 72 h, 6 h entre 72 h et 24 h, 2 h entre 24 h et 6 h, puis 1 h dans les six dernières heures. Le worker vérifie les éléments dus à intervalles réguliers.

### FAQ-WEATHER-004 — Quelle adresse est utilisée ?
**Audience : Tous**

En priorité l’adresse du match ; sinon l’adresse du club à domicile ; sinon l’adresse mémorisée de l’adversaire à l’extérieur.

### FAQ-WEATHER-005 — Une panne météo peut-elle bloquer un match ?
**Audience : Tous**

Non. La météo est un enrichissement non bloquant. La dernière prévision valide peut rester affichée et le match continue normalement.

### FAQ-WEATHER-006 — Que montre la carte météo ?
**Audience : Tous**

La température au coup d’envoi, le ressenti, la pluie, le vent, les rafales, l’humidité et plusieurs créneaux utiles selon les données disponibles.

### FAQ-WEATHER-007 — Qu’est-ce que l’Indice Grinta ?
**Audience : Tous**

C’est un indicateur calculé par l’application à partir des conditions météo affichées. Il reste volontairement prudent lorsque les conditions peuvent devenir défavorables ou dangereuses.

---

# 21. Calendrier externe

### FAQ-CAL-001 — Puis-je ajouter les matchs à mon calendrier personnel ?
**Audience : Utilisateur**

Oui. L’application dispose d’un abonnement calendrier dynamique permettant à un calendrier compatible de suivre les événements exposés par AS Grinta.

### FAQ-CAL-002 — Quelle différence avec un simple export ponctuel ?
**Audience : Utilisateur**

Un abonnement dynamique peut refléter les changements ultérieurs du calendrier lorsqu’il est rafraîchi par ton application de calendrier, contrairement à un fichier importé une seule fois.

### FAQ-CAL-003 — Une suppression de match est-elle prise en compte ?
**Audience : Utilisateur**

Le système conserve des informations techniques de suppression afin que le flux calendrier puisse traiter correctement les événements retirés au lieu de les oublier silencieusement.

### FAQ-CAL-004 — Le lien de calendrier doit-il être partagé publiquement ?
**Audience : Utilisateur**

Non. Considère ton abonnement personnel comme un accès à conserver pour toi. Ne publie pas son lien/token sur un espace public.

### FAQ-CAL-005 — Pourquoi mon calendrier externe n’est-il pas mis à jour immédiatement ?
**Audience : Utilisateur**

Le délai dépend aussi de la fréquence de rafraîchissement de l’application de calendrier externe. AS Grinta peut exposer la donnée à jour sans pouvoir forcer chaque fournisseur à la relire instantanément.

---

# 22. Saisons, historique et Wrapped

### FAQ-SEASON-001 — Combien de saisons peuvent être ouvertes en même temps ?
**Audience : Tous**

Le modèle impose une seule saison ouverte à la fois pour les workflows courants.

### FAQ-SEASON-002 — Que se passe-t-il lorsqu’une saison est terminée ?
**Audience : Tous**

Les données sportives et de pronostics sont figées/archivées selon le workflow afin de préserver les résultats, statistiques, titres et historiques.

### FAQ-SEASON-003 — Peut-on encore modifier une saison archivée ?
**Audience : Tous**

Une saison archivée est destinée à la consultation historique. Les opérations ordinaires de saison active ne doivent plus y être appliquées.

### FAQ-SEASON-004 — Qu’est-ce que le Season Wrapped ?
**Audience : Tous**

C’est un bilan de saison généré à partir des données finalisées : performances, positions jouées, badges et autres éléments de synthèse disponibles.

### FAQ-SEASON-005 — Puis-je ouvrir le Wrapped avant la vraie fin de saison ?
**Audience : Tous**

Non via le parcours normal actuel. L’ancien aperçu de conception est volontairement bloqué par le routeur.

### FAQ-SEASON-006 — Le Wrapped est-il calculé à chaque ouverture ?
**Audience : Tous**

Le système possède un workflow serveur dédié avec des jobs de génération afin de produire et conserver le bilan associé au joueur/saison.

### FAQ-SEASON-007 — Pourquoi les anciens matchs n’ont-ils pas toutes les statistiques du Wrapped moderne ?
**Audience : Tous**

Parce que certaines métriques n’étaient pas collectées historiquement. Le Wrapped ne doit pas inventer une donnée absente.

---

# 23. Données personnelles et confidentialité

### FAQ-PRIV-001 — Quelles données mon compte peut-il conserver ?
**Audience : Tous**

Selon ton usage : identité affichée, identifiant, surnom, photo facultative, rôle/statut, préférences de notification, pronostics, badges, liens avec l’effectif et les feuilles de match, abonnements Push et certains journaux techniques.

### FAQ-PRIV-002 — L’application stocke-t-elle mes mots de passe ?
**Audience : Tous**

Pas dans ses tables métier. Ils sont gérés par le service d’authentification Supabase.

### FAQ-PRIV-003 — Puis-je demander une copie de mes données ?
**Audience : Utilisateur**

Oui en contactant un administrateur du club. Il n’existe actuellement plus de bouton/RPC d’export personnel automatique accessible au client.

### FAQ-PRIV-004 — Puis-je demander la correction d’une donnée personnelle ?
**Audience : Utilisateur**

Oui. Contacte un administrateur en précisant la donnée concernée. Les faits sportifs déjà validés doivent être vérifiés séparément des simples informations de compte.

### FAQ-PRIV-005 — Puis-je demander la suppression de mon compte ?
**Audience : Utilisateur**

Oui. La suppression du compte retire les éléments de connexion et les données directement liées selon les contraintes en vigueur, mais elle ne signifie pas nécessairement la disparition de tous les faits sportifs historiques.

### FAQ-PRIV-006 — Pourquoi mon nom peut-il rester dans un ancien match après suppression du compte ?
**Audience : Tous**

Parce qu’un fait sportif validé peut devoir rester dans l’histoire du club. Lorsque le lien vers le compte est supprimé, le fait sportif peut subsister sans compte actif associé.

### FAQ-PRIV-007 — La suppression du compte anonymise-t-elle automatiquement tout mon historique ?
**Audience : Tous**

Non. Une demande d’anonymisation complète est différente d’une simple suppression de compte et doit être traitée séparément sur les feuilles de match, statistiques, invités et imports historiques concernés.

### FAQ-PRIV-008 — Qui peut voir pour qui j’ai voté au HDM ?
**Audience : Tous**

Les clients ordinaires, y compris l’administration courante, n’ont pas un accès direct aux bulletins individuels. Seuls les résultats agrégés sont exposés au produit.

### FAQ-PRIV-009 — Les journaux Push contiennent-ils les secrets de mon navigateur ?
**Audience : Tous**

Ils ne doivent pas contenir les secrets Web Push. Les journaux sont limités aux informations techniques nécessaires au diagnostic et à l’idempotence.

### FAQ-PRIV-010 — Que devient ma photo si je la remplace ?
**Audience : Utilisateur**

Le flux prévoit le nettoyage cohérent de l’ancien objet. Les administrateurs doivent éviter les suppressions massives de fichiers sans vérifier auparavant qu’ils sont réellement orphelins.

---

# 24. Administration des comptes

### FAQ-ADMUSR-001 — Comment valider une nouvelle inscription ?
**Audience : Admin**

Utilise la gestion des utilisateurs pour activer le profil en attente. L’Edge Function de gestion revérifie le JWT et les droits staff côté serveur.

### FAQ-ADMUSR-002 — Puis-je changer le rôle d’un utilisateur ?
**Audience : Admin**

Oui via les outils prévus. Les rôles sensibles ne doivent jamais être modifiés par une écriture directe depuis un client standard.

### FAQ-ADMUSR-003 — Puis-je archiver un utilisateur ?
**Audience : Admin**

Oui. L’archivage bloque l’usage actif tout en permettant de préserver les participations historiques nécessaires.

### FAQ-ADMUSR-004 — Puis-je supprimer définitivement un compte ?
**Audience : Admin**

Oui via le flux administratif prévu, après avoir évalué les conséquences sur les données personnelles et les faits sportifs historiques. Une anonymisation complète, si demandée, nécessite des vérifications supplémentaires.

### FAQ-ADMUSR-005 — Puis-je lier un compte à une identité joueur existante ?
**Audience : Admin**

Oui. Il faut privilégier l’identité joueur canonique existante afin d’éviter les doublons de statistiques et d’historique.

### FAQ-ADMUSR-006 — Puis-je donner les droits Admin simplement en marquant quelqu’un Coach ?
**Audience : Admin**

Non. L’attribut Coach donne seulement les droits sportifs Live prévus sur les matchs de la saison. Il ne remplace pas le rôle Admin.

---

# 25. Administration des matchs

### FAQ-ADMMATCH-001 — Qui peut créer ou modifier un match ?
**Audience : Admin**

Les opérations de gestion de match sont réservées au staff autorisé et revérifiées côté serveur.

### FAQ-ADMMATCH-002 — La création/modification de match et ses données associées sont-elles protégées contre les mises à jour concurrentes ?
**Audience : Admin**

Les flux récents utilisent des opérations atomiques et/ou des versions attendues afin d’éviter qu’une modification obsolète écrase silencieusement l’état courant.

### FAQ-ADMMATCH-003 — Dois-je changer directement le statut d’un match ?
**Audience : Admin**

Non. Utilise les actions dédiées : annuler, terminer/finaliser, archiver ou supprimer. Le serveur bloque les changements de statut génériques qui contourneraient le cycle métier.

### FAQ-ADMMATCH-004 — Puis-je archiver un match à venir ?
**Audience : Admin**

Non. L’archivage normal accepte uniquement un match déjà terminé.

### FAQ-ADMMATCH-005 — Pourquoi l’annulation est-elle refusée près du coup d’envoi ?
**Audience : Admin**

À partir du verrou T-15, le match est considéré comme entré dans son cycle Live. Le flux d’annulation prématch normal est alors fermé afin d’éviter de casser les états déjà figés.

### FAQ-ADMMATCH-006 — Pourquoi la suppression est-elle refusée après 24 h ?
**Audience : Admin**

Parce qu’au-delà de cette fenêtre le match est considéré comme un fait sportif à conserver/corriger plutôt qu’un objet à supprimer entièrement.

### FAQ-ADMMATCH-007 — Les cotes doivent-elles être saisies manuellement ?
**Audience : Admin**

Le produit actuel possède un calcul serveur canonique de cotes. L’objectif est que le client ne puisse pas devenir la source de vérité du modèle de cotes.

### FAQ-ADMMATCH-008 — Puis-je créer deux adversaires ayant exactement le même nom ?
**Audience : Admin**

Le modèle actuel permet explicitement certains doublons lorsque cela est nécessaire. Il faut néanmoins les utiliser volontairement afin de ne pas fragmenter inutilement l’historique d’un même adversaire.

---

# 26. Sécurité et fiabilité

### FAQ-SEC-001 — Les données sont-elles protégées uniquement par les boutons de l’application ?
**Audience : Tous**

Non. Les tables applicatives publiques ont la Row Level Security activée et les opérations sensibles contrôlent l’identité, le statut actif et/ou le rôle côté serveur.

### FAQ-SEC-002 — Un compte en attente peut-il appeler directement les API métier ?
**Audience : Tous**

Le contrat de sécurité prévoit qu’un profil non actif ne dispose pas d’accès métier utile, même s’il possède une session Auth valide.

### FAQ-SEC-003 — Pourquoi Supabase peut-il signaler des fonctions `SECURITY DEFINER` ?
**Audience : Admin**

Le conseiller générique signale l’exposition potentielle de fonctions privilégiées. Ce n’est pas automatiquement une faille : les RPC client autorisées doivent revérifier l’identité et les droits dans leur corps ou dans la fonction privée à laquelle elles délèguent. Chaque nouvelle RPC sensible doit continuer à être couverte par les tests d’ACL/RLS.

### FAQ-SEC-004 — La protection contre les mots de passe déjà compromis est-elle active ?
**Audience : Admin**

Pas actuellement sur le projet audité : la fonctionnalité native `Leaked Password Protection` nécessite un niveau Supabase supérieur au forfait actuellement utilisé. La politique de longueur du mot de passe et les autres protections applicatives restent distinctes de cette option.

### FAQ-SEC-005 — La branche principale GitHub est-elle protégée ?
**Audience : Admin**

Oui. Le dépôt utilise une protection de `main` avec passage par Pull Request et contrôles CI requis pour les changements concernés.

### FAQ-SEC-006 — Les migrations Supabase sont-elles surveillées ?
**Audience : Admin**

Oui. Le dépôt possède un inventaire/verrou de migrations et des workflows destinés à détecter une dérive entre GitHub et la production.

### FAQ-SEC-007 — Les sauvegardes sont-elles prévues ?
**Audience : Admin**

Oui. Sur le forfait actuel, un workflow GitHub effectue une sauvegarde logique chiffrée hebdomadaire de la base et des buckets applicatifs avec conservation limitée. Une sauvegarde n’est réellement validée qu’après un test périodique de restauration sur un environnement isolé.

### FAQ-SEC-008 — Peut-on tester une restauration directement sur la production ?
**Audience : Admin**

Non. Toute restauration d’essai doit être réalisée dans un environnement non productif.

### FAQ-SEC-009 — Que faire après une migration Supabase ?
**Audience : Admin**

Vérifier l’état du projet, les migrations distantes, la CI/RLS, les logs, les tâches planifiées concernées, les conseillers sécurité/performance et les parcours fonctionnels réellement modifiés.

---

# 27. Dépannage et incidents

### FAQ-HELP-001 — Une action affiche une référence d’incident. À quoi sert-elle ?
**Audience : Tous**

Elle permet de corréler plus facilement l’erreur vue dans l’interface avec les informations techniques disponibles au support, sans exposer de secret à l’utilisateur.

### FAQ-HELP-002 — Que faire si un enregistrement reste incertain après une coupure réseau ?
**Audience : Tous**

Recharge d’abord l’état depuis le serveur avant de répéter l’action. Plusieurs opérations critiques utilisent désormais l’idempotence, mais le parcours réseau complet n’est pas encore automatisé pour tous les scénarios de coupure ; il faut donc vérifier l’état autoritaire avant de recommencer.

### FAQ-HELP-003 — Que faire si je ne reçois aucun Push ?
**Audience : Utilisateur**

Vérifie l’autorisation navigateur, tes préférences et l’abonnement de l’appareil. Si plusieurs utilisateurs sont touchés, un administrateur doit aussi vérifier le coupe-circuit global et les journaux de livraison.

### FAQ-HELP-004 — Que faire si une donnée semble différente sur deux appareils ?
**Audience : Tous**

Rafraîchis les deux clients et vérifie la connexion. La base Supabase est la source de vérité ; un cache ou un onglet resté ouvert peut momentanément montrer un état ancien.

### FAQ-HELP-005 — Que faire si l’application refuse une action Admin alors que je suis Admin ?
**Audience : Admin**

Vérifie que le profil est toujours actif, que le rôle courant est bien Admin, que le match est dans le bon état et que l’échéance n’est pas dépassée. Si tout est correct, relève la référence d’incident et consulte les logs correspondants.

### FAQ-HELP-006 — Que faire si une fonction météo échoue ?
**Audience : Tous**

Rien de bloquant pour le match. La météo est facultative et le serveur réessaiera selon son planning ; la dernière prévision valide peut rester affichée.

### FAQ-HELP-007 — Que faire si une modification concurrente est signalée ?
**Audience : Admin, Coach**

Recharge l’état récent puis recommence ta modification à partir de cette nouvelle version. Ne cherche pas à forcer l’ancienne version.

### FAQ-HELP-008 — Puis-je conclure qu’une tâche planifiée est cassée parce qu’un ancien log contient une erreur ?
**Audience : Admin**

Non. Il faut lire les tâches actives et les exécutions récentes. Un ancien historique d’échec ne prouve pas que la tâche est toujours active ni toujours en erreur.

---

# 28. État de l’audit au 31 août 2026 — points à suivre

Cette section n’est pas destinée à être affichée telle quelle aux utilisateurs finaux. Elle sert de garde-fou aux mainteneurs de la FAQ.

### AUDIT-001 — Production et CI

- Projet Supabase de production actif et sain au moment de l’audit.
- 552 migrations distantes, dernière version `20260831012022`.
- La dernière PR fusionnée auditée a passé `Flutter CI` et `Runtime diagnostic`.
- Les statuts GitHub Pages observés sur `main` sont au vert.
- 0 exécution cron en échec sur les dernières 24 h au moment du contrôle.

### AUDIT-002 — Sécurité

- Toutes les tables applicatives `public` inspectées ont la RLS activée.
- Aucun contournement de rôle n’a été démontré dans les RPC Live critiques inspectées : les wrappers publics délèguent à des helpers privés qui vérifient notamment `is_match_coach_or_admin`.
- Les alertes génériques `SECURITY DEFINER` doivent continuer à être classifiées, pas supprimées aveuglément.
- `Leaked Password Protection` reste désactivée sur le forfait Supabase courant.

### AUDIT-003 — Hygiène Auth à corriger

Le diagnostic a trouvé **18 comptes Auth non supprimés sans profil applicatif correspondant**. Ils ont tous été créés au même instant le 21 juillet 2026 et n’ont jamais ouvert de session. Leur origine doit être identifiée avant suppression ; ils ressemblent à un reliquat de test/migration mais ne sont pas marqués explicitement comme comptes de test.

### AUDIT-004 — Notifications

Au moment de l’audit, le flag opérationnel `notifications_paused` est activé. Les appels techniques au pipeline Push continuent d’être observables et les workflows métier restent indépendants du coupe-circuit. Avant tout diagnostic utilisateur, relire la valeur distante : elle est volontairement dynamique.

### AUDIT-005 — Documentation à réaligner

- `production-operations.md` n’inventorie pas encore la nouvelle Edge Function `calendar-feed`.
- La production possède aussi les crons `process-season-wrapped-jobs` et `purge-client-incident-log`, absents de la liste historique de ce document.
- L’ancien texte affirmant que l’attribut Coach n’accorde aucun droit applicatif est trop large : le serveur donne bien au coach actif de la saison des droits Live ciblés via `private.is_match_coach_or_admin()`.

### AUDIT-006 — QA encore incomplète

Les éléments suivants restent à valider complètement :

- test réel de restauration d’une sauvegarde dans un environnement isolé ;
- tests appareils physiques/accessibilité : VoiceOver, TalkBack, grande taille de texte, notifications réelles multi-appareils ;
- automatisation exhaustive des coupures réseau au milieu des actions critiques (disponibilité, pronostic, finalisation/correction, upload photo) ;
- campagne combinatoire exhaustive de tous les états/limites encore suivie par les tickets QA existants.

### AUDIT-007 — Performance

Les conseillers Supabase ne montrent pas de blocage de performance démontré. Quelques clés étrangères sans index couvrant et plusieurs index encore inutilisés sont signalés en information. Aucun index ne doit être supprimé uniquement parce que son compteur d’utilisation est nul.

### AUDIT-008 — Dérive de ce fichier

Toute modification de l’un des éléments suivants doit déclencher une revue de cette FAQ :

- rôles, RLS ou RPC ;
- chronologie J-6 / T-15 / post-match ;
- règles de pronostic et de classement ;
- disponibilités, liste d’attente ou convocations ;
- composition, Live ou compte rendu ;
- MOTM ;
- notifications ;
- calendrier externe ;
- météo ;
- statistiques, badges, identité joueur ;
- confidentialité/suppression ;
- saisons et Wrapped ;
- fonctions Edge, crons ou politique de sauvegarde.

---

# 29. Matrice de couverture de la FAQ

| Domaine | Couvert | Audiences principales |
|---|---:|---|
| Inscription / attente / connexion / mot de passe | Oui | Tous, Utilisateur, Admin |
| Rôles / Admin / Coach / sécurité des routes | Oui | Tous |
| PWA / navigation / liens profonds / hors ligne | Oui | Tous |
| Matchs / calendrier / historique / annulation / suppression | Oui | Tous, Admin |
| Disponibilités | Oui | Joueur, Admin |
| Liste d’attente / Effectif / convocations | Oui | Joueur, Admin |
| Composition classique | Oui | Tous, Admin |
| Match entre nous | Oui | Tous, Admin |
| Live / chrono / buts / assists / remplacements / formation | Oui | Coach, Admin |
| Compte rendu / corrections / archivage | Oui | Tous, Admin |
| Homme du match | Oui | Tous, Joueur |
| Pronostics matchs / barème | Oui | Tous, Utilisateur |
| Pronostics saison / bonus / roster figé | Oui | Tous, Utilisateur |
| Classements | Oui | Tous |
| Statistiques | Oui | Tous |
| Badges / Armoire | Oui | Tous, Admin |
| Profil / joueurs / invités / photos | Oui | Tous, Admin |
| Notifications / préférences / coupe-circuit | Oui | Tous, Admin |
| Météo | Oui | Tous |
| Abonnement calendrier | Oui | Utilisateur |
| Saisons / historique / Wrapped | Oui | Tous, Admin |
| Confidentialité / suppression / anonymisation | Oui | Tous, Admin |
| Exploitation / sécurité / migrations / sauvegarde | Oui | Admin |
| Dépannage / incidents / concurrence / réseau | Oui | Tous, Admin |

---

# 30. Règles éditoriales pour la future FAQ dans Flutter

1. Utiliser les identifiants `FAQ-*` comme clés stables plutôt que le texte de la question.
2. Permettre la recherche sur question, réponse, catégorie et synonymes.
3. Filtrer ou prioriser les questions selon le rôle, sans cacher les explications générales utiles.
4. Ne jamais afficher la section `AUDIT-*` dans la FAQ publique ; elle sert aux mainteneurs.
5. Ne pas coder dans l’interface une règle métier uniquement depuis ce Markdown : le backend reste la source de vérité.
6. Lorsqu’une règle dépend d’une valeur opérationnelle (`notifications_paused`, état d’un cron, version déployée), expliquer le principe sans figer la valeur du jour dans l’interface.
7. Lorsqu’une fonctionnalité est retirée, supprimer son entrée active ou la transformer en question de migration explicite plutôt que laisser une réponse ambiguë.
8. Toute nouvelle fonctionnalité livrée doit ajouter ou modifier ses entrées FAQ dans la même PR.
