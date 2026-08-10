-- Corrige le total historique de buts de Samih Châa.
-- L'audit de l'archive 2013-2026 confirme 1 but en carrière
-- (07/11/2022, 4-4 contre l'Amicale Olympique Cornebarireu).

update public.historical_player_statistics
set goals = 1,
    updated_at = now()
where scope = 'all_time'
  and player_name = 'Samih Châa'
  and goals = 0;
