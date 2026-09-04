# Appellation des joueurs

## Où vit un surnom

Un surnom est stocké à un seul endroit : la colonne `surnom` de la fiche de
compte (`public.profiles`). Il n’existe pas de deuxième copie.

- La personne concernée est la seule à pouvoir le modifier, depuis son écran
  Profil. Aucun écran d’administration ne change le surnom de quelqu’un
  d’autre.
- L’effectif (`public.season_players`) ne porte pas de surnom : un admin y
  saisit un prénom et un nom. Un joueur d’effectif n’a de surnom que s’il est
  rattaché à un compte qui en a un.
- Un invité (`public.guest_players`) n’a pas de compte, donc jamais de surnom.
- Le surnom n’est figé dans aucun historique : ni composition publiée, ni
  feuille de match, ni notification archivée. Il est recalculé à chaque
  lecture, donc un changement de surnom se répercute aussi sur les matchs
  passés.

Un surnom non renseigné est enregistré sous la forme d’une **chaîne vide**,
pas d’un `null` : toute règle qui manipule le surnom doit traiter `''` et
`'   '` comme « non renseigné ».

## La règle d’appellation

L’ordre de priorité est le même partout :

1. le surnom du compte ;
2. sinon le prénom du compte ;
3. sinon le prénom de repli (fiche d’effectif ou invité) ;
4. sinon le nom complet de repli ;
5. sinon le repli explicite de l’appelant (« Joueur », « Compte sans nom »…).

Une liste se classe sur le nom réellement affiché, pas sur le surnom brut.

## Où la règle est écrite

Elle n’existe qu’à deux endroits, un par côté :

- côté base : `public.person_display_name`, `public.person_sort_key`,
  `public.guest_display_name` et `public.guest_display_label` ;
- côté application : `lib/core/utils/display_name.dart`.

Toute fonction de lecture appelle la fonction partagée. **Ne jamais réécrire la
cascade à la main dans une nouvelle requête ou un nouvel écran** : c’est
exactement ce qui faisait afficher un même joueur sous deux noms différents
selon l’écran.

Les contrats sont fixés par
`supabase/tests/database/display_name_single_source.test.sql` et
`test/display_name_test.dart`. Une évolution de la règle se fait dans ces deux
fonctions et dans ces deux tests.

## Exceptions volontaires

- Les statistiques (`public.v_statistics_players`) nomment toujours les joueurs
  par leur vrai prénom, jamais par leur surnom.
- Un invité s’affiche parfois suivi de l’étiquette « (Invité) », parfois sans,
  selon l’écran. Le choix appartient à l’appelant ; la mise en forme du nom
  lui-même reste partagée.
