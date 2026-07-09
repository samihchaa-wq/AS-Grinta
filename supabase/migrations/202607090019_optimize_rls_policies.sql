drop policy if exists insert_own_profile on public.profiles;
create policy insert_own_profile
on public.profiles for insert to authenticated
with check(
  id=(select auth.uid())
  and role='pronostiqueur'
  and status='active'
);

drop policy if exists profiles_update_self on public.profiles;
drop policy if exists profiles_moderator_update on public.profiles;
create policy profiles_update_authorized
on public.profiles for update to authenticated
using(
  id=(select auth.uid()) or public.is_moderator()
)
with check(
  id=(select auth.uid()) or public.is_moderator()
);

drop policy if exists matches_admin_insert on public.matches;
create policy matches_admin_insert
on public.matches for insert to authenticated
with check(
  public.is_admin() and created_by=(select auth.uid())
);

drop policy if exists matches_admin_update on public.matches;
drop policy if exists matches_moderator_update on public.matches;
create policy matches_authorized_update
on public.matches for update to authenticated
using(
  public.is_moderator()
  or (public.is_admin() and status<>'archive')
)
with check(
  public.is_moderator() or public.is_admin()
);

drop policy if exists match_motm_admin_insert on public.match_motm;
create policy match_motm_admin_insert
on public.match_motm for insert to authenticated
with check(
  public.is_admin() and created_by=(select auth.uid())
);

drop policy if exists match_predictions_owner_insert
on public.match_predictions;
create policy match_predictions_owner_insert
on public.match_predictions for insert to authenticated
with check(profile_id=(select auth.uid()));

drop policy if exists season_predictions_owner_insert
on public.season_predictions;
create policy season_predictions_owner_insert
on public.season_predictions for insert to authenticated
with check(predictor_profile_id=(select auth.uid()));

drop policy if exists season_predictions_owner_update
on public.season_predictions;
create policy season_predictions_owner_update
on public.season_predictions for update to authenticated
using(predictor_profile_id=(select auth.uid()))
with check(predictor_profile_id=(select auth.uid()));

drop policy if exists live_sessions_controller_update
on public.live_sessions;
create policy live_sessions_controller_update
on public.live_sessions for update to authenticated
using(
  public.is_moderator()
  or (
    public.is_admin()
    and (
      controller_profile_id=(select auth.uid())
      or (
        controller_profile_id is null
        and controller_session_id is null
      )
    )
  )
)
with check(
  public.is_moderator()
  or (
    public.is_admin()
    and controller_profile_id=(select auth.uid())
  )
);
