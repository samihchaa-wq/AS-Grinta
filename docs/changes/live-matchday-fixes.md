# Quatre corrections sur le Tableau Blanc du jour de match

## Ce qui n'allait pas

### 1. Impossible d'échanger un titulaire et un remplaçant avant le coup d'envoi

Sur l'écran de préparation du Live, faire glisser un remplaçant sur le terrain
échouait à tous les coups. L'application affichait « Action non confirmée.
L'état réel du serveur a été rechargé. » et la composition revenait comme
avant.

La base refusait l'enregistrement : elle exige que tout passage du banc au
terrain soit déclaré comme un remplacement, pour ne pas fausser les
« Faits du match » ni le compteur de fois sur le banc. Ce garde-fou n'a aucun
sens avant le coup d'envoi, où aucun événement ne peut exister : une inversion
y est une simple correction de composition.

### 2. Le prénom « François » affiché « Franç… »

Pendant le match, le terrain se resserre pour laisser la place à la colonne du
banc. L'étiquette du prénom était limitée à la largeur de la photo : les
prénoms longs étaient coupés, sur le terrain comme sur le banc.

### 3. Renvoyé sur l'onglet Info en plein match

À T-15 (quinze minutes avant le coup d'envoi) les pronostics ferment et
l'onglet « Prono » disparaît. La fiche du match traitait cette disparition
comme une demande de navigation et rebasculait sur la section d'arrivée —
en pratique « Info » quand le match avait été ouvert depuis le calendrier.
Le basculement ne se voyait qu'au premier rafraîchissement suivant, par
exemple juste après avoir marqué un but et désigné un buteur.

### 4. Impossible de refermer la liste des joueurs

La liste « Qui a marqué ? » puis « Passe décisive ? » remplit tout l'écran :
il n'y avait ni poignée ni bouton pour sortir sans désigner quelqu'un. Un
buteur enregistré par erreur ne pouvait pas non plus être remis « à
attribuer ».

## Ce qui change

- `private.save_match_live_lineup` n'applique le contrôle terrain/banc qu'à
  partir du moment où le match est lancé (`running`, `paused`, `halftime`).
  Avant le coup d'envoi, les échanges passent et ne créent aucun événement de
  remplacement. Une fois le match lancé, le garde-fou est intact.
- L'étiquette du prénom peut déborder du marqueur sur le terrain (jusqu'à 1,6
  fois sa largeur, centrée) et se réduit légèrement en dernier recours au lieu
  d'être tronquée. Sur le banc, collé au bord de l'écran, elle se réduit
  seulement.
- La fiche du match ne réinitialise plus l'onglet affiché : seule une nouvelle
  section explicitement demandée le change. Si l'onglet consulté est justement
  « Prono » au moment où il ferme, la page revient d'elle-même sur la section
  d'ouverture.
- Les feuilles de choix du buteur et du passeur ont une poignée et un bouton
  « Annuler ». Quand le but est déjà attribué, un choix
  « Effacer · buteur à désigner plus tard » le remet à attribuer (la passe
  décisive part avec lui).

## Migration et tests

- Migration : `20260828120000_live_prekickoff_lineup_swap.sql`.
- Test pgTAP : `supabase/tests/database/live_prekickoff_lineup_swap.test.sql`.
- Tests Flutter : `test/match_live_player_name_display_test.dart`,
  `test/admin_squad_plan_step_persistence_test.dart`,
  `test/match_live_scorer_picker_test.dart`.
- Validation : la suite Flutter complète passe (451 tests). Le comportement de
  la fonction SQL a été rejoué sur un PostgreSQL local avec un schéma réduit
  aux tables qu'elle touche : échange accepté avant le coup d'envoi sans
  événement créé, échange non déclaré toujours refusé match lancé, échange
  déclaré accepté avec son événement. La suite pgTAP complète tourne dans la CI
  Supabase du dépôt. La migration n'a pas été appliquée sur staging depuis
  cette session.
