-- Renommage du badge « Prophète » → « J'vous avais dis quoi ? » et changement
-- d'emoji (🔮 → 🥸).
update public.badges
set name = 'J’vous avais dis quoi ?',
    emoji = '🥸'
where code = 'perfect_own_goals_prediction__1';
