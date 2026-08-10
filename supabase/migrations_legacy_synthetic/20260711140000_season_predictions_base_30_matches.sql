-- La saison compte 30 matchs : les pronostics de saison sont désormais des
-- valeurs attendues sur 30 matchs, proratisées au nombre de matchs réellement
-- joués par le joueur (au lieu de la base 20 d'origine). Le maximum reste
-- 20 points par pronostic.

alter table public.season_predictions
  rename column predicted_value_20 to predicted_value_30;

create or replace view public.v_season_prediction_points
with (security_invoker = true) as
select
  sp.id,
  sp.season_id,
  sp.predictor_profile_id,
  sp.player_profile_id,
  sp.category,
  round(
    greatest(
      0::numeric,
      1::numeric - abs(
        (case sp.category
          when 'buts' then stats.goals
          when 'passes' then stats.assists
          when 'hommes_du_match' then stats.motm
          when 'clean_sheets' then stats.clean_sheets
          when 'penalty_faults' then stats.penalty_faults
          else 0
        end)::numeric
        - (sp.predicted_value_30 * stats.matches_played)::numeric / 30.0
      ) / greatest((sp.predicted_value_30 * stats.matches_played)::numeric / 30.0, 1::numeric)
    ) * 20::numeric
  )::integer as points
from season_predictions sp
join public.v_player_season_stats stats
  on stats.season_id = sp.season_id
 and stats.profile_id = sp.player_profile_id
join seasons s on s.id = sp.season_id
where sp.is_filled
  and stats.matches_played > 0
  and not (s.status = 'archived'::text and stats.matches_played < 3);

create or replace function public.seed_predictions_for_active_profile()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.status <> 'active' then return new; end if;

  insert into public.match_predictions(
    match_id, profile_id, predicted_score_as_grinta, predicted_score_adverse, is_filled
  )
  select id, new.id, 0, 0, false
  from public.matches
  where status = 'a_venir'
  on conflict(match_id, profile_id) do nothing;

  insert into public.season_predictions(
    season_id, predictor_profile_id, player_profile_id, category, predicted_value_30, is_filled
  )
  select sp.season_id, new.id, sp.profile_id, c.category, 0, false
  from public.season_players sp
  join public.seasons s on s.id = sp.season_id and s.status = 'open'
  cross join lateral unnest(
    case when sp.is_goalkeeper_snapshot
      then array['clean_sheets','hommes_du_match','penalty_faults']::text[]
      else array['buts','passes','hommes_du_match','penalty_faults']::text[]
    end
  ) c(category)
  on conflict(season_id, predictor_profile_id, player_profile_id, category) do nothing;
  return new;
end;
$$;

create or replace function public.seed_season_predictions_for_player()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  insert into public.season_predictions(
    season_id, predictor_profile_id, player_profile_id, category, predicted_value_30, is_filled
  )
  select new.season_id, p.id, new.profile_id, c.category, 0, false
  from public.profiles p
  cross join lateral unnest(
    case when new.is_goalkeeper_snapshot
      then array['clean_sheets','hommes_du_match','penalty_faults']::text[]
      else array['buts','passes','hommes_du_match','penalty_faults']::text[]
    end
  ) c(category)
  where p.status = 'active'
  on conflict(season_id, predictor_profile_id, player_profile_id, category) do nothing;
  return new;
end;
$$;
