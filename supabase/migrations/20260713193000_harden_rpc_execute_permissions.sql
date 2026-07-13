-- P0 security hardening: expose only the RPCs intentionally called by the app.
-- This migration does not change business logic or table data.

begin;

-- PostgreSQL grants EXECUTE to PUBLIC on new functions by default. Remove that
-- implicit access from every application function currently defined in public.
revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;
revoke execute on all functions in schema public from authenticated;

-- ---------------------------------------------------------------------------
-- Authenticated client API
-- ---------------------------------------------------------------------------

-- Authentication and personal settings.
grant execute on function public.complete_password_change() to authenticated;
grant execute on function public.update_my_app_preferences(boolean, boolean, boolean) to authenticated;
grant execute on function public.register_push_subscription(text, text, text, text) to authenticated;

-- Read helpers used by RLS policies and safe client-side reads.
grant execute on function public.current_profile_role() to authenticated;
grant execute on function public.is_active_profile() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_exact_moderator() to authenticated;
grant execute on function public.is_match_staff() to authenticated;
grant execute on function public.is_moderator() to authenticated;
grant execute on function public.match_prediction_participant_count(uuid) to authenticated;

-- Match administration. Each function also performs its own staff/admin check.
grant execute on function public.get_or_create_opponent(text) to authenticated;
grant execute on function public.create_match_with_odds(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric) to authenticated;
grant execute on function public.preview_match_odds(uuid, text) to authenticated;
grant execute on function public.set_match_odds(uuid, numeric, numeric, numeric) to authenticated;
grant execute on function public.delete_match(uuid) to authenticated;
grant execute on function public.archive_match(uuid) to authenticated;
grant execute on function public.close_match_predictions(uuid) to authenticated;

-- Only the current five-argument finalization contract remains client-callable.
-- The legacy four-argument overload is intentionally not granted.
grant execute on function public.finalize_match_postgame(uuid, integer, jsonb, uuid, integer) to authenticated;

-- Staff and season administration.
grant execute on function public.staff_list_profiles() to authenticated;
grant execute on function public.admin_require_password_change(uuid) to authenticated;
grant execute on function public.moderator_update_profile_admin_fields(uuid, text, text, boolean) to authenticated;
grant execute on function public.open_or_create_season(text) to authenticated;
grant execute on function public.set_season_status(uuid, text) to authenticated;
grant execute on function public.set_season_predictions_lock(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Server-only API
-- ---------------------------------------------------------------------------

-- Edge Functions use the service role for the push dispatch pipeline.
grant execute on function public.internal_push_config() to service_role;
grant execute on function public.internal_push_dispatch(text, uuid) to service_role;
grant execute on function public.internal_push_prune(text[]) to service_role;

-- Explicitly preserve service-role access to all application functions. This is
-- required for trusted server workflows and does not expose them to clients.
grant execute on all functions in schema public to service_role;

-- ---------------------------------------------------------------------------
-- Migration assertions
-- ---------------------------------------------------------------------------

do $$
begin
  if has_function_privilege(
    'anon',
    'public.finalize_match_postgame(uuid,integer,jsonb,uuid)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Security assertion failed: anon can execute legacy finalization';
  end if;

  if has_function_privilege(
    'anon',
    'public.finalize_match_postgame(uuid,integer,jsonb,uuid,integer)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Security assertion failed: anon can execute current finalization';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.finalize_match_postgame(uuid,integer,jsonb,uuid)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Security assertion failed: legacy finalization remains client-callable';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.finalize_match_postgame(uuid,integer,jsonb,uuid,integer)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Security assertion failed: current finalization is unavailable to authenticated users';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.internal_push_config()'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Security assertion failed: internal push configuration is client-callable';
  end if;
end;
$$;

commit;
