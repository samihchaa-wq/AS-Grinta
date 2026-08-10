-- Historical compatibility note:
-- production already contained parts of the later prediction schema when this
-- migration was first recorded. A clean replay does not. Keep the intended
-- profile protections on the columns that exist at this point, and only add
-- prediction policies when their tables are already present.

create policy "insert_own_profile"
on public.profiles for insert
to authenticated
with check (
  id = auth.uid()
  and role = 'pronostiqueur'
  and is_active = true
);

create policy "update_own_profile"
on public.profiles for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

do $do$
begin
  if to_regclass('public.match_predictions') is not null then
    execute $sql$
      create policy "update_own_match_prediction"
      on public.match_predictions for update
      to authenticated
      using (profile_id = auth.uid())
      with check (profile_id = auth.uid() and is_filled = true)
    $sql$;
  end if;

  if to_regclass('public.season_predictions') is not null then
    execute $sql$
      create policy "update_own_season_prediction"
      on public.season_predictions for update
      to authenticated
      using (predictor_profile_id = auth.uid())
      with check (predictor_profile_id = auth.uid() and is_filled = true)
    $sql$;
  end if;
end
$do$;
