-- « J'vous avais dis quoi ? » devient un badge secret (masqué « ??? » dans
-- « À débloquer » tant qu'il n'est pas gagné).
update public.badges
set secret = true
where code = 'perfect_own_goals_prediction__1';
