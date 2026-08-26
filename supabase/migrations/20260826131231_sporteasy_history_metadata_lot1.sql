-- Lot 1 de l'import SportEasy : complete l'archive avec l'heure de coup
-- d'envoi, l'adresse, le type de match et la journee de championnat.
--
-- Ces quatre colonnes ont ete ajoutees vides le 2026-08-26 en prevision d'un
-- import plus riche. Elles sont remplies ici a partir du releve SportEasy du
-- 2026-08-26 (tool/sporteasy/data/matches_full.json).
--
-- Aucun score, aucun joueur, aucun classement n'est touche : le releve est
-- identique a l'archive sur ces points, verification faite match par match
-- (dates, scores, domicile, effectif present, buteurs, hommes du match,
-- compositions et formations : zero ecart sur les 313 rencontres).
--
-- Les 313 rencontres se repartissent en 157 championnats et 156 amicaux.
-- Aucune n'est de type inconnu, aucune n'est un match entre nous : les
-- 4 rencontres internes avec score restent hors de l'archive tant que
-- historical_match_scores exige un adversaire.
--
-- Saison 2022-2023 : la numerotation des journees repart a J1 en mars 2023.
-- C'est la source qui le dit, le championnat ayant eu deux phases cette
-- saison-la. Les numeros sont repris tels quels plutot que renumerotes en
-- continu, pour ne pas inventer une numerotation que le club n'a pas utilisee.
--
-- Appliquee en production le 2026-08-26 sous la version 20260826131231.
-- Comptes verifies apres coup : 313 heures, 313 adresses, 157 championnats,
-- 156 amicaux, 157 journees. Les scores, les 3953 lignes de joueurs, les
-- 1196 buts, les 114 classements et les 42 adversaires sont inchanges.
--
-- Le rapprochement se fait par date : les 313 rencontres archivees ont
-- 313 dates distinctes, ce que le garde-fou ci-dessous revalide avant toute
-- ecriture.

do $prealable$
declare
  v_lignes integer;
  v_dates integer;
begin
  select count(*), count(distinct match_date) into v_lignes, v_dates
  from public.historical_match_scores;
  if v_lignes <> v_dates then
    raise exception 'Lot 1 : % rencontres pour % dates, le rapprochement par date n''est pas fiable', v_lignes, v_dates;
  end if;
end;
$prealable$;

