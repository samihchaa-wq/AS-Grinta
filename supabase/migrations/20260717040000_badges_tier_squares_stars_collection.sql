-- Collection finale des badges : couleur du carré par palier, étoile sur les
-- derniers paliers stats + tous les Diamant, emojis + surnoms + descriptions.

alter table public.badges
  add column if not exists has_star boolean not null default false;

update public.badges b set
  emoji       = v.emoji,
  name        = v.name,
  description = v.description,
  color       = v.color,
  has_star    = v.has_star
from (values
  ('matches_played_season__15', '📅', $q$Habitué$q$,               $q$Participer à 15 matchs au cours d'une même saison.$q$,                               '#6E7A86', false),
  ('matches_played_season__20', '📅', $q$Assidu$q$,                $q$Participer à 20 matchs au cours d'une même saison.$q$,                               '#B87333', false),
  ('matches_played_season__25', '📅', $q$Pilier$q$,                $q$Participer à 25 matchs au cours d'une même saison.$q$,                               '#C4CBD4', false),
  ('matches_played_season__30', '📅', $q$Incontournable$q$,        $q$Participer à 30 matchs au cours d'une même saison.$q$,                               '#E3B23C', true),
  ('matches_played__150',       '📅', $q$Fidèle$q$,                $q$Atteindre 150 matchs joués avec le club.$q$,                                        '#4FA9E8', false),
  ('matches_played__200',       '📅', $q$Vétéran$q$,               $q$Atteindre 200 matchs joués avec le club.$q$,                                        '#1E3A8A', false),
  ('matches_played__250',       '📅', $q$Cadre du club$q$,         $q$Atteindre 250 matchs joués avec le club.$q$,                                        '#7C3AED', false),
  ('matches_played__300',       '📅', $q$Légende du club$q$,       $q$Atteindre 300 matchs joués avec le club.$q$,                                        '#1C1C24', true),
  ('goals_season__5',           '⚽', $q$Première gâchette$q$,      $q$Marquer 5 buts au cours d'une même saison.$q$,                                      '#6E7A86', false),
  ('goals_season__10',          '⚽', $q$Finisseur$q$,             $q$Marquer 10 buts au cours d'une même saison.$q$,                                     '#B87333', false),
  ('goals_season__20',          '⚽', $q$Artilleur$q$,             $q$Marquer 20 buts au cours d'une même saison.$q$,                                     '#C4CBD4', false),
  ('goals_season__30',          '⚽', $q$Goleador$q$,              $q$Marquer 30 buts au cours d'une même saison.$q$,                                     '#E3B23C', true),
  ('goals__25',                 '⚽', $q$Buteur confirmé$q$,       $q$Atteindre 25 buts marqués avec le club.$q$,                                         '#4FA9E8', false),
  ('goals__50',                 '⚽', $q$Canonnier$q$,             $q$Atteindre 50 buts marqués avec le club.$q$,                                         '#1E3A8A', false),
  ('goals__75',                 '⚽', $q$Chasseur de records$q$,   $q$Atteindre 75 buts marqués avec le club.$q$,                                         '#7C3AED', false),
  ('goals__100',                '⚽', $q$Centurion$q$,             $q$Atteindre la barre mythique des 100 buts avec le club.$q$,                          '#1C1C24', true),
  ('wins_season__10',           '🏆', $q$Compétiteur$q$,           $q$Remporter 10 matchs au cours d'une même saison.$q$,                                 '#6E7A86', false),
  ('wins_season__15',           '🏆', $q$Gagnant$q$,               $q$Remporter 15 matchs au cours d'une même saison.$q$,                                 '#B87333', false),
  ('wins_season__20',           '🏆', $q$Serial winner$q$,         $q$Remporter 20 matchs au cours d'une même saison.$q$,                                 '#C4CBD4', false),
  ('wins_season__25',           '🏆', $q$Invincible$q$,            $q$Remporter 25 matchs au cours d'une même saison.$q$,                                 '#E3B23C', true),
  ('wins__50',                  '🏆', $q$Habitué de la victoire$q$,$q$Atteindre 50 victoires avec le club.$q$,                                            '#4FA9E8', false),
  ('wins__100',                 '🏆', $q$Centurion victorieux$q$,  $q$Atteindre 100 victoires avec le club.$q$,                                           '#1E3A8A', false),
  ('wins__150',                 '🏆', $q$Maître de la gagne$q$,    $q$Atteindre 150 victoires avec le club.$q$,                                           '#7C3AED', false),
  ('wins__200',                 '🏆', $q$Légende victorieuse$q$,   $q$Atteindre 200 victoires avec le club.$q$,                                           '#1C1C24', true),
  ('clean_sheets_season__3',    '🧤', $q$Premier verrou$q$,        $q$Terminer 3 matchs sans encaisser de but au cours d'une même saison.$q$,              '#6E7A86', false),
  ('clean_sheets_season__5',    '🧤', $q$Dernier rempart$q$,       $q$Terminer 5 matchs sans encaisser de but au cours d'une même saison.$q$,              '#B87333', false),
  ('clean_sheets_season__7',    '🧤', $q$Muraille$q$,              $q$Terminer 7 matchs sans encaisser de but au cours d'une même saison.$q$,              '#C4CBD4', false),
  ('clean_sheets_season__10',   '🧤', $q$Forteresse imprenable$q$, $q$Terminer 10 matchs sans encaisser de but au cours d'une même saison.$q$,             '#E3B23C', true),
  ('clean_sheets__15',          '🧤', $q$Verrou confirmé$q$,       $q$Atteindre 15 matchs sans encaisser de but avec le club.$q$,                         '#4FA9E8', false),
  ('clean_sheets__25',          '🧤', $q$Gardien du temple$q$,     $q$Atteindre 25 matchs sans encaisser de but avec le club.$q$,                         '#1E3A8A', false),
  ('clean_sheets__50',          '🧤', $q$Mur infranchissable$q$,   $q$Atteindre 50 matchs sans encaisser de but avec le club.$q$,                         '#7C3AED', false),
  ('clean_sheets__100',         '🧤', $q$Maître des cages$q$,      $q$Atteindre 100 matchs sans encaisser de but avec le club.$q$,                        '#1C1C24', true),
  ('doubles__10',               '✌️', $q$Double impact$q$,         $q$Réaliser 10 doublés avec le club.$q$,                                               '#6E7A86', false),
  ('doubles__20',               '✌️', $q$Double menace$q$,         $q$Réaliser 20 doublés avec le club.$q$,                                               '#B87333', false),
  ('doubles__30',               '✌️', $q$Spécialiste du doublé$q$, $q$Réaliser 30 doublés avec le club.$q$,                                               '#C4CBD4', false),
  ('doubles__50',               '✌️', $q$Monsieur doublé$q$,       $q$Atteindre 50 doublés avec le club.$q$,                                              '#E3B23C', true),
  ('mvp__10',                   '👑', $q$Homme fort$q$,            $q$Obtenir 10 distinctions d'Homme du match avec le club.$q$,                          '#4FA9E8', false),
  ('mvp__20',                   '👑', $q$Joueur décisif$q$,        $q$Obtenir 20 distinctions d'Homme du match avec le club.$q$,                          '#1E3A8A', false),
  ('mvp__30',                   '👑', $q$Roi du match$q$,          $q$Obtenir 30 distinctions d'Homme du match avec le club.$q$,                          '#7C3AED', false),
  ('mvp__50',                   '👑', $q$Mobutu$q$,                $q$Obtenir 50 distinctions d'Homme du match avec le club.$q$,                          '#1C1C24', true),
  ('pred_good_result__15',      '✅', $q$Bon début$q$,             $q$Trouver correctement l'issue de 15 matchs.$q$,                                      '#4FA9E8', false),
  ('pred_good_result__30',      '✅', $q$Pronostiqueur confirmé$q$,$q$Trouver correctement l'issue de 30 matchs.$q$,                                       '#1E3A8A', false),
  ('pred_good_result__50',      '✅', $q$Expert du résultat$q$,    $q$Trouver correctement l'issue de 50 matchs.$q$,                                      '#7C3AED', false),
  ('pred_good_result__100',     '✅', $q$Oracle$q$,                $q$Atteindre 100 bons résultats pronostiqués.$q$,                                      '#1C1C24', true),
  ('pred_exact_score__10',      '🎯', $q$Œil juste$q$,             $q$Trouver exactement le score de 10 matchs.$q$,                                       '#4FA9E8', false),
  ('pred_exact_score__20',      '🎯', $q$Tireur d'élite$q$,        $q$Trouver exactement le score de 20 matchs.$q$,                                       '#1E3A8A', false),
  ('pred_exact_score__30',      '🎯', $q$Maître du score$q$,       $q$Trouver exactement le score de 30 matchs.$q$,                                       '#7C3AED', false),
  ('pred_exact_score__50',      '🎯', $q$Sniper$q$,                $q$Atteindre 50 scores exacts pronostiqués.$q$,                                        '#1C1C24', true),
  ('seasons_complete__1',       '🫡', $q$Toujours présent$q$,      $q$Participer à tous les matchs organisés au cours d'une même saison, sans aucune absence.$q$, '#5FC9D9', true),
  ('title_most_present__1',     '🙋', $q$Monsieur Présent$q$,      $q$Terminer une saison en étant le joueur ayant participé au plus grand nombre de matchs.$q$,   '#5FC9D9', true),
  ('title_top_scorer__1',       '🥇', $q$Soulier d'or$q$,          $q$Terminer une saison en étant le joueur ayant marqué le plus grand nombre de buts.$q$,        '#5FC9D9', true),
  ('title_best_winrate__1',     '📈', $q$Monsieur Victoire$q$,     $q$Terminer une saison avec le meilleur taux de victoire parmi les joueurs éligibles.$q$,        '#5FC9D9', true),
  ('title_mvp_king__1',         '🌟', $q$Ballon d'or$q$,           $q$Terminer une saison en étant le joueur ayant obtenu le plus de distinctions d'Homme du match.$q$, '#5FC9D9', true),
  ('title_best_pred_player__1', '📊', $q$L'Analyste$q$,            $q$Terminer une saison avec le meilleur total de points sur les pronostics liés aux statistiques des joueurs.$q$, '#5FC9D9', true),
  ('title_best_pred_match__1',  '🔮', $q$Le Visionnaire$q$,        $q$Terminer une saison avec le meilleur total de points sur les pronostics de résultats et de scores des matchs.$q$, '#5FC9D9', true),
  ('title_best_pred_overall__1','🧠', $q$Le Cerveau$q$,            $q$Terminer une saison avec le meilleur total cumulé sur l'ensemble des catégories de pronostics.$q$, '#5FC9D9', true),
  ('max_match_goals__3',        '🎩', $q$Pas content ?$q$,         $q$Marquer trois buts au cours d'un même match.$q$,                                    '#F1706E', false),
  ('max_match_goals__4',        '🃏', $q$Poker$q$,                 $q$Marquer quatre buts au cours d'un même match.$q$,                                   '#E23B36', false),
  ('max_match_goals__5',        '🖐️', $q$La Manita$q$,             $q$Marquer cinq buts au cours d'un même match.$q$,                                     '#9E1B1B', false),
  ('exploit_remplace_gardien',  '🧤', $q$Gardien d'un soir$q$,     $q$Prendre la place du gardien pendant un match alors que ce n'est pas son poste habituel.$q$, '#F2811D', false),
  ('exploit_equipe_adverse',    '🕵️', $q$Agent double$q$,          $q$Changer temporairement de camp afin de jouer dans l'équipe adverse.$q$,              '#F2811D', false),
  ('exploit_penalty_provoque',  '🔪', $q$Le Boucher$q$,            $q$Commettre une faute entraînant un penalty pour l'équipe adverse.$q$,                 '#F2811D', false),
  ('exploit_penalty_subi',      '🤿', $q$Le Plongeur$q$,           $q$Subir une faute dans la surface permettant à son équipe d'obtenir un penalty.$q$,     '#F2811D', false),
  ('exploit_penalty_arrete',    '🧱', $q$Le Mur$q$,                $q$Empêcher l'adversaire de marquer en arrêtant un penalty.$q$,                         '#F2811D', false),
  ('exploit_but_vainqueur_tardif','🥵',$q$Clutch$q$,               $q$Marquer dans les dernières minutes le but qui offre définitivement la victoire à son équipe.$q$, '#F2811D', false),
  ('exploit_csc',               '🫣', $q$La Boulette$q$,           $q$Envoyer involontairement le ballon dans les cages de sa propre équipe.$q$,           '#F2811D', false),
  ('exploit_sauvetage_ligne',   '🦸', $q$Super-héros$q$,           $q$Empêcher un but en dégageant le ballon directement sur la ligne de but.$q$,          '#F2811D', false),
  ('exploit_trois_postes',      '🧩', $q$Couteau suisse$q$,        $q$Occuper au moins trois postes différents au cours d'un même match.$q$,               '#F2811D', false),
  ('role_president',            '🤵', $q$El Presidente$q$,          $q$Exercer officiellement la fonction de président du club.$q$,                         '#1C1C24', false),
  ('role_coach',               '👨‍🦲', $q$Coach$q$,                 $q$Exercer officiellement la fonction de coach du club.$q$,                             '#1C1C24', false)
) as v(code, emoji, name, description, color, has_star)
where b.code = v.code;

-- Exposer has_star dans le RPC des badges arborés.
drop function if exists public.featured_badges();
create function public.featured_badges()
returns table(
  profile_id uuid, code text, emoji text, image_url text, color text,
  metric text, threshold integer, has_star boolean, sort_order integer
)
language sql
stable security definer
set search_path to 'public'
as $function$
  select pb.profile_id, b.code, b.emoji, b.image_url, b.color, b.metric,
         b.threshold, b.has_star, b.sort_order
  from public.profile_badges pb
  join public.badges b on b.id = pb.badge_id
  where pb.featured
  order by pb.profile_id, b.sort_order;
$function$;

grant execute on function public.featured_badges() to authenticated;
