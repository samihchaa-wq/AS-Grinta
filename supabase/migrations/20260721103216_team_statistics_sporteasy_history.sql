-- Statistiques collectives enrichies d'après l'historique SportEasy.
--
-- Le total « Toutes saisons » est initialisé avec les chiffres arrêtés à la
-- saison 2025-2026, puis seuls les matchs des saisons suivantes s'y ajoutent.
-- Les périodes actuelle et précédente restent calculées automatiquement depuis
-- les matchs terminés ou archivés.
create table if not exists public.historical_team_statistics (
  scope text primary key check (scope = 'all_time'),
  through_season text not null,
  matches_played integer not null check (matches_played >= 0),
  wins integer not null check (wins >= 0),
  draws integer not null check (draws >= 0),
  losses integer not null check (losses >= 0),
  goals_for integer not null check (goals_for >= 0),
  goals_against integer not null check (goals_against >= 0),
  best_win_streak integer not null check (best_win_streak >= 0),
  best_win_start date,
  best_win_end date,
  best_unbeaten_streak integer not null check (best_unbeaten_streak >= 0),
  best_unbeaten_start date,
  best_unbeaten_end date,
  worst_loss_streak integer not null check (worst_loss_streak >= 0),
  worst_loss_start date,
  worst_loss_end date,
  worst_winless_streak integer not null check (worst_winless_streak >= 0),
  worst_winless_start date,
  worst_winless_end date,
  updated_at timestamptz not null default now()
);

alter table public.historical_team_statistics enable row level security;

drop policy if exists historical_team_statistics_authenticated_read
  on public.historical_team_statistics;

create policy historical_team_statistics_authenticated_read
  on public.historical_team_statistics
  for select
  to authenticated
  using (true);

