-- Réalignement exact du catalogue automatique sur le barème final :
-- stats à 4 paliers, badges spéciaux à 1 palier. Les 11 exploits manuels
-- (kind='custom') ne sont pas touchés.
create temporary table _target_tier(
  code text primary key, name text, description text, emoji text,
  family text, category text, metric text, threshold int, sort_order int
) on commit drop;

insert into _target_tier values
  -- 1. Présences
  ('matches_played_season__15','15 présences','15 présences sur une saison','📅','joueur','joueur_saison','matches_played_season',15,100),
  ('matches_played_season__20','20 présences','20 présences sur une saison','📅','joueur','joueur_saison','matches_played_season',20,101),
  ('matches_played_season__25','25 présences','25 présences sur une saison','📅','joueur','joueur_saison','matches_played_season',25,102),
  ('matches_played_season__30','30 présences','30 présences sur une saison','📅','joueur','joueur_saison','matches_played_season',30,103),
  ('matches_played__150','150 présences','150 présences en tout','📅','joueur','joueur_all_time','matches_played',150,104),
  ('matches_played__200','200 présences','200 présences en tout','📅','joueur','joueur_all_time','matches_played',200,105),
  ('matches_played__250','250 présences','250 présences en tout','📅','joueur','joueur_all_time','matches_played',250,106),
  ('matches_played__300','300 présences','300 présences en tout','📅','joueur','joueur_all_time','matches_played',300,107),
  -- 2. Buts
  ('goals_season__5','5 buts','5 buts sur une saison','⚽','joueur','joueur_saison','goals_season',5,110),
  ('goals_season__10','10 buts','10 buts sur une saison','⚽','joueur','joueur_saison','goals_season',10,111),
  ('goals_season__20','20 buts','20 buts sur une saison','⚽','joueur','joueur_saison','goals_season',20,112),
  ('goals_season__30','30 buts','30 buts sur une saison','⚽','joueur','joueur_saison','goals_season',30,113),
  ('goals__25','25 buts','25 buts en tout','⚽','joueur','joueur_all_time','goals',25,114),
  ('goals__50','50 buts','50 buts en tout','⚽','joueur','joueur_all_time','goals',50,115),
  ('goals__75','75 buts','75 buts en tout','⚽','joueur','joueur_all_time','goals',75,116),
  ('goals__100','100 buts','100 buts en tout','⚽','joueur','joueur_all_time','goals',100,117),
  -- 3. Victoires
  ('wins_season__10','10 victoires','10 victoires sur une saison','🏆','joueur','joueur_saison','wins_season',10,120),
  ('wins_season__15','15 victoires','15 victoires sur une saison','🏆','joueur','joueur_saison','wins_season',15,121),
  ('wins_season__20','20 victoires','20 victoires sur une saison','🏆','joueur','joueur_saison','wins_season',20,122),
  ('wins_season__25','25 victoires','25 victoires sur une saison','🏆','joueur','joueur_saison','wins_season',25,123),
  ('wins__50','50 victoires','50 victoires en tout','🏆','joueur','joueur_all_time','wins',50,124),
  ('wins__100','100 victoires','100 victoires en tout','🏆','joueur','joueur_all_time','wins',100,125),
  ('wins__150','150 victoires','150 victoires en tout','🏆','joueur','joueur_all_time','wins',150,126),
  ('wins__200','200 victoires','200 victoires en tout','🏆','joueur','joueur_all_time','wins',200,127),
  -- 4. Clean sheets
  ('clean_sheets_season__3','3 clean sheets','3 clean sheets sur une saison','🧤','joueur','joueur_saison','clean_sheets_season',3,130),
  ('clean_sheets_season__5','5 clean sheets','5 clean sheets sur une saison','🧤','joueur','joueur_saison','clean_sheets_season',5,131),
  ('clean_sheets_season__7','7 clean sheets','7 clean sheets sur une saison','🧤','joueur','joueur_saison','clean_sheets_season',7,132),
  ('clean_sheets_season__10','10 clean sheets','10 clean sheets sur une saison','🧤','joueur','joueur_saison','clean_sheets_season',10,133),
  ('clean_sheets__15','15 clean sheets','15 clean sheets en tout','🧤','joueur','joueur_all_time','clean_sheets',15,134),
  ('clean_sheets__25','25 clean sheets','25 clean sheets en tout','🧤','joueur','joueur_all_time','clean_sheets',25,135),
  ('clean_sheets__50','50 clean sheets','50 clean sheets en tout','🧤','joueur','joueur_all_time','clean_sheets',50,136),
  ('clean_sheets__100','100 clean sheets','100 clean sheets en tout','🧤','joueur','joueur_all_time','clean_sheets',100,137),
  -- 5. Doublés
  ('doubles__10','10 doublés','10 doublés en tout','✌️','joueur','joueur_all_time','doubles',10,140),
  ('doubles__20','20 doublés','20 doublés en tout','✌️','joueur','joueur_all_time','doubles',20,141),
  ('doubles__30','30 doublés','30 doublés en tout','✌️','joueur','joueur_all_time','doubles',30,142),
  ('doubles__50','50 doublés','50 doublés en tout','✌️','joueur','joueur_all_time','doubles',50,143),
  -- 6. HDM
  ('mvp__10','10 HDM','10 HDM en tout','⭐','joueur','joueur_all_time','mvp',10,150),
  ('mvp__20','20 HDM','20 HDM en tout','⭐','joueur','joueur_all_time','mvp',20,151),
  ('mvp__30','30 HDM','30 HDM en tout','⭐','joueur','joueur_all_time','mvp',30,152),
  ('mvp__50','50 HDM','50 HDM en tout','⭐','joueur','joueur_all_time','mvp',50,153),
  -- 17-19. Triplé / quadruplé / quintuplé
  ('max_match_goals__3','Triplé','Marquer un triplé dans un match.','🎩','joueur','joueur_all_time','max_match_goals',3,160),
  ('max_match_goals__4','Quadruplé','Marquer un quadruplé dans un match.','🃏','joueur','joueur_all_time','max_match_goals',4,161),
  ('max_match_goals__5','Quintuplé','Marquer un quintuplé dans un match.','👑','joueur','joueur_all_time','max_match_goals',5,162),
  -- 7. Bons résultats
  ('pred_good_result__15','15 bons résultats','15 bons résultats en tout','✅','pronostiqueur','pronos_all_time','pred_good_result',15,170),
  ('pred_good_result__30','30 bons résultats','30 bons résultats en tout','✅','pronostiqueur','pronos_all_time','pred_good_result',30,171),
  ('pred_good_result__50','50 bons résultats','50 bons résultats en tout','✅','pronostiqueur','pronos_all_time','pred_good_result',50,172),
  ('pred_good_result__100','100 bons résultats','100 bons résultats en tout','✅','pronostiqueur','pronos_all_time','pred_good_result',100,173),
  -- 8. Bons scores
  ('pred_exact_score__10','10 bons scores','10 bons scores en tout','💯','pronostiqueur','pronos_all_time','pred_exact_score',10,180),
  ('pred_exact_score__20','20 bons scores','20 bons scores en tout','💯','pronostiqueur','pronos_all_time','pred_exact_score',20,181),
  ('pred_exact_score__30','30 bons scores','30 bons scores en tout','💯','pronostiqueur','pronos_all_time','pred_exact_score',30,182),
  ('pred_exact_score__50','50 bons scores','50 bons scores en tout','💯','pronostiqueur','pronos_all_time','pred_exact_score',50,183),
  -- 9-16. Palmarès (1 palier)
  ('seasons_complete__1','Saison sans absence','N''a loupé aucun match d''une saison.','📌','joueur','palmares','seasons_complete',1,190),
  ('title_most_present__1','Le plus assidu','Joueur le plus présent d''une saison.','🧲','joueur','palmares','title_most_present',1,191),
  ('title_top_scorer__1','Meilleur buteur','Meilleur buteur d''une saison.','👟','joueur','palmares','title_top_scorer',1,192),
  ('title_best_winrate__1','Meilleur taux de victoire','Meilleur taux de victoire d''une saison.','📈','joueur','palmares','title_best_winrate',1,193),
  ('title_mvp_king__1','Roi des HDM','Le plus d''HDM sur une saison.','👑','joueur','palmares','title_mvp_king',1,194),
  ('title_best_pred_player__1','Scout de la saison','Meilleur pronostiqueur des stats joueurs.','🔎','pronostiqueur','palmares','title_best_pred_player',1,200),
  ('title_best_pred_match__1','Pronostiqueur de matchs','Meilleur pronostiqueur de matchs d''une saison.','🎯','pronostiqueur','palmares','title_best_pred_match',1,201),
  ('title_best_pred_overall__1','Champion des pronos','Meilleur pronostiqueur cumulé d''une saison.','🏅','pronostiqueur','palmares','title_best_pred_overall',1,202);

-- Upsert des paliers cibles.
insert into public.badges (code,name,description,emoji,image_url,family,auto,kind,category,metric,threshold,sort_order)
select code,name,description,emoji,null,family,true,'tier',category,metric,threshold,sort_order from _target_tier
on conflict (code) do update set
  name=excluded.name, description=excluded.description, emoji=excluded.emoji,
  family=excluded.family, category=excluded.category, metric=excluded.metric,
  threshold=excluded.threshold, sort_order=excluded.sort_order, auto=true, kind='tier';

-- Retrait des attributions puis des paliers obsolètes.
delete from public.profile_badges pb using public.badges b
where pb.badge_id=b.id and b.kind='tier' and b.code not in (select code from _target_tier);

delete from public.badges
where kind='tier' and code not in (select code from _target_tier);
