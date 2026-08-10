begin;

-- Authenticated read access to public application data.
drop policy if exists profiles_read_authenticated on public.profiles;
create policy profiles_read_authenticated on public.profiles
for select to authenticated using (true);

drop policy if exists seasons_read_authenticated on public.seasons;
create policy seasons_read_authenticated on public.seasons
for select to authenticated using (true);

drop policy if exists season_players_read_authenticated on public.season_players;
create policy season_players_read_authenticated on public.season_players
for select to authenticated using (true);

drop policy if exists opponents_read_authenticated on public.opponents;
create policy opponents_read_authenticated on public.opponents
for select to authenticated using (true);

drop policy if exists matches_read_authenticated on public.matches;
create policy matches_read_authenticated on public.matches
for select to authenticated using (true);

drop policy if exists match_participants_read_authenticated on public.match_participants;
create policy match_participants_read_authenticated on public.match_participants
for select to authenticated using (true);

drop policy if exists live_sessions_read_authenticated on public.live_sessions;
create policy live_sessions_read_authenticated on public.live_sessions
for select to authenticated using (true);

drop policy if exists live_positions_read_authenticated on public.live_positions;
create policy live_positions_read_authenticated on public.live_positions
for select to authenticated using (true);

drop policy if exists goals_read_authenticated on public.goals;
create policy goals_read_authenticated on public.goals
for select to authenticated using (true);

drop policy if exists substitutions_read_authenticated on public.substitutions;
create policy substitutions_read_authenticated on public.substitutions
for select to authenticated using (true);

drop policy if exists match_motm_read_authenticated on public.match_motm;
create policy match_motm_read_authenticated on public.match_motm
for select to authenticated using (true);

drop policy if exists match_odds_read_authenticated on public.match_odds;
create policy match_odds_read_authenticated on public.match_odds
for select to authenticated using (true);

drop policy if exists formations_read_authenticated on public.formations;
create policy formations_read_authenticated on public.formations
for select to authenticated using (true);

-- Profile writes.
drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
for insert to authenticated
with check (
  id = auth.uid()
  and role = 'pronostiqueur'
  and status = 'active'
);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists profiles_moderator_update on public.profiles;
create policy profiles_moderator_update on public.profiles
for update to authenticated
using (public.is_moderator())
with check (public.is_moderator());

revoke update on public.profiles from authenticated;
grant update (first_name, last_name, photo_url, updated_at) on public.profiles to authenticated;
grant update (role, status, is_goalkeeper, updated_at) on public.profiles to authenticated;

-- Season and squad administration belongs to the Moderator.
drop policy if exists seasons_moderator_insert on public.seasons;
create policy seasons_moderator_insert on public.seasons
for insert to authenticated
with check (public.is_moderator());

drop policy if exists seasons_moderator_update on public.seasons;
create policy seasons_moderator_update on public.seasons
for update to authenticated
using (public.is_moderator())
with check (public.is_moderator());

drop policy if exists seasons_moderator_delete on public.seasons;
create policy seasons_moderator_delete on public.seasons
for delete to authenticated
using (public.is_moderator());

drop policy if exists season_players_moderator_insert on public.season_players;
create policy season_players_moderator_insert on public.season_players
for insert to authenticated
with check (public.is_moderator());

drop policy if exists season_players_moderator_update on public.season_players;
create policy season_players_moderator_update on public.season_players
for update to authenticated
using (public.is_moderator())
with check (public.is_moderator());

drop policy if exists season_players_moderator_delete on public.season_players;
create policy season_players_moderator_delete on public.season_players
for delete to authenticated
using (public.is_moderator());

-- Opponents can be created by Admins, corrected by Moderator.
drop policy if exists opponents_admin_insert on public.opponents;
create policy opponents_admin_insert on public.opponents
for insert to authenticated
with check (public.is_admin() or public.is_moderator());

drop policy if exists opponents_moderator_update on public.opponents;
create policy opponents_moderator_update on public.opponents
for update to authenticated
using (public.is_moderator())
with check (public.is_moderator());

drop policy if exists opponents_moderator_delete on public.opponents;
create policy opponents_moderator_delete on public.opponents
for delete to authenticated
using (public.is_moderator());

-- Match lifecycle.
drop policy if exists matches_admin_insert on public.matches;
create policy matches_admin_insert on public.matches
for insert to authenticated
with check (public.is_admin() and created_by = auth.uid());

drop policy if exists matches_admin_update_non_archived on public.matches;
create policy matches_admin_update_non_archived on public.matches
for update to authenticated
using (public.is_admin() and status <> 'archive')
with check (public.is_admin());

drop policy if exists matches_moderator_update on public.matches;
create policy matches_moderator_update on public.matches
for update to authenticated
using (public.is_moderator())
with check (public.is_moderator());

drop policy if exists matches_moderator_delete on public.matches;
create policy matches_moderator_delete on public.matches
for delete to authenticated
using (public.is_moderator());

-- Match participant selection by Admin on non-archived matches.
drop policy if exists match_participants_admin_insert on public.match_participants;
create policy match_participants_admin_insert on public.match_participants
for insert to authenticated
with check (
  public.is_admin()
  and exists (
    select 1 from public.matches m
    where m.id = match_id and m.status <> 'archive'
  )
);

