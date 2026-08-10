create policy "authenticated_read_profiles"
on public.profiles for select
to authenticated
using (true);

create policy "authenticated_read_seasons"
on public.seasons for select
to authenticated
using (true);

create policy "authenticated_read_season_players"
on public.season_players for select
to authenticated
using (true);

create policy "authenticated_read_opponents"
on public.opponents for select
to authenticated
using (true);

create policy "authenticated_read_matches"
on public.matches for select
to authenticated
using (true);

create policy "authenticated_read_match_participants"
on public.match_participants for select
to authenticated
using (true);

create policy "authenticated_read_live_sessions"
on public.live_sessions for select
to authenticated
using (true);

create policy "authenticated_read_live_positions"
on public.live_positions for select
to authenticated
using (true);

create policy "authenticated_read_goals"
on public.goals for select
to authenticated
using (true);

create policy "authenticated_read_substitutions"
on public.substitutions for select
to authenticated
using (true);

create policy "authenticated_read_match_motm"
on public.match_motm for select
to authenticated
using (true);

create policy "authenticated_read_match_odds"
on public.match_odds for select
to authenticated
using (true);

create policy "authenticated_read_season_predictions"
on public.season_predictions for select
to authenticated
using (true);

create policy "authenticated_read_formations"
on public.formations for select
to authenticated
using (true);

create policy "read_own_or_revealed_match_predictions"
on public.match_predictions for select
to authenticated
using (
  profile_id = (select auth.uid())
  or exists (
    select 1
    from public.matches m
    where m.id = match_predictions.match_id
      and m.status in ('termine', 'archive')
  )
);;
