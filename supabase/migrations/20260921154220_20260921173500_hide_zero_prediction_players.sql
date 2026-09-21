-- Keep the match-prediction leaderboard limited to actual participants.
--
-- Active profiles are pre-seeded with unfilled match_prediction rows, so
-- checking for a row is not enough. A profile becomes visible only after at
-- least one prediction has really been submitted (is_filled = true).
--
-- Historical archived predictors remain visible, test accounts remain hidden.

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
), eligible_profiles as (
  select profile.id, profile.first_name, profile.surnom
  from public.profiles profile
  where not profile.is_test_account
    and profile.status in ('active', 'archived')
    and exists (
      select 1
      from public.match_predictions prediction
      where prediction.profile_id = profile.id
        and prediction.is_filled
    )
)
select profile.id as profile_id,
       profile.first_name,
       profile.surnom,
       coalesce(match_total.match_points, 0::numeric) as match_points,
       coalesce(match_stat.match_bons, 0::bigint) as match_bons,
       coalesce(match_stat.match_exacts, 0::bigint) as match_exacts
from eligible_profiles profile
left join match_totals match_total on match_total.profile_id = profile.id
left join match_flags match_stat on match_stat.profile_id = profile.id;

revoke all on public.v_classement_general from public, anon, authenticated;
grant select on public.v_classement_general to authenticated;
