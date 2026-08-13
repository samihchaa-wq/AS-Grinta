-- Bug 9 : les statistiques affichees sont incoherentes avec elles-memes.
--
-- L'onglet Statistiques -> Equipe annonce « 317 matchs joues — 211 victoires,
-- 46 nuls, 56 defaites », or 211 + 46 + 56 = 313. La table de verite
-- `historical_match_scores` contient exactement 313 lignes, toutes avec un
-- score, reparties en 211 V / 46 N / 56 D : c'est bien `matches_played` qui est
-- faux, et les pourcentages affiches (67 / 15 / 18 %) etaient calcules sur 317
-- tout en decrivant 313 matchs.
--
-- Meme defaut cote joueurs : 40 lignes sur 114 avaient
-- `matches_played <> wins + draws + losses`, avec un ecart toujours positif
-- compris entre 1 et 4 — des matchs comptes a l'import sans resultat classe.
--
-- Le decompte des resultats est la seule donnee recoupable (elle correspond
-- exactement a la table de verite cote equipe), donc `matches_played` est
-- recalcule depuis lui. Une contrainte empeche desormais la divergence de
-- revenir silencieusement.

begin;

update public.historical_team_statistics
set matches_played = wins + draws + losses
where matches_played is distinct from wins + draws + losses;

update public.historical_player_statistics
set matches_played = wins + draws + losses
where matches_played is distinct from wins + draws + losses;

alter table public.historical_team_statistics
  drop constraint if exists historical_team_statistics_matches_played_check;
alter table public.historical_team_statistics
  add constraint historical_team_statistics_matches_played_check
  check (matches_played = wins + draws + losses);

alter table public.historical_player_statistics
  drop constraint if exists historical_player_statistics_matches_played_check;
alter table public.historical_player_statistics
  add constraint historical_player_statistics_matches_played_check
  check (matches_played = wins + draws + losses);

commit;
