# Audit visuel — pistes d’amélioration

Planches « Aujourd’hui / Proposition » pour cinq écrans. Les captures
« Aujourd’hui » sont de vrais rendus de l’application (widgets Flutter affichés
avec des données de démonstration, taille iPhone 390 × 844, thème sombre).
Les « Propositions » sont des maquettes : rien n’est encore codé.

| Planche | Idée principale |
| --- | --- |
| `1_calendrier_defile.png` | Prochain match en vedette, autres matchs en lignes compactes |
| `2_calendrier_mois.png` | Vraie grille mensuelle colorée par résultat |
| `3_fiche_match.png` | Buteurs et Homme du match sous le score, onglets au lieu de volets |
| `4_statistiques_joueurs.png` | Podium, en-têtes de colonnes en clair, filtre de saison compact |
| `5_parametres.png` | Carte profil en tête, réglages groupés, déconnexion accessible |

Le dossier `captures/` contient toutes les captures brutes, y compris les
écrans non retravaillés (Équipe, Prono, Profil, Connexion).

Point relevé en passant : sur le terrain de la fiche match, le nom de chaque
joueur dépasse d’un pixel de sa case avec la taille de texte imposée par
l’application (×1,10). En production c’est invisible ou presque (bas des
lettres rogné), mais c’est à corriger si on retravaille cet écran.