with lieu(code, adresse) as (
  values
    (1, '20 Chemin de Garric, 31200 Toulouse, France'),
    (2, 'Chemin des Côtes de Pech David, 31400 Toulouse, France'),
    (3, 'Rue des Cyclamens, 31700 Blagnac, France'),
    (4, 'Allée de la Colombe, 31770 Colomiers, France'),
    (5, 'Chemin des Garrosses, 31180 Rouffiac-Tolosan, France'),
    (6, '153 Avenue de Lardenne, 31100 Toulouse, France'),
    (7, 'Impasse Barthe, 31200 Toulouse, France'),
    (8, 'Chemin de la Cepière, 31100 Toulouse, France'),
    (9, 'Rte du Stade, 31700 Cornebarrieu, France'),
    (10, 'Rue de Rabastens, 31500 Toulouse, France'),
    (11, '8 bis Rue Claudius Rougenet, 31500 Toulouse, France'),
    (12, 'Avenue Jean Mermoz, 31140 Fonbeauzard, France'),
    (13, 'Avenue de Lattre de Tassigny, 31400 Toulouse, France'),
    (14, 'Chemin du Dr Louis Delherm, 31320 Auzeville-Tolosane, France'),
    (15, '2 Boulevard des Écoles, 31820 Pibrac, France'),
    (16, '110 Avenue du Marquisat, 31170 Tournefeuille, France'),
    (17, 'Boulevard Als Cambiots, 31130 Balma, France'),
    (18, 'Rue du Stade, 31490 Brax, France'),
    (19, '17 Chemin de la Saudrune, 31100 Toulouse, France'),
    (20, 'Allée des Sports, 31170 Tournefeuille, France'),
    (21, '223 Rue des Arts, 31670 Labège, France'),
    (22, '8 Rue Claudius Rougenet, 31500 Toulouse, France')
), source(match_date, lieu_code, match_time, match_type, championship_round) as (
  values
    ('2014-04-24', 1, '19:30', 'amical', null),
    ('2014-05-13', 2, '20:00', 'championnat', 21),
    ('2014-05-27', 3, '20:15', 'amical', null),
    ('2014-06-02', 4, '20:00', 'amical', null),
    ('2014-06-12', 5, '20:15', 'amical', null),
    ('2014-09-25', 5, '20:00', 'amical', null),
    ('2014-10-06', 4, '20:00', 'championnat', 1),
    ('2014-10-14', 3, '20:00', 'championnat', 2),
    ('2014-10-21', 3, '20:00', 'amical', null),
    ('2014-11-05', 6, '20:00', 'championnat', 3),
    ('2014-11-13', 5, '20:00', 'amical', null),
    ('2014-11-17', 4, '20:00', 'championnat', 4),
    ('2014-11-26', 7, '20:00', 'championnat', 5),
    ('2014-12-02', 8, '20:00', 'championnat', 6),
    ('2014-12-08', 4, '20:00', 'championnat', 7),
    ('2014-12-15', 4, '20:00', 'championnat', 8),
    ('2015-01-12', 9, '20:00', 'amical', null),
    ('2015-01-27', 10, '20:00', 'championnat', 10),
    ('2015-02-13', 11, '20:00', 'amical', null),
    ('2015-02-23', 4, '20:00', 'championnat', 12),
    ('2015-03-09', 4, '20:00', 'championnat', 14),
    ('2015-03-16', 4, '20:00', 'championnat', 15),
    ('2015-03-24', 10, '20:00', 'championnat', 16),
    ('2015-03-30', 12, '20:15', 'championnat', 17),
    ('2015-04-20', 4, '20:00', 'amical', null),
    ('2015-04-28', 3, '20:00', 'amical', null),
    ('2015-05-05', 8, '20:00', 'amical', null),
    ('2015-05-11', 4, '20:00', 'amical', null),
    ('2015-05-28', 13, '20:00', 'amical', null),
    ('2015-09-14', 9, '20:00', 'amical', null),
    ('2015-09-21', 4, '20:00', 'amical', null),
    ('2015-10-01', 5, '20:00', 'amical', null),
    ('2015-10-05', 4, '20:00', 'amical', null),
    ('2015-10-12', 4, '20:00', 'championnat', 2),
    ('2015-10-22', 5, '20:00', 'championnat', 1),
    ('2015-11-13', 11, '20:00', 'amical', null),
    ('2015-11-17', 8, '20:00', 'championnat', 4),
    ('2015-12-02', 6, '20:00', 'championnat', 6),
    ('2015-12-07', 4, '20:00', 'championnat', 7),
    ('2015-12-15', 3, '20:00', 'championnat', 8),
    ('2016-02-08', 4, '20:00', 'championnat', 11),
    ('2016-02-15', 4, '20:00', 'championnat', 12),
    ('2016-02-23', 3, '20:00', 'amical', null),
    ('2016-03-07', 4, '20:00', 'championnat', 13),
    ('2016-03-14', 12, '20:30', 'championnat', 14),
    ('2016-03-21', 4, '20:00', 'championnat', 15),
    ('2016-03-29', 1, '20:30', 'amical', null),
    ('2016-04-05', 2, '20:00', 'championnat', 16),
    ('2016-04-21', 5, '20:00', 'championnat', 10),
    ('2016-04-25', 12, '20:30', 'championnat', 5),
    ('2016-05-02', 4, '20:15', 'amical', null),
    ('2016-05-09', 4, '20:00', 'championnat', 18),
    ('2016-05-19', 1, '20:30', 'amical', null),
    ('2016-05-23', 4, '20:00', 'amical', null),
    ('2016-06-03', 11, '19:30', 'amical', null),
    ('2016-06-20', 4, '20:15', 'amical', null),
    ('2016-09-12', 9, '20:00', 'amical', null),
    ('2016-09-19', 4, '20:00', 'amical', null),
    ('2016-09-26', 4, '20:00', 'amical', null),
    ('2016-10-03', 4, '20:00', 'championnat', 1),
    ('2016-10-11', 2, '20:00', 'championnat', 2),
    ('2016-10-17', 4, '20:00', 'amical', null),
    ('2016-10-24', 14, '20:30', 'amical', null),
    ('2016-11-08', 1, '20:30', 'amical', null),
    ('2016-11-14', 4, '20:00', 'championnat', 3),
    ('2016-11-23', 15, '20:30', 'championnat', 4),
    ('2016-11-28', 4, '20:00', 'championnat', 5),
    ('2016-12-05', 4, '20:00', 'championnat', 6),
    ('2016-12-13', 8, '20:00', 'championnat', 7),
    ('2017-01-09', 4, '20:00', 'championnat', 8),
    ('2017-01-23', 4, '20:00', 'amical', null),
    ('2017-01-27', 15, '20:30', 'amical', null),
    ('2017-02-02', 16, '20:00', 'championnat', 10),
    ('2017-02-20', 4, '20:00', 'championnat', 11),
    ('2017-02-27', 4, '20:00', 'championnat', 12),
    ('2017-03-16', 7, '20:00', 'championnat', 14),
    ('2017-03-27', 4, '20:00', 'championnat', 16),
    ('2017-04-18', 1, '20:30', 'amical', null),
    ('2017-04-24', 7, '20:00', 'championnat', 17),
    ('2017-05-15', 17, '19:50', 'amical', null),
    ('2017-05-22', 4, '20:00', 'amical', null),
    ('2017-06-12', 7, '20:00', 'amical', null),
    ('2017-06-19', 4, '20:00', 'amical', null),
    ('2017-09-11', 4, '20:00', 'amical', null),
    ('2017-09-21', 5, '20:00', 'amical', null),
    ('2017-09-26', 8, '20:15', 'amical', null),
    ('2017-10-02', 4, '20:00', 'championnat', 1),
    ('2017-10-10', 2, '20:00', 'championnat', 2),
    ('2017-10-16', 4, '20:00', 'championnat', 3),
    ('2017-10-30', 17, '20:00', 'amical', null),
    ('2017-11-06', 18, '20:00', 'amical', null),
    ('2017-11-16', 5, '20:00', 'championnat', 4),
    ('2017-11-20', 4, '20:00', 'championnat', 5),
    ('2017-11-28', 1, '20:30', 'amical', null),
    ('2017-12-18', 4, '20:00', 'amical', null),
    ('2018-01-10', 15, '21:00', 'championnat', 7),
    ('2018-01-15', 4, '20:00', 'amical', null),
    ('2018-01-29', 14, '20:30', 'amical', null),
    ('2018-02-05', 7, '20:00', 'championnat', 8),
    ('2018-02-12', 4, '20:00', 'championnat', 9),
    ('2018-03-15', 5, '20:00', 'championnat', 11),
    ('2018-04-10', 3, '20:00', 'championnat', 13),
    ('2018-04-18', 6, '20:00', 'amical', null),
    ('2018-04-26', 8, '20:30', 'amical', null),
    ('2018-05-22', 1, '20:30', 'amical', null),
    ('2018-06-04', 4, '20:00', 'amical', null),
    ('2018-06-11', 4, '20:00', 'amical', null),
    ('2018-06-18', 17, '20:00', 'amical', null),
    ('2018-09-18', 8, '20:00', 'amical', null),
    ('2018-09-27', 5, '20:30', 'amical', null),
    ('2018-10-01', 4, '20:00', 'championnat', 1),
    ('2018-10-09', 2, '20:00', 'championnat', 2),
    ('2018-10-17', 3, '20:15', 'championnat', 3),
    ('2018-10-29', 4, '20:00', 'amical', null),
    ('2018-11-08', 5, '20:30', 'championnat', 4),
    ('2018-11-19', 4, '20:00', 'championnat', 6),
    ('2018-12-03', 4, '20:00', 'amical', null),
    ('2018-12-10', 4, '20:00', 'amical', null),
    ('2019-01-07', 4, '20:00', 'amical', null),
    ('2019-01-14', 4, '20:00', 'amical', null),
    ('2019-01-21', 17, '20:00', 'amical', null),
    ('2019-02-04', 4, '20:00', 'amical', null),
    ('2019-02-28', 1, '20:30', 'amical', null),
    ('2019-03-11', 4, '20:00', 'championnat', 10),
    ('2019-03-21', 5, '20:00', 'championnat', 11),
    ('2019-03-28', 19, '20:00', 'championnat', 12),
    ('2019-04-02', 8, '20:00', 'championnat', 13),
    ('2019-04-08', 4, '20:00', 'championnat', 14),
    ('2019-04-15', 18, '20:00', 'amical', null),
    ('2019-04-29', 4, '20:00', 'amical', null),
    ('2019-05-14', 1, '20:30', 'amical', null),
    ('2019-05-27', 4, '20:00', 'amical', null),
    ('2019-06-06', 8, '20:00', 'amical', null),
    ('2019-06-24', 4, '20:00', 'amical', null),
    ('2019-09-12', 5, '20:30', 'amical', null),
    ('2019-09-18', 15, '21:00', 'amical', null),
    ('2019-09-23', 4, '20:00', 'amical', null),
    ('2019-09-30', 4, '20:00', 'championnat', 1),
    ('2019-10-08', 8, '20:00', 'championnat', 2),
    ('2019-10-14', 20, '20:30', 'championnat', 3),
    ('2019-10-21', 4, '20:00', 'amical', null),
    ('2019-10-28', 17, '20:00', 'amical', null),
    ('2019-11-07', 1, '20:30', 'championnat', 4),
    ('2019-11-20', 15, '20:30', 'amical', null),
    ('2019-11-25', 4, '20:00', 'championnat', 5),
    ('2019-12-02', 9, '20:00', 'championnat', 6),
    ('2020-01-16', 5, '20:00', 'championnat', 8),
    ('2020-01-29', 6, '20:00', 'amical', null),
    ('2020-02-03', 4, '20:00', 'amical', null),
    ('2020-02-13', 5, '20:00', 'amical', null),
    ('2020-02-24', 4, '20:00', 'championnat', 10),
    ('2020-03-09', 20, '20:30', 'championnat', 12),
    ('2020-09-29', 1, '20:30', 'championnat', 1),
    ('2020-10-05', 15, '21:00', 'championnat', 2),
    ('2020-10-12', 20, '21:00', 'championnat', 3),
    ('2021-06-17', 21, '20:00', 'amical', null),
    ('2021-06-24', 21, '20:00', 'amical', null),
    ('2021-09-09', 21, '21:00', 'amical', null),
    ('2021-09-16', 21, '21:00', 'amical', null),
    ('2021-09-23', 21, '21:00', 'amical', null),
    ('2021-09-29', 15, '20:30', 'amical', null),
    ('2021-10-07', 21, '21:00', 'amical', null),
    ('2021-10-14', 21, '21:00', 'championnat', 1),
    ('2021-10-21', 5, '20:00', 'championnat', 2),
    ('2021-10-28', 5, '20:00', 'amical', null),
    ('2021-11-09', 1, '20:30', 'championnat', 3),
    ('2021-11-18', 21, '21:00', 'amical', null),
    ('2021-12-16', 21, '21:00', 'championnat', 6),
    ('2022-01-05', 15, '20:30', 'amical', null),
    ('2022-01-13', 21, '21:00', 'championnat', 7),
    ('2022-01-20', 21, '21:00', 'championnat', 8),
    ('2022-01-27', 8, '20:00', 'amical', null),
    ('2022-02-02', 22, '20:30', 'championnat', 9),
    ('2022-02-10', 5, '20:30', 'championnat', 10),
    ('2022-02-17', 21, '21:00', 'championnat', 11),
    ('2022-02-24', 21, '21:00', 'amical', null),
    ('2022-03-10', 21, '21:00', 'championnat', 12),
    ('2022-04-07', 21, '21:00', 'championnat', 15),
    ('2022-04-14', 21, '21:00', 'amical', null),
    ('2022-04-19', 1, '20:30', 'amical', null),
    ('2022-05-03', 8, '20:00', 'amical', null),
    ('2022-05-11', 11, '20:45', 'championnat', 17),
    ('2022-05-19', 21, '21:00', 'amical', null),
    ('2022-06-01', 11, '20:30', 'amical', null),
    ('2022-06-09', 21, '21:00', 'amical', null),
    ('2022-06-16', 21, '21:00', 'amical', null),
    ('2022-06-23', 21, '21:00', 'amical', null),
    ('2022-06-30', 21, '21:00', 'amical', null),
    ('2022-09-21', 11, '20:30', 'amical', null),
    ('2022-09-29', 21, '21:00', 'amical', null),
    ('2022-10-04', 1, '20:30', 'amical', null),
    ('2022-10-13', 5, '20:30', 'amical', null),
    ('2022-10-19', 11, '20:30', 'championnat', 1),
    ('2022-10-27', 21, '21:00', 'championnat', 2),
    ('2022-11-03', 1, '20:30', 'championnat', 3),
    ('2022-11-07', 9, '20:30', 'championnat', 4),
    ('2022-11-17', 21, '21:00', 'championnat', 5),
    ('2022-11-24', 21, '21:00', 'championnat', 6),
    ('2022-12-01', 21, '21:00', 'championnat', 7),
    ('2022-12-15', 1, '20:30', 'championnat', 9),
    ('2023-01-05', 21, '21:00', 'championnat', 8),
    ('2023-01-11', 11, '20:30', 'amical', null),
    ('2023-01-19', 21, '21:00', 'championnat', 10),
    ('2023-01-25', 15, '20:30', 'championnat', 11),
    ('2023-02-02', 1, '20:30', 'championnat', 12),
    ('2023-02-09', 21, '21:00', 'championnat', 13),
    ('2023-02-16', 21, '21:00', 'championnat', 14),
    ('2023-02-21', 1, '20:30', 'amical', null),
    ('2023-03-07', 8, '20:15', 'championnat', 1),
    ('2023-03-15', 11, '20:45', 'championnat', 2),
    ('2023-03-23', 21, '21:00', 'amical', null),
    ('2023-03-30', 21, '21:00', 'championnat', 3),
    ('2023-04-06', 1, '20:30', 'championnat', 4),
    ('2023-04-11', 1, '20:30', 'amical', null),
    ('2023-04-19', 15, '20:30', 'championnat', 5),
    ('2023-05-03', 11, '20:30', 'amical', null),
    ('2023-05-11', 21, '21:00', 'championnat', 6),
    ('2023-05-25', 21, '21:00', 'championnat', 7),
    ('2023-06-01', 21, '21:00', 'amical', null),
    ('2023-06-08', 21, '21:00', 'amical', null),
    ('2023-06-15', 21, '21:00', 'amical', null),
    ('2023-06-22', 21, '21:00', 'amical', null),
    ('2023-06-28', 11, '20:30', 'amical', null),
    ('2023-10-04', 11, '20:30', 'amical', null),
    ('2023-10-12', 21, '21:00', 'championnat', 1),
    ('2023-10-19', 21, '21:00', 'championnat', 2),
    ('2023-10-24', 1, '20:30', 'amical', null),
    ('2023-11-06', 17, '20:45', 'amical', null),
    ('2023-11-16', 21, '21:00', 'amical', null),
    ('2023-11-20', 9, '20:00', 'championnat', 4),
    ('2023-11-30', 21, '21:00', 'amical', null),
    ('2023-12-07', 21, '21:00', 'championnat', 5),
    ('2023-12-14', 1, '20:30', 'championnat', 6),
    ('2023-12-21', 21, '21:00', 'amical', null),
    ('2024-01-11', 21, '21:00', 'amical', null),
    ('2024-01-15', 20, '20:15', 'championnat', 7),
    ('2024-01-25', 21, '21:00', 'championnat', 8),
    ('2024-02-01', 5, '20:30', 'amical', null),
    ('2024-02-08', 21, '21:00', 'championnat', 9),
    ('2024-02-15', 21, '21:00', 'amical', null),
    ('2024-02-20', 1, '20:30', 'amical', null),
    ('2024-02-26', 9, '20:30', 'championnat', 10),
    ('2024-03-07', 21, '21:00', 'championnat', 11),
    ('2024-03-14', 21, '21:00', 'amical', null),
    ('2024-03-21', 1, '20:30', 'championnat', 12),
    ('2024-03-28', 21, '21:00', 'amical', null),
    ('2024-04-04', 21, '21:00', 'amical', null),
    ('2024-04-09', 1, '20:30', 'amical', null),
    ('2024-04-25', 21, '21:00', 'championnat', 13),
    ('2024-05-27', 9, '22:00', 'amical', null),
    ('2024-06-06', 21, '21:00', 'amical', null),
    ('2024-06-12', 11, '20:30', 'amical', null),
    ('2024-06-26', 11, '20:30', 'amical', null),
    ('2024-09-19', 21, '21:00', 'amical', null),
    ('2024-09-26', 21, '21:00', 'amical', null),
    ('2024-10-03', 21, '21:00', 'amical', null),
    ('2024-10-07', 9, '20:30', 'amical', null),
    ('2024-10-17', 11, '21:15', 'championnat', 1),
    ('2024-10-24', 21, '21:00', 'amical', null),
    ('2024-10-29', 1, '20:30', 'amical', null),
    ('2024-11-05', 1, '20:30', 'championnat', 2),
    ('2024-11-14', 21, '21:00', 'championnat', 3),
    ('2024-11-21', 21, '21:00', 'amical', null),
    ('2024-11-28', 5, '20:30', 'championnat', 5),
    ('2024-12-02', 9, '20:30', 'championnat', 6),
    ('2024-12-19', 1, '20:30', 'championnat', 8),
    ('2025-01-09', 11, '21:15', 'amical', null),
    ('2025-01-16', 21, '21:00', 'championnat', 9),
    ('2025-01-23', 21, '21:00', 'championnat', 10),
    ('2025-01-30', 21, '21:00', 'championnat', 11),
    ('2025-02-13', 21, '21:00', 'championnat', 13),
    ('2025-02-20', 21, '21:00', 'amical', null),
    ('2025-03-04', 1, '20:30', 'championnat', 14),
    ('2025-03-13', 21, '21:00', 'championnat', 15),
    ('2025-03-27', 5, '20:30', 'championnat', 17),
    ('2025-03-31', 9, '20:30', 'championnat', 18),
    ('2025-04-10', 21, '21:00', 'championnat', 19),
    ('2025-04-17', 11, '21:15', 'amical', null),
    ('2025-04-28', 17, '20:30', 'amical', null),
    ('2025-05-06', 1, '20:30', 'amical', null),
    ('2025-05-22', 11, '21:15', 'amical', null),
    ('2025-06-02', 17, '20:30', 'championnat', 25),
    ('2025-06-12', 11, '21:15', 'championnat', 26),
    ('2025-06-23', 17, '20:30', 'amical', null),
    ('2025-09-03', 11, '21:00', 'amical', null),
    ('2025-09-15', 17, '20:30', 'amical', null),
    ('2025-10-01', 11, '21:00', 'amical', null),
    ('2025-10-07', 1, '20:30', 'amical', null),
    ('2025-10-16', 7, '20:00', 'championnat', 1),
    ('2025-10-20', 21, '20:45', 'amical', null),
    ('2025-11-03', 21, '20:45', 'championnat', 2),
    ('2025-11-12', 11, '21:00', 'championnat', 3),
    ('2025-11-17', 21, '20:45', 'championnat', 4),
    ('2025-11-27', 1, '20:30', 'championnat', 5),
    ('2025-12-01', 21, '20:45', 'championnat', 6),
    ('2025-12-08', 21, '20:45', 'championnat', 7),
    ('2025-12-15', 9, '20:30', 'championnat', 8),
    ('2026-01-07', 11, '21:00', 'amical', null),
    ('2026-01-12', 21, '20:45', 'championnat', 9),
    ('2026-01-20', 1, '20:30', 'championnat', 10),
    ('2026-02-02', 21, '20:45', 'championnat', 12),
    ('2026-02-09', 21, '20:45', 'championnat', 13),
    ('2026-02-16', 21, '20:45', 'championnat', 14),
    ('2026-03-03', 1, '20:30', 'amical', null),
    ('2026-03-16', 21, '20:45', 'championnat', 16),
    ('2026-03-26', 1, '20:30', 'championnat', 17),
    ('2026-04-01', 11, '20:30', 'amical', null),
    ('2026-04-13', 9, '20:30', 'championnat', 20),
    ('2026-04-23', 5, '20:30', 'amical', null),
    ('2026-04-27', 17, '20:30', 'amical', null),
    ('2026-05-12', 1, '20:30', 'championnat', 22),
    ('2026-05-21', 5, '20:30', 'championnat', 23),
    ('2026-06-15', 21, '20:15', 'championnat', 26)
)
update public.historical_match_scores h
set match_time = source.match_time::time,
    address = lieu.adresse,
    match_type = source.match_type,
    championship_round = source.championship_round
