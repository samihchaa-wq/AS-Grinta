create policy "insert_own_profile"
on public.profiles for insert
to authenticated
with check (id = auth.uid() and role = 'pronostiqueur' and status = 'active');

create policy "update_own_profile"
on public.profiles for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy "update_own_match_prediction"
on public.match_predictions for update
to authenticated
using (profile_id = auth.uid())
with check (profile_id = auth.uid() and is_filled = true);

create policy "update_own_season_prediction"
on public.season_predictions for update
to authenticated
using (predictor_profile_id = auth.uid())
with check (predictor_profile_id = auth.uid() and is_filled = true);;
