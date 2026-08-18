-- Keep production QA accounts usable without exposing them in player rankings.
-- The marker is explicit so leaderboard eligibility does not depend on current
-- roster membership: former players can remain legitimate pronostiqueurs.

alter table public.profiles
  add column if not exists is_test_account boolean not null default false;

comment on column public.profiles.is_test_account is
  'Internal QA/test account. Test accounts stay usable but are excluded from player leaderboards.';

-- Existing production QA account. Use its stable local test email rather than
-- a generated UUID so the migration remains replayable across environments.
update public.profiles
set is_test_account = true
where lower(email) = 'testt@pronos.as-grinta.local';

-- The profile update surface is intentionally column-scoped. Keep this
-- internal marker out of the client-writable set.
revoke update (is_test_account) on table public.profiles from authenticated;

create or replace view public.v_classement_general
with (security_invoker = true)
as
with match_totals as (
  select
    v_match_prediction_points.profile_id,
    coalesce(sum(v_match_prediction_points.points), 0::numeric) as match_points
  from public.v_match_prediction_points
  group by v_match_prediction_points.profile_id
),
match_flags as (
  select
    v_match_prediction_flags.profile_id,
    coalesce(sum(v_match_prediction_flags.bon_pari), 0::bigint) as match_bons,
    coalesce(sum(v_match_prediction_flags.exact), 0::bigint) as match_exacts
  from public.v_match_prediction_flags
  group by v_match_prediction_flags.profile_id
),
season_totals as (
  select
    v_season_prediction_points.predictor_profile_id as profile_id,
    coalesce(sum(v_season_prediction_points.points), 0::bigint)::numeric as season_points
  from public.v_season_prediction_points
  group by v_season_prediction_points.predictor_profile_id
),
season_bonus as (
  select
    v_season_prediction_bonus.predictor_profile_id as profile_id,
    coalesce(sum(v_season_prediction_bonus.bonus_points), 0::bigint)::numeric as bonus_points
  from public.v_season_prediction_bonus
  group by v_season_prediction_bonus.predictor_profile_id
),
season_flags as (
  select
    v_season_prediction_flags.predictor_profile_id as profile_id,
    coalesce(sum(v_season_prediction_flags.bon_pari), 0::bigint) as season_bons,
    coalesce(sum(v_season_prediction_flags.exact), 0::bigint) as season_exacts
  from public.v_season_prediction_flags
  group by v_season_prediction_flags.predictor_profile_id
),
totals as (
  select
    p.id as profile_id,
    p.first_name,
    p.surnom,
    coalesce(mt.match_points, 0::numeric) as match_points,
    coalesce(st.season_points, 0::numeric)
      + coalesce(sb.bonus_points, 0::numeric) as season_points,
    coalesce(mf.match_bons, 0::bigint) as match_bons,
    coalesce(mf.match_exacts, 0::bigint) as match_exacts,
    coalesce(sf.season_bons, 0::bigint) as season_bons,
    coalesce(sf.season_exacts, 0::bigint) as season_exacts
  from public.profiles p
  left join match_totals mt on mt.profile_id = p.id
  left join match_flags mf on mf.profile_id = p.id
  left join season_totals st on st.profile_id = p.id
  left join season_bonus sb on sb.profile_id = p.id
  left join season_flags sf on sf.profile_id = p.id
  where p.status = 'active'::text
    and not p.is_test_account
)
select
  profile_id,
  first_name,
  surnom,
  match_points,
  season_points,
  match_points * 100::numeric + season_points as total_points,
  match_bons,
  match_exacts,
  season_bons,
  season_exacts
from totals;
