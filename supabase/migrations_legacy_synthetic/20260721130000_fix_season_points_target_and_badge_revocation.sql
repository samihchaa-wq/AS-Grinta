-- Corrections issues de l'audit « saison complète ».
--
-- 1) v_season_prediction_points : la cible de comparaison était le total BRUT
--    de la saison (ex. 12 matchs joués) alors que la prédiction `predicted_value_30`
--    est exprimée « sur 30 matchs ». La vue des DRAPEAUX (v_season_prediction_flags)
--    projette correctement le réel à 30 matchs tant que la saison n'est pas
--    archivée ; les POINTS, eux, restaient sur le total brut. Résultat : pendant
--    la saison (verrouillée mais pas archivée), le classement des pronos de saison
--    et le bonus ×2 « exact » étaient calculés sur une mauvaise cible. On aligne
--    la cible des points sur celle des drapeaux (projection à 30 hors archivage,
--    total réel une fois archivé).
--
-- 2) recalculate_profile_badges : n'attribuait les badges auto qu'en INSERT
--    (jamais de retrait). Un score corrigé à la baisse laissait des badges
--    « fantômes » au-dessus de leur palier réel. On rend l'attribution
--    symétrique : si la métrique repasse sous le seuil, l'attribution AUTOMATIQUE
--    est retirée. Les badges donnés à la main (source <> 'auto') restent acquis.

-- ---------------------------------------------------------------------------
-- 1) Points de pronostics de saison : cible projetée à 30 matchs
-- ---------------------------------------------------------------------------
create or replace view public.v_season_prediction_points as
with eligible_seasons as (
  select seasons.id, seasons.status
  from seasons
  where seasons.season_predictions_locked_at is not null or seasons.status = 'archived'
), expected_predictions as (
  select sp.season_id, count(*) as expected_count
  from season_players sp
  join eligible_seasons es on es.id = sp.season_id
  group by sp.season_id
), predictor_completion as (
  select sp.season_id, sp.predictor_profile_id,
         count(*) filter (where sp.is_filled and (sp.category = any (array['buts','clean_sheets']))) as filled_count
  from season_predictions sp
  join eligible_seasons es on es.id = sp.season_id
  group by sp.season_id, sp.predictor_profile_id
), eligible_predictors as (
  select pc.season_id, pc.predictor_profile_id
  from predictor_completion pc
  join expected_predictions ep on ep.season_id = pc.season_id
  where ep.expected_count > 0 and pc.filled_count = ep.expected_count
), base as (
  select sp.id, sp.season_id, sp.predictor_profile_id, sp.season_player_id,
         sp.category, sp.predicted_value_30,
         case sp.category
           when 'buts' then st.goals
           when 'clean_sheets' then st.clean_sheets
           else 0
         end as metric,
         es.status as season_status,
         mc.matches_played
  from season_predictions sp
  join eligible_predictors ep on ep.season_id = sp.season_id and ep.predictor_profile_id = sp.predictor_profile_id
  join eligible_seasons es on es.id = sp.season_id
  join v_player_season_stats st on st.season_player_id = sp.season_player_id
  left join v_season_match_count mc on mc.season_id = sp.season_id
  where sp.is_filled and (sp.category = any (array['buts','clean_sheets']))
), targeted as (
  select base.*,
         case
           when base.season_status = 'archived' then base.metric::numeric
           when coalesce(base.matches_played, 0) > 0
             then round(base.metric::numeric * 30.0 / base.matches_played::numeric)
           else null::numeric
         end as target
  from base
), ranked as (
  select targeted.id, targeted.season_id, targeted.predictor_profile_id,
         targeted.season_player_id, targeted.category, targeted.predicted_value_30,
         targeted.target,
         count(*) over (partition by targeted.season_id, targeted.season_player_id, targeted.category) as participant_count,
         rank() over (partition by targeted.season_id, targeted.season_player_id, targeted.category
                      order by (abs(targeted.predicted_value_30::numeric - targeted.target))) as proximity_rank
  from targeted
  where targeted.target is not null
)
select id, season_id, predictor_profile_id, season_player_id, category,
       ((participant_count - proximity_rank + 1) * 3 *
         case when predicted_value_30::numeric = target then 2 else 1 end)::integer as points
from ranked;

-- ---------------------------------------------------------------------------
-- 2) Attribution des badges auto rendue symétrique (retrait sous le seuil)
-- ---------------------------------------------------------------------------
create or replace function public.recalculate_profile_badges(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v jsonb;
  b record;
  val integer;
begin
  if p_profile_id is null then
    return;
  end if;
  select to_jsonb(t) into v from public.profile_badge_metrics(p_profile_id) t;
  if v is null then
    return;
  end if;
  for b in
    select id, metric, threshold from public.badges
    where auto and kind = 'tier' and metric is not null and threshold is not null
  loop
    val := coalesce((v ->> b.metric)::int, 0);
    if val >= b.threshold then
      insert into public.profile_badges(profile_id, badge_id, source)
      values (p_profile_id, b.id, 'auto')
      on conflict (profile_id, badge_id) do nothing;
    else
      -- Palier plus atteint : on retire UNIQUEMENT l'attribution automatique.
      -- Les badges décernés manuellement (source <> 'auto') restent acquis.
      delete from public.profile_badges
      where profile_id = p_profile_id and badge_id = b.id and source = 'auto';
    end if;
  end loop;
end;
$function$;
