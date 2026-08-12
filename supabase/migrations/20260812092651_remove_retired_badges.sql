set local lock_timeout = '5s';

delete from public.badges
where code in (
  'exploit_trois_postes',
  'exploit_sauvetage_ligne',
  'exploit_equipe_adverse',
  'perfect_own_goals_prediction__1'
);
