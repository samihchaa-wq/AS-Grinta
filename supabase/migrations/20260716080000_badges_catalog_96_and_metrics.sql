-- Catalogue révisé : 96 badges, un nom unique par palier.
-- Nouveautés : HDM/pronos « sur une saison » retirés ; triplé/quadruplé/
-- quintuplé deviennent des badges uniques (metric max_match_goals) ; titres
-- négatifs supprimés ; seuils revus. Les métriques sont réalignées et le moteur
-- réattribue tout (les triggers existants restent en place).
delete from public.profile_badges where source = 'auto';
delete from public.badges;

insert into public.badges(code, name, description, emoji, family, category, kind, auto, metric, threshold, sort_order) values
('matches_played_season__5','Dans le groupe','5 matchs joués sur une saison','👕','joueur','joueur_saison','tier',true,'matches_played_season',5,1),
('matches_played_season__10','Toujours là','10 matchs joués sur une saison','👕','joueur','joueur_saison','tier',true,'matches_played_season',10,2),
('matches_played_season__20','Indispensable','20 matchs joués sur une saison','👕','joueur','joueur_saison','tier',true,'matches_played_season',20,3),
('matches_played_season__30','Saison de fer','30 matchs joués sur une saison','👕','joueur','joueur_saison','tier',true,'matches_played_season',30,4),
('goals_season__5','Débloqueur','5 buts sur une saison','⚽','joueur','joueur_saison','tier',true,'goals_season',5,5),
('goals_season__10','Finisseur','10 buts sur une saison','⚽','joueur','joueur_saison','tier',true,'goals_season',10,6),
('goals_season__15','Gâchette','15 buts sur une saison','⚽','joueur','joueur_saison','tier',true,'goals_season',15,7),
('goals_season__20','Machine à buts','20 buts sur une saison','⚽','joueur','joueur_saison','tier',true,'goals_season',20,8),
('wins_season__5','Premier élan','5 victoires sur une saison','🏆','joueur','joueur_saison','tier',true,'wins_season',5,9),
('wins_season__10','Habitué à gagner','10 victoires sur une saison','🏆','joueur','joueur_saison','tier',true,'wins_season',10,10),
('wins_season__15','Dominateur','15 victoires sur une saison','🏆','joueur','joueur_saison','tier',true,'wins_season',15,11),
('wins_season__20','Moissonneur de victoires','20 victoires sur une saison','🏆','joueur','joueur_saison','tier',true,'wins_season',20,12),
('clean_sheets_season__1','Premier verrou','1 clean sheet sur une saison','🧤','joueur','joueur_saison','tier',true,'clean_sheets_season',1,13),
('clean_sheets_season__2','Double verrou','2 clean sheets sur une saison','🧤','joueur','joueur_saison','tier',true,'clean_sheets_season',2,14),
('clean_sheets_season__3','Forteresse','3 clean sheets sur une saison','🧤','joueur','joueur_saison','tier',true,'clean_sheets_season',3,15),
('clean_sheets_season__5','Mur de la saison','5 clean sheets sur une saison','🧤','joueur','joueur_saison','tier',true,'clean_sheets_season',5,16),
('clean_sheets_season__10','Infranchissable','10 clean sheets sur une saison','🧤','joueur','joueur_saison','tier',true,'clean_sheets_season',10,17),
('matches_played__25','Visage familier','25 matchs en carrière','👕','joueur','joueur_all_time','tier',true,'matches_played',25,18),
('matches_played__50','Cadre du groupe','50 matchs en carrière','👕','joueur','joueur_all_time','tier',true,'matches_played',50,19),
('matches_played__100','Pilier du terrain','100 matchs en carrière','👕','joueur','joueur_all_time','tier',true,'matches_played',100,20),
('matches_played__250','Légende du vestiaire','250 matchs en carrière','👕','joueur','joueur_all_time','tier',true,'matches_played',250,21),
('goals__25','Buteur confirmé','25 buts en carrière','⚽','joueur','joueur_all_time','tier',true,'goals',25,22),
('goals__50','Artilleur','50 buts en carrière','⚽','joueur','joueur_all_time','tier',true,'goals',50,23),
('goals__100','Centurion','100 buts en carrière','⚽','joueur','joueur_all_time','tier',true,'goals',100,24),
('goals__200','Monument du but','200 buts en carrière','⚽','joueur','joueur_all_time','tier',true,'goals',200,25),
('wins__10','Goût de la victoire','10 victoires en carrière','🏆','joueur','joueur_all_time','tier',true,'wins',10,26),
('wins__25','Compétiteur','25 victoires en carrière','🏆','joueur','joueur_all_time','tier',true,'wins',25,27),
('wins__50','Champion régulier','50 victoires en carrière','🏆','joueur','joueur_all_time','tier',true,'wins',50,28),
('wins__100','Collectionneur','100 victoires en carrière','🏆','joueur','joueur_all_time','tier',true,'wins',100,29),
('wins__200','Dynastie','200 victoires en carrière','🏆','joueur','joueur_all_time','tier',true,'wins',200,30),
('doubles__1','Coup double','1 doublé (2 buts dans un match)','🎯','joueur','joueur_all_time','tier',true,'doubles',1,31),
('doubles__5','Double menace','5 doublés','🎯','joueur','joueur_all_time','tier',true,'doubles',5,32),
('doubles__10','Récidiviste','10 doublés','🎯','joueur','joueur_all_time','tier',true,'doubles',10,33),
('doubles__25','Maître du doublé','25 doublés','🎯','joueur','joueur_all_time','tier',true,'doubles',25,34),
('max_match_goals__3','Pas content ?','Marquer 3 buts dans un match (triplé)','🎩','joueur','joueur_all_time','tier',true,'max_match_goals',3,35),
('max_match_goals__4','Carré d’as','Marquer 4 buts dans un match (quadruplé)','🎩','joueur','joueur_all_time','tier',true,'max_match_goals',4,36),
('max_match_goals__5','Main pleine','Marquer 5 buts dans un match (quintuplé)','🎩','joueur','joueur_all_time','tier',true,'max_match_goals',5,37),
('mvp__1','Homme du jour','1 homme du match en carrière','⭐','joueur','joueur_all_time','tier',true,'mvp',1,38),
('mvp__10','Décisif','10 hommes du match en carrière','⭐','joueur','joueur_all_time','tier',true,'mvp',10,39),
('mvp__20','Patron du match','20 hommes du match en carrière','⭐','joueur','joueur_all_time','tier',true,'mvp',20,40),
('mvp__50','Icône des rencontres','50 hommes du match en carrière','⭐','joueur','joueur_all_time','tier',true,'mvp',50,41),
('clean_sheets__5','Gants sûrs','5 clean sheets en carrière','🧤','joueur','joueur_all_time','tier',true,'clean_sheets',5,42),
('clean_sheets__10','Gardien de fer','10 clean sheets en carrière','🧤','joueur','joueur_all_time','tier',true,'clean_sheets',10,43),
('clean_sheets__20','Mur historique','20 clean sheets en carrière','🧤','joueur','joueur_all_time','tier',true,'clean_sheets',20,44),
('clean_sheets__30','Dernier rempart','30 clean sheets en carrière','🧤','joueur','joueur_all_time','tier',true,'clean_sheets',30,45),
('clean_sheets__50','Rideau d’acier','50 clean sheets en carrière','🧤','joueur','joueur_all_time','tier',true,'clean_sheets',50,46),
('seasons_complete__1','Saison sans absence','1 saison complète','📅','joueur','palmares','tier',true,'seasons_complete',1,47),
('seasons_complete__2','Toujours disponible','2 saisons complètes','📅','joueur','palmares','tier',true,'seasons_complete',2,48),
('seasons_complete__3','Fidèle au poste','3 saisons complètes','📅','joueur','palmares','tier',true,'seasons_complete',3,49),
('seasons_complete__4','Infatigable','4 saisons complètes','📅','joueur','palmares','tier',true,'seasons_complete',4,50),
('seasons_complete__5','Éternel présent','5 saisons complètes','📅','joueur','palmares','tier',true,'seasons_complete',5,51),
('title_most_present__1','Le plus assidu','1 saison en joueur le plus présent','📌','joueur','palmares','tier',true,'title_most_present',1,52),
('title_most_present__2','Incontournable','2 saisons en joueur le plus présent','📌','joueur','palmares','tier',true,'title_most_present',2,53),
('title_most_present__3','Abonné au terrain','3 saisons en joueur le plus présent','📌','joueur','palmares','tier',true,'title_most_present',3,54),
('title_most_present__4','Pilier des saisons','4 saisons en joueur le plus présent','📌','joueur','palmares','tier',true,'title_most_present',4,55),
('title_most_present__5','Monsieur Présence','5 saisons en joueur le plus présent','📌','joueur','palmares','tier',true,'title_most_present',5,56),
('title_top_scorer__1','Canon de la saison','1 saison en meilleur buteur','👑','joueur','palmares','tier',true,'title_top_scorer',1,57),
('title_top_scorer__2','Buteur récidiviste','2 saisons en meilleur buteur','👑','joueur','palmares','tier',true,'title_top_scorer',2,58),
('title_top_scorer__3','Roi des filets','3 saisons en meilleur buteur','👑','joueur','palmares','tier',true,'title_top_scorer',3,59),
('title_top_scorer__4','Empereur des buts','4 saisons en meilleur buteur','👑','joueur','palmares','tier',true,'title_top_scorer',4,60),
('title_top_scorer__5','Légende du classement','5 saisons en meilleur buteur','👑','joueur','palmares','tier',true,'title_top_scorer',5,61),
('title_mvp_king__1','Homme fort','1 saison avec le plus de HDM','⭐','joueur','palmares','tier',true,'title_mvp_king',1,62),
('title_mvp_king__2','Décisif encore','2 saisons avec le plus de HDM','⭐','joueur','palmares','tier',true,'title_mvp_king',2,63),
('title_mvp_king__3','Patron des matchs','3 saisons avec le plus de HDM','⭐','joueur','palmares','tier',true,'title_mvp_king',3,64),
('title_mvp_king__4','Roi des HDM','4 saisons avec le plus de HDM','⭐','joueur','palmares','tier',true,'title_mvp_king',4,65),
('title_mvp_king__5','Seigneur des rencontres','5 saisons avec le plus de HDM','⭐','joueur','palmares','tier',true,'title_mvp_king',5,66),
('title_best_winrate__1','Porte-bonheur','1 saison au meilleur taux de victoire','📈','joueur','palmares','tier',true,'title_best_winrate',1,67),
('title_best_winrate__2','Aimant à victoires','2 saisons au meilleur taux de victoire','📈','joueur','palmares','tier',true,'title_best_winrate',2,68),
('title_best_winrate__3','Talisman','3 saisons au meilleur taux de victoire','📈','joueur','palmares','tier',true,'title_best_winrate',3,69),
('title_best_winrate__4','Facteur victoire','4 saisons au meilleur taux de victoire','📈','joueur','palmares','tier',true,'title_best_winrate',4,70),
('title_best_winrate__5','Machine à gagner','5 saisons au meilleur taux de victoire','📈','joueur','palmares','tier',true,'title_best_winrate',5,71),
('pred_good_result__1','Premier bon coup','1 bonne issue en carrière','🎯','pronostiqueur','pronos_all_time','tier',true,'pred_good_result',1,72),
('pred_good_result__10','Œil juste','10 bonnes issues en carrière','🎯','pronostiqueur','pronos_all_time','tier',true,'pred_good_result',10,73),
('pred_good_result__25','Fin lecteur','25 bonnes issues en carrière','🎯','pronostiqueur','pronos_all_time','tier',true,'pred_good_result',25,74),
('pred_good_result__50','Visionnaire','50 bonnes issues en carrière','🎯','pronostiqueur','pronos_all_time','tier',true,'pred_good_result',50,75),
('pred_good_result__100','Oracle du 1N2','100 bonnes issues en carrière','🎯','pronostiqueur','pronos_all_time','tier',true,'pred_good_result',100,76),
('pred_exact_score__1','Premier exact','1 score exact en carrière','🔬','pronostiqueur','pronos_all_time','tier',true,'pred_exact_score',1,77),
('pred_exact_score__5','Dans le mille','5 scores exacts en carrière','🔬','pronostiqueur','pronos_all_time','tier',true,'pred_exact_score',5,78),
('pred_exact_score__10','Score chirurgical','10 scores exacts en carrière','🔬','pronostiqueur','pronos_all_time','tier',true,'pred_exact_score',10,79),
('pred_exact_score__25','Maître du score','25 scores exacts en carrière','🔬','pronostiqueur','pronos_all_time','tier',true,'pred_exact_score',25,80),
('pred_exact_score__50','Score absolu','50 scores exacts en carrière','🔬','pronostiqueur','pronos_all_time','tier',true,'pred_exact_score',50,81),
('title_best_pred_player__1','Scout de la saison','1 saison en meilleur pronostiqueur de stats joueurs','🔮','pronostiqueur','palmares','tier',true,'title_best_pred_player',1,82),
('title_best_pred_player__2','Analyste confirmé','2 saisons en meilleur pronostiqueur de stats joueurs','🔮','pronostiqueur','palmares','tier',true,'title_best_pred_player',2,83),
('title_best_pred_player__3','Décrypteur','3 saisons en meilleur pronostiqueur de stats joueurs','🔮','pronostiqueur','palmares','tier',true,'title_best_pred_player',3,84),
('title_best_pred_player__4','Maître des stats','4 saisons en meilleur pronostiqueur de stats joueurs','🔮','pronostiqueur','palmares','tier',true,'title_best_pred_player',4,85),
('title_best_pred_player__5','Oracle des joueurs','5 saisons en meilleur pronostiqueur de stats joueurs','🔮','pronostiqueur','palmares','tier',true,'title_best_pred_player',5,86),
('title_best_pred_match__1','Lecteur du jeu','1 saison en meilleur pronostiqueur de matchs','🔮','pronostiqueur','palmares','tier',true,'title_best_pred_match',1,87),
('title_best_pred_match__2','Stratège','2 saisons en meilleur pronostiqueur de matchs','🔮','pronostiqueur','palmares','tier',true,'title_best_pred_match',2,88),
('title_best_pred_match__3','Visionnaire des matchs','3 saisons en meilleur pronostiqueur de matchs','🔮','pronostiqueur','palmares','tier',true,'title_best_pred_match',3,89),
('title_best_pred_match__4','Maître du 1N2','4 saisons en meilleur pronostiqueur de matchs','🔮','pronostiqueur','palmares','tier',true,'title_best_pred_match',4,90),
('title_best_pred_match__5','Oracle des matchs','5 saisons en meilleur pronostiqueur de matchs','🔮','pronostiqueur','palmares','tier',true,'title_best_pred_match',5,91),
('title_best_pred_overall__1','Champion des pronos','1 saison en meilleur pronostiqueur cumulé','🏅','pronostiqueur','palmares','tier',true,'title_best_pred_overall',1,92),
('title_best_pred_overall__2','Double expertise','2 saisons en meilleur pronostiqueur cumulé','🏅','pronostiqueur','palmares','tier',true,'title_best_pred_overall',2,93),
('title_best_pred_overall__3','Grand analyste','3 saisons en meilleur pronostiqueur cumulé','🏅','pronostiqueur','palmares','tier',true,'title_best_pred_overall',3,94),
('title_best_pred_overall__4','Maître absolu','4 saisons en meilleur pronostiqueur cumulé','🏅','pronostiqueur','palmares','tier',true,'title_best_pred_overall',4,95),
('title_best_pred_overall__5','Légende des pronostics','5 saisons en meilleur pronostiqueur cumulé','🏅','pronostiqueur','palmares','tier',true,'title_best_pred_overall',5,96);
drop function if exists public.profile_badge_metrics(uuid);