revoke all on public.historical_team_statistics from public, anon, authenticated;
grant select on public.historical_team_statistics to authenticated;

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
  updated_at
)
values (
  'all_time',
  '2025-2026',
  313,
  211,
  46,
  56,
  1235,
  589,
  12,
  date '2019-11-07',
  date '2020-10-05',
  33,
  date '2024-03-14',
  date '2025-03-31',
  4,
  date '2014-04-24',
  date '2014-06-02',
  8,
  date '2018-03-15',
  date '2018-06-18',
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
  updated_at = now();

create or replace view public.v_statistics_team
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
  select s.id, s.name
  from public.seasons s
  cross join open_season current
  where s.name < current.name
  order by s.name desc
  limit 1
),
baseline as (
  select *
  from public.historical_team_statistics
  where scope = 'all_time'
),
scored_matches as (
  select
    m.id,
    m.season_id,
    s.name as season_name,
    m.match_date,
    m.score_as_grinta as goals_for,
    m.score_adverse as goals_against,
    m.score_as_grinta - m.score_adverse as margin,
    case
      when m.score_as_grinta > m.score_adverse then 'V'::text
      when m.score_as_grinta = m.score_adverse then 'N'::text
      else 'D'::text
    end as result
  from public.matches m
  join public.seasons s on s.id = m.season_id
  where m.status = any (array['termine'::text, 'archive'::text])
    and m.score_as_grinta is not null
    and m.score_adverse is not null
),
period_refs as (
  select
    'current'::text as period_key,
    current.id as season_id,
    current.name as period_label
  from open_season current

  union all

  select
    'previous'::text,
    previous.id,
    previous.name
  from previous_season previous
),
period_totals as (
  select
    refs.period_key,
    refs.period_label,
    count(matches.id)::int as matches_played,
    count(*) filter (where matches.result = 'V')::int as wins,
    count(*) filter (where matches.result = 'N')::int as draws,
    count(*) filter (where matches.result = 'D')::int as losses,
    coalesce(sum(matches.goals_for), 0)::int as goals_for,
    coalesce(sum(matches.goals_against), 0)::int as goals_against
  from period_refs refs
  left join scored_matches matches on matches.season_id = refs.season_id
  group by refs.period_key, refs.period_label
),
period_recent_ranked as (
  select
    refs.period_key,
    matches.result,
    matches.match_date,
    matches.id,
    row_number() over (
      partition by refs.period_key
      order by matches.match_date desc, matches.id desc
    ) as recent_rank
  from period_refs refs
  join scored_matches matches on matches.season_id = refs.season_id
),
period_recent as (
  select
    period_key,
    array_agg(result order by match_date, id) as recent_results
  from period_recent_ranked
  where recent_rank <= 6
  group by period_key
),
period_margin_counts as (
  select
    refs.period_key,
    matches.margin,
    count(*)::int as match_count
  from period_refs refs
  join scored_matches matches on matches.season_id = refs.season_id
  group by refs.period_key, matches.margin
),
period_margins as (
  select
    period_key,
    jsonb_object_agg(
      margin::text,
      match_count
      order by margin
    ) as distribution
  from period_margin_counts
  group by period_key
),
period_streak_expanded as (
  select
    refs.period_key,
    matches.id,
    matches.match_date,
    streak.kind,
    streak.qualifies,
    sum(case when streak.qualifies then 0 else 1 end) over (
      partition by refs.period_key, streak.kind
      order by matches.match_date, matches.id
    ) as streak_group
  from period_refs refs
  join scored_matches matches on matches.season_id = refs.season_id
  cross join lateral (
    values
      ('win'::text, matches.result = 'V'),
      ('unbeaten'::text, matches.result <> 'D'),
      ('loss'::text, matches.result = 'D'),
      ('winless'::text, matches.result <> 'V')
  ) streak(kind, qualifies)
),
period_streaks as (
  select
    period_key,
    kind,
    count(*)::int as streak_length,
    min(match_date) as start_date,
    max(match_date) as end_date
  from period_streak_expanded
  where qualifies
  group by period_key, kind, streak_group
),
period_streak_ranked as (
  select
    *,
    row_number() over (
      partition by period_key, kind
      order by streak_length desc, end_date desc
    ) as streak_rank
  from period_streaks
),
period_streak_summary as (
  select
    period_key,
    coalesce(max(streak_length) filter (
      where kind = 'win' and streak_rank = 1
    ), 0)::int as best_win_streak,
    max(start_date) filter (
      where kind = 'win' and streak_rank = 1
    ) as best_win_start,
    max(end_date) filter (
      where kind = 'win' and streak_rank = 1
    ) as best_win_end,
    coalesce(max(streak_length) filter (
      where kind = 'unbeaten' and streak_rank = 1
    ), 0)::int as best_unbeaten_streak,
    max(start_date) filter (
      where kind = 'unbeaten' and streak_rank = 1
    ) as best_unbeaten_start,
    max(end_date) filter (
      where kind = 'unbeaten' and streak_rank = 1
    ) as best_unbeaten_end,
    coalesce(max(streak_length) filter (
      where kind = 'loss' and streak_rank = 1
    ), 0)::int as worst_loss_streak,
    max(start_date) filter (
      where kind = 'loss' and streak_rank = 1
    ) as worst_loss_start,
    max(end_date) filter (
      where kind = 'loss' and streak_rank = 1
    ) as worst_loss_end,
    coalesce(max(streak_length) filter (
      where kind = 'winless' and streak_rank = 1
    ), 0)::int as worst_winless_streak,
    max(start_date) filter (
      where kind = 'winless' and streak_rank = 1
    ) as worst_winless_start,
    max(end_date) filter (
      where kind = 'winless' and streak_rank = 1
    ) as worst_winless_end
  from period_streak_ranked
  group by period_key
),
dynamic_periods as (
  select
    totals.period_key,
    totals.period_label,
    totals.matches_played,
    totals.wins,
    totals.draws,
    totals.losses,
    totals.goals_for,
    totals.goals_against,
    totals.goals_for - totals.goals_against as goal_difference,
    0::int as clean_sheets,
    coalesce(recent.recent_results, array[]::text[]) as recent_results,
    margins.distribution as score_margin_distribution,
    coalesce(streaks.best_win_streak, 0) as best_win_streak,
    streaks.best_win_start,
    streaks.best_win_end,
    coalesce(streaks.best_unbeaten_streak, 0) as best_unbeaten_streak,
    streaks.best_unbeaten_start,
    streaks.best_unbeaten_end,
    coalesce(streaks.worst_loss_streak, 0) as worst_loss_streak,
    streaks.worst_loss_start,
    streaks.worst_loss_end,
    coalesce(streaks.worst_winless_streak, 0) as worst_winless_streak,
    streaks.worst_winless_start,
    streaks.worst_winless_end
  from period_totals totals
  left join period_recent recent using (period_key)
  left join period_margins margins using (period_key)
  left join period_streak_summary streaks using (period_key)
),
post_baseline_matches as (
  select matches.*
  from scored_matches matches
  cross join baseline history
  where matches.season_name > history.through_season
),
all_time_sequence as (
  select matches.*
  from scored_matches matches
  cross join baseline history
  where matches.season_name >= history.through_season
),
all_time_totals as (
  select
    history.matches_played + count(matches.id)::int as matches_played,
    history.wins + count(*) filter (
      where matches.result = 'V'
    )::int as wins,
    history.draws + count(*) filter (
      where matches.result = 'N'
    )::int as draws,
    history.losses + count(*) filter (
      where matches.result = 'D'
    )::int as losses,
    history.goals_for + coalesce(sum(matches.goals_for), 0)::int as goals_for,
    history.goals_against
      + coalesce(sum(matches.goals_against), 0)::int as goals_against
  from baseline history
  left join post_baseline_matches matches on true
  group by
    history.matches_played,
    history.wins,
    history.draws,
    history.losses,
    history.goals_for,
    history.goals_against
),
all_time_recent_ranked as (
  select
    result,
    match_date,
    id,
    row_number() over (
      order by match_date desc, id desc
    ) as recent_rank
  from all_time_sequence
),
all_time_recent as (
  select array_agg(result order by match_date, id) as recent_results
  from all_time_recent_ranked
  where recent_rank <= 6
),
all_time_streak_expanded as (
  select
    matches.id,
    matches.match_date,
    streak.kind,
    streak.qualifies,
    sum(case when streak.qualifies then 0 else 1 end) over (
      partition by streak.kind
      order by matches.match_date, matches.id
    ) as streak_group
  from all_time_sequence matches
  cross join lateral (
    values
      ('win'::text, matches.result = 'V'),
      ('unbeaten'::text, matches.result <> 'D'),
      ('loss'::text, matches.result = 'D'),
      ('winless'::text, matches.result <> 'V')
  ) streak(kind, qualifies)
),
all_time_streaks as (
  select
    kind,
    count(*)::int as streak_length,
    min(match_date) as start_date,
    max(match_date) as end_date
  from all_time_streak_expanded
  where qualifies
  group by kind, streak_group
),
all_time_streak_ranked as (
  select
    *,
    row_number() over (
      partition by kind
      order by streak_length desc, end_date desc
    ) as streak_rank
  from all_time_streaks
),
all_time_dynamic_streaks as (
  select
    coalesce(max(streak_length) filter (
      where kind = 'win' and streak_rank = 1
    ), 0)::int as best_win_streak,
    max(start_date) filter (
      where kind = 'win' and streak_rank = 1
    ) as best_win_start,
    max(end_date) filter (
      where kind = 'win' and streak_rank = 1
    ) as best_win_end,
    coalesce(max(streak_length) filter (
      where kind = 'unbeaten' and streak_rank = 1
    ), 0)::int as best_unbeaten_streak,
    max(start_date) filter (
      where kind = 'unbeaten' and streak_rank = 1
    ) as best_unbeaten_start,
    max(end_date) filter (
      where kind = 'unbeaten' and streak_rank = 1
    ) as best_unbeaten_end,
    coalesce(max(streak_length) filter (
      where kind = 'loss' and streak_rank = 1
    ), 0)::int as worst_loss_streak,
    max(start_date) filter (
      where kind = 'loss' and streak_rank = 1
    ) as worst_loss_start,
    max(end_date) filter (
      where kind = 'loss' and streak_rank = 1
    ) as worst_loss_end,
    coalesce(max(streak_length) filter (
      where kind = 'winless' and streak_rank = 1
    ), 0)::int as worst_winless_streak,
    max(start_date) filter (
      where kind = 'winless' and streak_rank = 1
    ) as worst_winless_start,
    max(end_date) filter (
      where kind = 'winless' and streak_rank = 1
    ) as worst_winless_end
  from all_time_streak_ranked
),
all_time_period as (
  select
    'all_time'::text as period_key,
    'Toutes saisons'::text as period_label,
    totals.matches_played,
    totals.wins,
    totals.draws,
    totals.losses,
    totals.goals_for,
    totals.goals_against,
    totals.goals_for - totals.goals_against as goal_difference,
    0::int as clean_sheets,
    coalesce(recent.recent_results, array[]::text[]) as recent_results,
    null::jsonb as score_margin_distribution,
    case
      when dynamic.best_win_streak > history.best_win_streak
        then dynamic.best_win_streak
      else history.best_win_streak
    end as best_win_streak,
    case
      when dynamic.best_win_streak > history.best_win_streak
        then dynamic.best_win_start
      else history.best_win_start
    end as best_win_start,
    case
      when dynamic.best_win_streak > history.best_win_streak
        then dynamic.best_win_end
      else history.best_win_end
    end as best_win_end,
    case
      when dynamic.best_unbeaten_streak > history.best_unbeaten_streak
        then dynamic.best_unbeaten_streak
      else history.best_unbeaten_streak
    end as best_unbeaten_streak,
    case
      when dynamic.best_unbeaten_streak > history.best_unbeaten_streak
        then dynamic.best_unbeaten_start
      else history.best_unbeaten_start
    end as best_unbeaten_start,
    case
      when dynamic.best_unbeaten_streak > history.best_unbeaten_streak
        then dynamic.best_unbeaten_end
      else history.best_unbeaten_end
    end as best_unbeaten_end,
    case
      when dynamic.worst_loss_streak > history.worst_loss_streak
        then dynamic.worst_loss_streak
      else history.worst_loss_streak
    end as worst_loss_streak,
    case
      when dynamic.worst_loss_streak > history.worst_loss_streak
        then dynamic.worst_loss_start
      else history.worst_loss_start
    end as worst_loss_start,
    case
      when dynamic.worst_loss_streak > history.worst_loss_streak
        then dynamic.worst_loss_end
      else history.worst_loss_end
    end as worst_loss_end,
    case
      when dynamic.worst_winless_streak > history.worst_winless_streak
        then dynamic.worst_winless_streak
      else history.worst_winless_streak
    end as worst_winless_streak,
    case
      when dynamic.worst_winless_streak > history.worst_winless_streak
        then dynamic.worst_winless_start
      else history.worst_winless_start
    end as worst_winless_start,
    case
      when dynamic.worst_winless_streak > history.worst_winless_streak
        then dynamic.worst_winless_end
      else history.worst_winless_end
    end as worst_winless_end
  from all_time_totals totals
  cross join baseline history
  cross join all_time_recent recent
  cross join all_time_dynamic_streaks dynamic
)
select * from dynamic_periods
union all
select * from all_time_period;

revoke all on public.v_statistics_team from public, anon, authenticated;
grant select on public.v_statistics_team to authenticated;
