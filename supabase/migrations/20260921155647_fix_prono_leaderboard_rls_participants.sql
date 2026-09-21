-- Let the leaderboard expose participation without exposing unrevealed scores.
--
-- match_predictions RLS intentionally hides another user's prediction until the
-- match is finished/archived. v_classement_general is security_invoker, so a
-- direct EXISTS on match_predictions only sees the caller's own current row.
--
-- This helper crosses RLS for one narrow boolean only: whether a profile has
-- ever submitted at least one filled match prediction. Prediction values stay
-- protected by the existing match_predictions RLS policy.

create or replace function private.has_filled_match_prediction(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    private.is_active_profile()
    and exists (
      select 1
      from public.match_predictions prediction
      where prediction.profile_id = p_profile_id
        and prediction.is_filled
    );
$function$;

revoke all on function private.has_filled_match_prediction(uuid)
  from public, anon, authenticated;
grant execute on function private.has_filled_match_prediction(uuid)
  to authenticated, service_role;

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
    and private.has_filled_match_prediction(profile.id)
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
