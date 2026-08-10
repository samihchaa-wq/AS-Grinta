begin;

-- Les statistiques équipe importées suivent le même principe que les joueurs :
-- l'import 2025-2026 sert de repli, puis l'ancienne saison actuelle devient
-- automatiquement la saison précédente dès qu'une nouvelle saison est ouverte.
alter table public.historical_team_statistics
  add column if not exists recent_results text[] not null default '{}',
  add column if not exists score_margin_distribution jsonb;

alter table public.historical_team_statistics
  drop constraint if exists historical_team_statistics_scope_check;
alter table public.historical_team_statistics
  add constraint historical_team_statistics_scope_check
  check (scope in ('all_time', 'previous'));

insert into public.historical_team_statistics (
  scope,
  through_season,
  matches_played,
  wins,
  draws,
  losses,
  goals_for,
  goals_against,
  best_win_streak,
  best_win_start,
  best_win_end,
  best_unbeaten_streak,
  best_unbeaten_start,
  best_unbeaten_end,
  worst_loss_streak,
  worst_loss_start,
  worst_loss_end,
  worst_winless_streak,
  worst_winless_start,
  worst_winless_end,
  recent_results,
  score_margin_distribution,
  updated_at
)
values (
  'previous',
  '2025-2026',
  29,
  20,
  2,
  7,
  139,
  51,
  9,
  date '2025-11-17',
  date '2026-02-02',
  9,
  date '2025-11-17',
  date '2026-02-02',
  2,
  date '2026-04-27',
  date '2026-05-12',
  2,
  date '2026-04-27',
  date '2026-05-12',
  array['N', 'V', 'D', 'D', 'V', 'D']::text[],
  '{"-2":1,"-1":6,"0":2,"1":1,"2":4,"3":1,"4":6,"5":0,"6":3,"7":2,"8":0,"9":2,"10":1}'::jsonb,
  now()
)
on conflict (scope) do update set
  through_season = excluded.through_season,
  matches_played = excluded.matches_played,
  wins = excluded.wins,
  draws = excluded.draws,
  losses = excluded.losses,
  goals_for = excluded.goals_for,
  goals_against = excluded.goals_against,
  best_win_streak = excluded.best_win_streak,
  best_win_start = excluded.best_win_start,
  best_win_end = excluded.best_win_end,
  best_unbeaten_streak = excluded.best_unbeaten_streak,
  best_unbeaten_start = excluded.best_unbeaten_start,
  best_unbeaten_end = excluded.best_unbeaten_end,
  worst_loss_streak = excluded.worst_loss_streak,
  worst_loss_start = excluded.worst_loss_start,
  worst_loss_end = excluded.worst_loss_end,
  worst_winless_streak = excluded.worst_winless_streak,
  worst_winless_start = excluded.worst_winless_start,
  worst_winless_end = excluded.worst_winless_end,
  recent_results = excluded.recent_results,
  score_margin_distribution = excluded.score_margin_distribution,
  updated_at = now();

-- Conserve le calcul dynamique existant dans une vue interne, puis choisit
-- entre ce calcul et l'import historique pour « Saison précédente ».
alter view public.v_statistics_team rename to v_statistics_team_dynamic_base;

create view public.v_statistics_team
with (security_invoker = true)
as
with open_season as (
  select id, name
  from public.seasons
  where status = 'open'
  order by created_at desc
  limit 1
),
previous_season as (
  select season.id, season.name
  from public.seasons season
  cross join open_season current
  where season.name < current.name
  order by season.name desc
  limit 1
),
previous_has_app_roster as (
  select exists (
    select 1
    from public.season_players player
    join previous_season previous on previous.id = player.season_id
  ) as has_app
),
imported_previous as (
  select
    'previous'::text as period_key,
    history.through_season as period_label,
    history.matches_played,
    history.wins,
    history.draws,
    history.losses,
    history.goals_for,
    history.goals_against,
    history.goals_for - history.goals_against as goal_difference,
    0::integer as clean_sheets,
    history.recent_results,
    history.score_margin_distribution,
    history.best_win_streak,
    history.best_win_start,
    history.best_win_end,
    history.best_unbeaten_streak,
    history.best_unbeaten_start,
    history.best_unbeaten_end,
    history.worst_loss_streak,
    history.worst_loss_start,
    history.worst_loss_end,
    history.worst_winless_streak,
    history.worst_winless_start,
    history.worst_winless_end
  from public.historical_team_statistics history
  cross join previous_has_app_roster app
  where history.scope = 'previous'
    and not app.has_app
)
select dynamic.*
from public.v_statistics_team_dynamic_base dynamic
where dynamic.period_key in ('current', 'all_time')

union all

select dynamic.*
from public.v_statistics_team_dynamic_base dynamic
cross join previous_has_app_roster app
where dynamic.period_key = 'previous'
  and app.has_app

union all

select imported.*
from imported_previous imported;

revoke all privileges on table public.v_statistics_team from anon;
grant select on table public.v_statistics_team to authenticated;
grant select on table public.v_statistics_team_dynamic_base to authenticated;

commit;