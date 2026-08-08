-- Corrige l'historique SportEasy : 317 matchs ont bien été joués,
-- dont 4 sans score renseigné. Ces 4 rencontres doivent compter dans J,
-- les buteurs/HDM connus doivent rester comptés, mais elles ne doivent pas
-- entrer dans V/N/P ni dans les buts pour/contre de l'équipe.

do $$
begin
  if exists (
    select 1
    from public.historical_team_statistics
    where scope = 'all_time'
      and matches_played = 313
  ) then
    update public.historical_player_statistics h
    set matches_played = h.matches_played + d.matches_delta,
        goals = h.goals + d.goals_delta,
        hdm = h.hdm + d.hdm_delta,
        updated_at = now()
    from (values
      ('all_time','Flo Arnauduc',4,0,0),
      ('all_time','Alyoun Cherfi',1,0,0),
      ('all_time','Milan Couzin',2,1,1),
      ('all_time','Samuel Granier',3,0,1),
      ('all_time','Olivier Millet',2,0,0),
      ('all_time','Stéphane Fernandez',4,0,0),
      ('all_time','Anis Messaoudi',1,0,0),
      ('all_time','Aki Salabee',1,0,0),
      ('all_time','Julien Cesar',1,0,0),
      ('all_time','Alban Ricard',1,0,0),
      ('all_time','Romain Spigolon',3,0,1),
      ('all_time','Samih Châa',2,0,1),
      ('all_time','Arnold Hajdini',1,0,0),
      ('all_time','Luka Brunel',1,0,0),
      ('all_time','Thomas Blanchard',1,0,0),
      ('all_time','Hakim Cherfi',1,0,0),
      ('all_time','Julio Vignard',2,0,0),
      ('all_time','Yoann Canal',1,2,1),
      ('all_time','Kevin Jagot',1,0,0),
      ('all_time','François De La Bourdonnaye',1,0,0),
      ('all_time','Stéphane Manenti',1,0,0),
      ('all_time','Mathieu Bergon',1,0,0),
      ('all_time','Sebastien Seillier',1,0,0),
      ('all_time','Momo Zz''Ou',1,0,0),
      ('all_time','Mounir Ben Hfaiedh~',1,0,0),
      ('all_time','Guillaume Puy',1,0,0),
      ('all_time','Guilhem Arlat',1,0,0),
      ('all_time','Ricardo Laurelut',1,0,0),
      ('previous','Flo Arnauduc',1,0,0),
      ('previous','Alyoun Cherfi',1,0,0),
      ('previous','Milan Couzin',1,0,1),
      ('previous','Samuel Granier',1,0,1),
      ('previous','Olivier Millet',1,0,0),
      ('previous','Stéphane Fernandez',1,0,0),
      ('previous','Anis Messaoudi',1,0,0),
      ('previous','Aki Salabee',1,0,0),
      ('previous','Julien Cesar',1,0,0),
      ('previous','Alban Ricard',1,0,0),
      ('previous','Romain Spigolon',1,0,0),
      ('previous','Samih Châa',1,0,1)
    ) as d(scope, player_name, matches_delta, goals_delta, hdm_delta)
    where h.scope = d.scope
      and h.player_name = d.player_name;

    update public.historical_team_statistics
    set matches_played = 317,
        recent_results = array['N','V','D','D','V','D']::text[],
        updated_at = now()
    where scope = 'all_time';

    update public.historical_team_statistics
    set matches_played = 30,
        recent_results = array['N','V','D','D','V','D']::text[],
        updated_at = now()
    where scope = 'previous';
  end if;
end
$$;

-- Toutes saisons doit fusionner l'historique importé avec les matchs
-- terminés depuis la fin de l'archive, pour les derniers résultats et la
-- distribution des écarts de score.
create or replace view public.v_statistics_team
with (security_invoker = true)
as
with baseline as (
  select through_season,
         recent_results,
         score_margin_distribution
  from public.historical_team_statistics
  where scope = 'all_time'
),
post_baseline as (
  select m.id,
         m.match_date,
         case
           when m.score_as_grinta > m.score_adverse then 'V'
           when m.score_as_grinta = m.score_adverse then 'N'
           else 'D'
         end as result,
         (m.score_as_grinta - m.score_adverse)::int as margin
  from public.matches m
  join public.seasons s on s.id = m.season_id
  cross join baseline b
  where m.status in ('termine','archive')
    and m.score_as_grinta is not null
    and m.score_adverse is not null
    and s.name > b.through_season
),
post_ranked as (
  select *,
         row_number() over (order by match_date desc, id desc) as rn
  from post_baseline
),
post_recent as (
  select coalesce(
           array_agg(result order by match_date, id) filter (where rn <= 6),
           array[]::text[]
         ) as results,
         count(*)::int as total_count
  from post_ranked
),
recent_all_time as (
  select case
    when p.total_count >= 6 then p.results
    else coalesce(
           b.recent_results[
             greatest(
               coalesce(array_length(b.recent_results, 1), 0)
               - (6 - p.total_count) + 1,
               1
             ):
             coalesce(array_length(b.recent_results, 1), 0)
           ],
           array[]::text[]
         ) || p.results
  end as results
  from baseline b
  cross join post_recent p
),
margin_parts as (
  select key::int as margin,
         value::int as cnt
  from baseline b,
       lateral jsonb_each_text(
         coalesce(b.score_margin_distribution, '{}'::jsonb)
       )

  union all

  select margin,
         count(*)::int
  from post_baseline
  group by margin
),
all_time_margins as (
  select coalesce(
           jsonb_object_agg(margin::text, cnt order by margin),
           '{}'::jsonb
         ) as distribution
  from (
    select margin,
           sum(cnt)::int as cnt
    from margin_parts
    group by margin
  ) merged
)
select source.period_key,
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
         when source.period_key = 'all_time'
           then (select results from recent_all_time)
         else source.recent_results
       end as recent_results,
       case
         when source.period_key = 'all_time'
           then (select distribution from all_time_margins)
         else source.score_margin_distribution
       end as score_margin_distribution,
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