from source
left join lieu on lieu.code = source.lieu_code
where h.match_date = source.match_date::date;

-- Controle strict : les comptes doivent tomber juste, sinon la migration
-- echoue et rien n'est conserve.
do $controle$
declare
  v_type integer; v_heure integer; v_adresse integer; v_journee integer;
  v_champ integer; v_amical integer; v_somme_j bigint;
  v_adr_dist integer; v_minutes bigint;
begin
  select count(*) filter (where match_type is not null),
         count(*) filter (where match_time is not null),
         count(*) filter (where address is not null),
         count(*) filter (where championship_round is not null),
         count(*) filter (where match_type = 'championnat'),
         count(*) filter (where match_type = 'amical'),
         coalesce(sum(championship_round), 0),
         count(distinct address),
         coalesce(sum(extract(hour from match_time) * 60
                    + extract(minute from match_time)), 0)
  into v_type, v_heure, v_adresse, v_journee,
       v_champ, v_amical, v_somme_j, v_adr_dist, v_minutes
  from public.historical_match_scores;

  if v_type <> 313 then
    raise exception 'Lot 1 : % rencontres typées au lieu de 313', v_type;
  end if;
  if v_heure <> 313 then
    raise exception 'Lot 1 : % heures au lieu de 313', v_heure;
  end if;
  if v_adresse <> 313 then
    raise exception 'Lot 1 : % adresses au lieu de 313', v_adresse;
  end if;
  if v_journee <> 157 then
    raise exception 'Lot 1 : % journées au lieu de 157', v_journee;
  end if;

  -- Sommes de controle : une valeur mal reportee ferait echouer la migration
  -- meme si les comptes tombaient juste.
  if v_champ <> 157 or v_amical <> 156 then
    raise exception 'Lot 1 : % championnats et % amicaux au lieu de 157 et 156', v_champ, v_amical;
  end if;
  if v_somme_j <> 1337 then
    raise exception 'Lot 1 : somme des journées = % au lieu de 1337', v_somme_j;
  end if;
  if v_adr_dist <> 22 then
    raise exception 'Lot 1 : % adresses distinctes au lieu de 22', v_adr_dist;
  end if;
  if v_minutes <> 383600 then
    raise exception 'Lot 1 : somme des heures = % minutes au lieu de 383600', v_minutes;
  end if;
end;
$controle$;
