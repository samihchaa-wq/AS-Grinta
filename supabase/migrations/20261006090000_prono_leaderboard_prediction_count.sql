begin;

-- Statistiques → Prono : nombre de pronostics réalisés.
--
-- Le classement gagne une colonne « Prono » placée avant « Bons ». Elle compte
-- les pronostics remplis sur les matchs terminés, c'est-à-dire exactement ceux
-- que « Bons », « Exacts » et « Points » évaluent : « Bons » ne peut jamais
-- dépasser « Prono ». Un pronostic sur un match à venir compte dès que le
-- match est terminé ; avant, il reste privé, comme ses valeurs.
--
-- La vue reste security_invoker : la politique RLS de match_predictions ne
-- montre les pronostics des autres qu'une fois le match terminé, ce qui est
-- précisément le périmètre compté ici. La nouvelle colonne est ajoutée en fin
-- de vue, sans toucher aux colonnes existantes.

create or replace view public.v_classement_general
with (security_invoker = true)
as
with match_totals as (
  select points.profile_id,
         coalesce(sum(points.points), 0::numeric) as match_points
  from public.v_match_prediction_points points
  group by points.profile_id
), match_flags as (
  select flags.profile_id,
         coalesce(sum(flags.bon_pari), 0::bigint) as match_bons,
         coalesce(sum(flags.exact), 0::bigint) as match_exacts
  from public.v_match_prediction_flags flags
  group by flags.profile_id
), match_counts as (
  select prediction.profile_id,
         count(*) as match_pronos
  from public.match_predictions prediction
  join public.matches match
    on match.id = prediction.match_id
   and match.status in ('termine', 'archive')
  where prediction.is_filled
  group by prediction.profile_id
), eligible_profiles as (
  select profile.id, profile.first_name, profile.surnom
  from public.profiles profile
  where not profile.is_test_account
    and profile.status in ('active', 'archived')
    and private.has_filled_match_prediction(profile.id)
)
select profile.id as profile_id,
       profile.first_name,
       profile.surnom,
       coalesce(match_total.match_points, 0::numeric) as match_points,
       coalesce(match_stat.match_bons, 0::bigint) as match_bons,
       coalesce(match_stat.match_exacts, 0::bigint) as match_exacts,
       coalesce(match_count.match_pronos, 0::bigint) as match_pronos
from eligible_profiles profile
left join match_totals match_total on match_total.profile_id = profile.id
left join match_flags match_stat on match_stat.profile_id = profile.id
left join match_counts match_count on match_count.profile_id = profile.id;

revoke all on public.v_classement_general from public, anon, authenticated;
grant select on public.v_classement_general to authenticated;

comment on column public.v_classement_general.match_pronos is
  'Pronostics remplis sur des matchs terminés : la base sur laquelle Bons, Exacts et Points sont comptés.';

commit;
