begin;

-- La section « Derniers matchs » reste disponible pour la saison actuelle et
-- pour « Toutes saisons », mais elle ne doit pas apparaître dans les
-- statistiques de la saison précédente.
alter view public.v_statistics_team
  rename to v_statistics_team_with_recent_results;

create view public.v_statistics_team
with (security_invoker = true)
as
select
  source.period_key,
  source.period_label,
  source.matches_played,
  source.wins,
  source.draws,
  source.losses,
  source.goals_for,
  source.goals_against,
  source.goal_difference,
  source.clean_sheets,
  case
    when source.period_key = 'previous' then array[]::text[]
    else source.recent_results
  end as recent_results,
  source.score_margin_distribution,
  source.best_win_streak,
  source.best_win_start,
  source.best_win_end,
  source.best_unbeaten_streak,
  source.best_unbeaten_start,
  source.best_unbeaten_end,
  source.worst_loss_streak,
  source.worst_loss_start,
  source.worst_loss_end,
  source.worst_winless_streak,
  source.worst_winless_start,
  source.worst_winless_end
from public.v_statistics_team_with_recent_results source;

revoke all privileges on table public.v_statistics_team from anon;
grant select on table public.v_statistics_team to authenticated;

commit;
