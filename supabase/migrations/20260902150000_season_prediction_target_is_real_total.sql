-- Une transition de statut ne doit jamais modifier le classement du pari
-- saison.
--
-- v_season_prediction_points comparait le pronostic à une projection sur 30
-- matchs tant que la saison n'était pas archivée, puis au total réel une fois
-- archivée. Une saison qui ne se termine pas exactement à 30 matchs voyait donc
-- ses points, ses ex aequo et son bonus « nombre exact » (x2) changer au moment
-- précis de l'archivage, sans qu'aucun match ait été joué entre-temps.
--
-- La règle retenue est le total réel, partout :
--   * c'est la règle annoncée aux joueurs dans l'app (« devine son total de
--     buts sur la saison », « plus ton prono est proche du total réel ») ;
--   * c'est déjà ce qu'affiche la jauge de progression de chaque joueur ;
--   * c'est déjà la cible utilisée par v_season_prediction_bonus pour le bonus
--     d'ordre des buteurs.
--
-- Le classement devient donc cohérent avec ce que voient les joueurs pendant
-- toute la saison, et l'archivage n'y change plus rien. La jointure sur
-- v_season_match_count et la colonne de statut ne servaient qu'à la projection
-- et disparaissent.
--
-- Aucun classement passé n'est réécrit : aucune saison de la base ne produit
-- aujourd'hui de ligne dans cette vue.

create or replace view public.v_season_prediction_points
with (security_invoker = true)
as
with eligible_seasons as (
  select
    season.id,
    season.status,
    exists (
      select 1
      from public.season_prediction_roster_captures capture
      where capture.season_id = season.id
    ) as has_roster_snapshot
  from public.seasons season
  where season.season_predictions_locked_at is not null
     or season.status = 'archived'
),
prediction_roster as (
  select
    member.season_id,
    member.season_player_id,
    member.category
  from public.season_prediction_roster_members member
  join eligible_seasons season
    on season.id = member.season_id
   and season.has_roster_snapshot

  union all

  -- Repli hérité, pour une saison éligible antérieure à la capture d'effectif.
  -- Tout verrou ou archivage crée désormais une capture, y compris vide.
  select
    player.season_id,
    player.id as season_player_id,
    case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
  from public.season_players player
  join eligible_seasons season
    on season.id = player.season_id
   and not season.has_roster_snapshot
),
expected_predictions as (
  select roster.season_id, count(*) as expected_count
  from prediction_roster roster
  group by roster.season_id
),
predictor_completion as (
  select
    prediction.season_id,
    prediction.predictor_profile_id,
    count(*) filter (
      where prediction.is_filled
        and prediction.category = roster.category
    ) as filled_count
  from public.season_predictions prediction
  join prediction_roster roster
    on roster.season_id = prediction.season_id
   and roster.season_player_id = prediction.season_player_id
   and roster.category = prediction.category
  group by prediction.season_id, prediction.predictor_profile_id
),
eligible_predictors as (
  select completion.season_id, completion.predictor_profile_id
  from predictor_completion completion
  join expected_predictions expected
    on expected.season_id = completion.season_id
  where expected.expected_count > 0
    and completion.filled_count = expected.expected_count
),
targeted as (
  select
    prediction.id,
    prediction.season_id,
    prediction.predictor_profile_id,
    prediction.season_player_id,
    prediction.category,
    prediction.predicted_value_30,
    (
      case prediction.category
        when 'buts' then stats.goals
        when 'clean_sheets' then stats.clean_sheets
        else 0
      end
    )::numeric as target
  from public.season_predictions prediction
  join eligible_predictors eligible
    on eligible.season_id = prediction.season_id
   and eligible.predictor_profile_id = prediction.predictor_profile_id
  join prediction_roster roster
    on roster.season_id = prediction.season_id
   and roster.season_player_id = prediction.season_player_id
   and roster.category = prediction.category
  join public.v_player_season_stats stats
    on stats.season_player_id = prediction.season_player_id
  where prediction.is_filled
),
ranked as (
  select
    targeted.id,
    targeted.season_id,
    targeted.predictor_profile_id,
    targeted.season_player_id,
    targeted.category,
    targeted.predicted_value_30,
    targeted.target,
    count(*) over (
      partition by targeted.season_id,
                   targeted.season_player_id,
                   targeted.category
    ) as participant_count,
    rank() over (
      partition by targeted.season_id,
                   targeted.season_player_id,
                   targeted.category
      order by abs(targeted.predicted_value_30::numeric - targeted.target)
    ) as proximity_rank
  from targeted
  where targeted.target is not null
)
select
  id,
  season_id,
  predictor_profile_id,
  season_player_id,
  category,
  (
    (participant_count - proximity_rank + 1)
    * 3
    * case when predicted_value_30::numeric = target then 2 else 1 end
  )::integer as points
from ranked;

grant select on public.v_season_prediction_points to authenticated;
