-- Échange uniquement les icônes des badges gardien demandés :
-- les paliers de clean sheet utilisent le mur, et l'exploit arrêt de penalty
-- utilise les gants. Le badge « Le Mur » devient « Goalkeeper ».

update public.badges
set emoji = '🧱'
where metric in ('clean_sheets_season', 'clean_sheets');

update public.badges
set
  emoji = '🧤',
  name = 'Goalkeeper'
where code = 'exploit_penalty_arrete';
