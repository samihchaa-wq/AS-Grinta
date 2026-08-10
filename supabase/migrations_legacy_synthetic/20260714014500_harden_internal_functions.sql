-- P0: harden remaining internal SECURITY DEFINER functions.
-- All referenced relations/functions are schema-qualified, so an empty
-- search_path is safe and prevents object-shadowing attacks.

alter function public.calculate_match_odds_v3(uuid, text) set search_path = '';
alter function public.calculate_match_odds_v4(uuid, text) set search_path = '';
alter function public.recalculate_upcoming_match_odds_v3() set search_path = '';
alter function public.recalculate_upcoming_match_odds_v4() set search_path = '';
alter function public.trigger_match_odds_v4() set search_path = '';
alter function public.trigger_recalculate_upcoming_odds_v3() set search_path = '';
alter function public.upsert_match_odds_v4(uuid) set search_path = '';
alter function public.seed_match_predictions() set search_path = '';
alter function public.seed_predictions_for_active_profile() set search_path = '';
alter function public.seed_season_predictions_for_player() set search_path = '';
alter function public.enforce_match_prediction_x2() set search_path = '';
alter function public.guard_match_prediction_window() set search_path = '';
alter function public.current_profile_role() set search_path = '';
alter function public.is_exact_moderator() set search_path = '';

-- Never trust raw_user_meta_data for authorization. A user created directly
-- through Supabase Auth starts pending. Administrative flows may pre-create a
-- profile; ON CONFLICT deliberately preserves its existing role/status.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(
    id,
    email,
    first_name,
    last_name,
    role,
    is_goalkeeper,
    status
  )
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    'pronostiqueur',
    false,
    'pending'
  )
  on conflict (id) do update
  set email = excluded.email,
      first_name = case
        when public.profiles.first_name = '' then excluded.first_name
        else public.profiles.first_name
      end,
      last_name = case
        when public.profiles.last_name = '' then excluded.last_name
        else public.profiles.last_name
      end,
      updated_at = now();

  return new;
end;
$$;

-- Internal functions must not be directly exposed through PostgREST.
revoke execute on function public.calculate_match_odds_v3(uuid, text) from public, anon, authenticated;
revoke execute on function public.calculate_match_odds_v4(uuid, text) from public, anon, authenticated;
revoke execute on function public.recalculate_upcoming_match_odds_v3() from public, anon, authenticated;
revoke execute on function public.recalculate_upcoming_match_odds_v4() from public, anon, authenticated;
revoke execute on function public.trigger_match_odds_v4() from public, anon, authenticated;
revoke execute on function public.trigger_recalculate_upcoming_odds_v3() from public, anon, authenticated;
revoke execute on function public.upsert_match_odds_v4(uuid) from public, anon, authenticated;
revoke execute on function public.seed_match_predictions() from public, anon, authenticated;
revoke execute on function public.seed_predictions_for_active_profile() from public, anon, authenticated;
revoke execute on function public.seed_season_predictions_for_player() from public, anon, authenticated;
revoke execute on function public.enforce_match_prediction_x2() from public, anon, authenticated;
revoke execute on function public.guard_match_prediction_window() from public, anon, authenticated;
revoke execute on function public.handle_new_auth_user() from public, anon, authenticated;
revoke execute on function public.current_profile_role() from public, anon, authenticated;
revoke execute on function public.is_exact_moderator() from public, anon, authenticated;

-- Keep service-role access only for internal calculations that may be invoked by
-- trusted server-side jobs. Trigger functions execute via their trigger binding.
grant execute on function public.calculate_match_odds_v3(uuid, text) to service_role;
grant execute on function public.calculate_match_odds_v4(uuid, text) to service_role;
grant execute on function public.recalculate_upcoming_match_odds_v3() to service_role;
grant execute on function public.recalculate_upcoming_match_odds_v4() to service_role;
grant execute on function public.upsert_match_odds_v4(uuid) to service_role;
