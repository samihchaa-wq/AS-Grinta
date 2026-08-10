-- These legacy policies were applied in production after additional objects had
-- already been created outside the recorded history. Keep clean replays ordered:
-- install each policy only when its required relation/column exists at this point.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'status'
  ) then
    execute $policy$
      create policy "insert_own_profile"
      on public.profiles for insert
      to authenticated
      with check (id = auth.uid() and role = 'pronostiqueur' and status = 'active')
    $policy$;
  end if;
end;
$$;

create policy "update_own_profile"
on public.profiles for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

do $$
begin
  if to_regclass('public.match_predictions') is not null then
    execute $policy$
      create policy "update_own_match_prediction"
      on public.match_predictions for update
      to authenticated
      using (profile_id = auth.uid())
      with check (profile_id = auth.uid() and is_filled = true)
    $policy$;
  end if;

  if to_regclass('public.season_predictions') is not null then
    execute $policy$
      create policy "update_own_season_prediction"
      on public.season_predictions for update
      to authenticated
      using (predictor_profile_id = auth.uid())
      with check (predictor_profile_id = auth.uid() and is_filled = true)
    $policy$;
  end if;
end;
$$;
