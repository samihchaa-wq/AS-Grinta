# Polices embarquées

Deux familles, sous licence SIL Open Font License 1.1 (voir `OFL-Inter.txt` et
`OFL-BarlowCondensed.txt`).

| Fichier | Famille | Graisse | Rôle |
| --- | --- | --- | --- |
| `BarlowCondensed-SemiBold.ttf` | `BarlowCondensed` | 600 | titres secondaires |
| `BarlowCondensed-Bold.ttf` | `BarlowCondensed` | 700 | titres, scores, chiffres mis en avant |
| `Inter-Regular.ttf` | `Inter` | 400 | texte courant |
| `Inter-Medium.ttf` | `Inter` | 500 | texte accentué, puces |
| `Inter-SemiBold.ttf` | `Inter` | 600 | boutons, étiquettes, onglets |
| `Inter-Bold.ttf` | `Inter` | 700 | mise en valeur dans le texte |

## Sous-ensemble

Les fichiers sont des sous-ensembles des originaux Google Fonts, réduits aux
caractères réellement utilisés par l'application (latin, latin étendu A,
ponctuation typographique, flèches, quelques symboles mathématiques). Les
emojis ne sont pas embarqués : ils continuent d'être rendus par la police
système, comme avant.

Le poids total passe ainsi de 1,7 Mo à environ 315 ko, ce qui reste tenable
pour la version Web.

Commande utilisée pour chaque fichier :

```bash
pyftsubset <original>.ttf \
  --unicodes="U+0020-007E,U+00A0-017F,U+0192,U+02B3,U+02C6,U+02DC,U+1D49,U+2000-206F,U+20AC,U+2190-2193,U+2212,U+2264-2265,U+25CF" \
  --layout-features='kern,liga,tnum,calt' \
  --no-hinting \
  --output-file=<destination>.ttf
```

La fonctionnalité `tnum` (chiffres à chasse fixe) est conservée volontairement :
elle est utilisée pour aligner les colonnes de statistiques et les scores.

Aucune graisse 800 n'est embarquée. Les styles qui demandent `FontWeight.w800`
retombent sur la graisse 700 disponible, ce qui est le comportement recherché :
l'ancien thème mettait presque tous les textes au gras maximum.
