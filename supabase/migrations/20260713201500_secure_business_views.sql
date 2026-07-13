-- P0 security hardening for exposed business views.
-- Enforce caller permissions/RLS and remove anonymous access.

alter view public.v_classement_general
  set (security_invoker = true);

alter view public.v_match_prediction_flags
  set (security_invoker = true);

alter view public.v_season_prediction_flags
  set (security_invoker = true);

alter view public.v_season_prediction_points
  set (security_invoker = true);

revoke all privileges on table public.v_classement_general from anon;
revoke all privileges on table public.v_match_prediction_flags from anon;
revoke all privileges on table public.v_season_prediction_flags from anon;
revoke all privileges on table public.v_season_prediction_points from anon;

revoke insert, update, delete, truncate, references, trigger
  on table public.v_classement_general
  from authenticated;

revoke insert, update, delete, truncate, references, trigger
  on table public.v_match_prediction_flags
  from authenticated;

revoke insert, update, delete, truncate, references, trigger
  on table public.v_season_prediction_flags
  from authenticated;

revoke insert, update, delete, truncate, references, trigger
  on table public.v_season_prediction_points
  from authenticated;

grant select on table public.v_classement_general to authenticated;
grant select on table public.v_match_prediction_flags to authenticated;
grant select on table public.v_season_prediction_flags to authenticated;
grant select on table public.v_season_prediction_points to authenticated;