drop policy if exists match_participants_admin_delete on public.match_participants;
create policy match_participants_admin_delete on public.match_participants
for delete to authenticated
using (
  public.is_admin()
  and exists (
    select 1 from public.matches m
    where m.id = match_id and m.status <> 'archive'
  )
);

-- Live session creation by Admin. Mutations are restricted to the current controller.
drop policy if exists live_sessions_admin_insert on public.live_sessions;
create policy live_sessions_admin_insert on public.live_sessions
for insert to authenticated
with check (public.is_admin());

drop policy if exists live_sessions_controller_update on public.live_sessions;
create policy live_sessions_controller_update on public.live_sessions
for update to authenticated
using (
  (public.is_admin() and controller_profile_id = auth.uid())
  or public.is_moderator()
)
with check (
  (public.is_admin() and controller_profile_id = auth.uid())
  or public.is_moderator()
);

create or replace function public.is_current_live_controller(p_live_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.live_sessions ls
    where ls.id = p_live_session_id
      and ls.controller_profile_id = auth.uid()
      and public.is_admin()
      and ls.controller_session_id is not null
  );
$$;

create or replace function public.is_current_match_controller(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.live_sessions ls
    where ls.match_id = p_match_id
      and ls.controller_profile_id = auth.uid()
      and public.is_admin()
      and ls.controller_session_id is not null
  );
$$;

-- Live positions.
drop policy if exists live_positions_controller_insert on public.live_positions;
create policy live_positions_controller_insert on public.live_positions
for insert to authenticated
with check (public.is_current_live_controller(live_session_id));

drop policy if exists live_positions_controller_update on public.live_positions;
create policy live_positions_controller_update on public.live_positions
for update to authenticated
using (public.is_current_live_controller(live_session_id))
with check (public.is_current_live_controller(live_session_id));

drop policy if exists live_positions_controller_delete on public.live_positions;
create policy live_positions_controller_delete on public.live_positions
for delete to authenticated
using (public.is_current_live_controller(live_session_id));

-- Goals.
drop policy if exists goals_controller_insert on public.goals;
create policy goals_controller_insert on public.goals
for insert to authenticated
with check (public.is_current_match_controller(match_id));

drop policy if exists goals_controller_update on public.goals;
create policy goals_controller_update on public.goals
for update to authenticated
using (public.is_current_match_controller(match_id))
with check (public.is_current_match_controller(match_id));

drop policy if exists goals_controller_delete on public.goals;
create policy goals_controller_delete on public.goals
for delete to authenticated
using (public.is_current_match_controller(match_id));

-- Substitutions.
drop policy if exists substitutions_controller_insert on public.substitutions;
create policy substitutions_controller_insert on public.substitutions
for insert to authenticated
with check (public.is_current_live_controller(live_session_id));

drop policy if exists substitutions_controller_delete on public.substitutions;
create policy substitutions_controller_delete on public.substitutions
for delete to authenticated
using (public.is_current_live_controller(live_session_id));

-- Man of the match.
drop policy if exists match_motm_admin_insert on public.match_motm;
create policy match_motm_admin_insert on public.match_motm
for insert to authenticated
with check (public.is_admin() and created_by = auth.uid());

drop policy if exists match_motm_admin_delete on public.match_motm;
create policy match_motm_admin_delete on public.match_motm
for delete to authenticated
using (public.is_admin() or public.is_moderator());

-- Match predictions: private before completion, public afterward.
drop policy if exists match_predictions_select_visibility on public.match_predictions;
create policy match_predictions_select_visibility on public.match_predictions
for select to authenticated
using (
  profile_id = auth.uid()
  or exists (
    select 1 from public.matches m
    where m.id = match_id
      and m.status in ('termine','archive')
  )
);

drop policy if exists match_predictions_owner_insert on public.match_predictions;
create policy match_predictions_owner_insert on public.match_predictions
for insert to authenticated
with check (profile_id = auth.uid());

drop policy if exists match_predictions_owner_update_window on public.match_predictions;
create policy match_predictions_owner_update_window on public.match_predictions
for update to authenticated
using (profile_id = auth.uid())
with check (
  profile_id = auth.uid()
  and exists (
    select 1
    from public.matches m
    where m.id = match_id
      and m.status = 'a_venir'
      and now() >= (m.match_date + m.match_time) - interval '6 days'
      and now() < (m.match_date + m.match_time) - interval '12 hours'
  )
);

-- Season predictions are public and owner-writable.
drop policy if exists season_predictions_read_authenticated on public.season_predictions;
create policy season_predictions_read_authenticated on public.season_predictions
for select to authenticated using (true);

drop policy if exists season_predictions_owner_insert on public.season_predictions;
create policy season_predictions_owner_insert on public.season_predictions
for insert to authenticated
with check (predictor_profile_id = auth.uid());

drop policy if exists season_predictions_owner_update on public.season_predictions;
create policy season_predictions_owner_update on public.season_predictions
for update to authenticated
using (predictor_profile_id = auth.uid())
with check (predictor_profile_id = auth.uid());

-- Odds and formations are system-managed; authenticated users only read them.
revoke insert, update, delete on public.match_odds from authenticated;
revoke insert, update, delete on public.formations from authenticated;

commit;