create function public.profile_badge_metrics(p_profile_id uuid)
returns table(
  matches_played_season integer, wins_season integer, goals_season integer,
  clean_sheets_season integer,
  matches_played integer, wins integer, goals integer,
  doubles integer, max_match_goals integer, mvp integer, clean_sheets integer,
  pred_good_result integer, pred_exact_score integer
)
language sql
security definer
set search_path to 'public'
as $$
  with pm as (
    select m.season_id,
           (m.score_as_grinta > m.score_adverse) as win,
           coalesce(st.goals, 0) as g,
           coalesce(st.clean_sheet, false) as cs,
           (mv.season_player_id is not null) as is_mvp
    from public.season_players sp
    join public.matches m
      on m.season_id = sp.season_id and m.status in ('termine', 'archive')
    left join public.match_player_stats st
      on st.season_player_id = sp.id and st.match_id = m.id
    left join public.match_attendance att
      on att.season_player_id = sp.id and att.match_id = m.id
    left join public.match_man_of_match mv
      on mv.season_player_id = sp.id and mv.match_id = m.id
    where sp.profile_id = p_profile_id
      and (st.match_id is not null or att.match_id is not null or mv.match_id is not null)
  ), ps as (
    select season_id,
           count(*) as mp,
           count(*) filter (where win) as w,
           sum(g) as gg,
           count(*) filter (where cs) as csn,
           count(*) filter (where is_mvp) as mvpn,
           count(*) filter (where g = 2) as dbl
    from pm group by season_id
  ), player as (
    select
      coalesce(max(mp), 0)::int as matches_played_season,
      coalesce(max(w), 0)::int as wins_season,
      coalesce(max(gg), 0)::int as goals_season,
      coalesce(max(csn), 0)::int as clean_sheets_season,
      coalesce(sum(mp), 0)::int as matches_played,
      coalesce(sum(w), 0)::int as wins,
      coalesce(sum(gg), 0)::int as goals,
      coalesce(sum(dbl), 0)::int as doubles,
      coalesce(sum(mvpn), 0)::int as mvp,
      coalesce(sum(csn), 0)::int as clean_sheets
    from ps
  ), pmax as (
    select coalesce(max(g), 0)::int as max_match_goals from pm
  ), mpred as (
    select
      (mp.is_filled and sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
        = sign((m.score_as_grinta - m.score_adverse)::numeric))::int as bon,
      (mp.is_filled and mp.predicted_score_as_grinta = m.score_as_grinta
        and mp.predicted_score_adverse = m.score_adverse)::int as ex
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id and m.status in ('termine', 'archive')
    where mp.profile_id = p_profile_id
  ), mpred_a as (
    select coalesce(sum(bon), 0)::int as pred_good_result,
           coalesce(sum(ex), 0)::int as pred_exact_score
    from mpred
  )
  select
    player.matches_played_season, player.wins_season, player.goals_season,
    player.clean_sheets_season,
    player.matches_played, player.wins, player.goals,
    player.doubles, pmax.max_match_goals, player.mvp, player.clean_sheets,
    mpred_a.pred_good_result, mpred_a.pred_exact_score
  from player, pmax, mpred_a;
$$;

revoke execute on function public.profile_badge_metrics(uuid) from public, anon;
grant execute on function public.profile_badge_metrics(uuid) to authenticated;

select public.recalculate_all_badges();
