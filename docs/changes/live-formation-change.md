# Changement de dispositif pendant un Live

Le coach peut modifier le dispositif depuis l'écran Live tant que la session est ouverte.

- Le menu réutilise le catalogue `footballFormations` de l'éditeur de composition.
- Seuls les joueurs déjà présents sur le terrain sont repositionnés.
- Le banc ne change pas.
- Aucun événement de remplacement n'est créé.
- Le changement est refusé tant qu'une salve de remplacements est en attente dans l'interface.
- La sauvegarde du `formation_code` et des positions est atomique côté Supabase.
- Le verrou `lineup_revision` empêche deux coachs d'écraser silencieusement leurs modifications.
- La migration canonique est `20260826190000_live_formation_change.sql`, après l'inventaire production synchronisé à `20260826181431`.
- Le contrat a été validé sur staging : changement de dispositif, incrément de révision, refus d'une révision obsolète et zéro événement de remplacement.
