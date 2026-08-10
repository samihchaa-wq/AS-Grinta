alter table public.seasons
  add column if not exists season_predictions_locked_at timestamptz;

create or replace function public.is_active_profile()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and status = 'active'
  );
$$;

grant execute on function public.is_active_profile() to authenticated;

drop policy if exists match_predictions_owner_insert on public.match_predictions;
create policy match_predictions_owner_insert on public.match_predictions
  for insert to authenticated
  with check (
    profile_id = (select auth.uid())
    and public.is_active_profile()
    and exists (
      select 1 from public.matches m
      where m.id = match_predictions.match_id
        and m.status = 'a_venir'
        and now() < (
          ((m.match_date + coalesce(m.match_time, '00:00:00'::time))
            at time zone 'Europe/Paris') - interval '5 minutes'
        )
    )
  );

drop policy if exists match_predictions_owner_update_window
  on public.match_predictions;
create policy match_predictions_owner_update_window on public.match_predictions
  for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (
    profile_id = (select auth.uid())
    and public.is_active_profile()
    and exists (
      select 1 from public.matches m
      where m.id = match_predictions.match_id
        and m.status = 'a_venir'
        and now() < (
          ((m.match_date + coalesce(m.match_time, '00:00:00'::time))
            at time zone 'Europe/Paris') - interval '5 minutes'
        )
    )
  );

drop policy if exists season_predictions_owner_insert on public.season_predictions;
create policy season_predictions_owner_insert on public.season_predictions
  for insert to authenticated
  with check (
    predictor_profile_id = (select auth.uid())
    and public.is_active_profile()
    and exists (
      select 1 from public.seasons s
      where s.id = season_predictions.season_id
        and s.status = 'open'
        and s.season_predictions_locked_at is null
    )
  );

drop policy if exists season_predictions_owner_update on public.season_predictions;
create policy season_predictions_owner_update on public.season_predictions
  for update to authenticated
  using (predictor_profile_id = (select auth.uid()))
  with check (
    predictor_profile_id = (select auth.uid())
    and public.is_active_profile()
    and exists (
      select 1 from public.seasons s
      where s.id = season_predictions.season_id
        and s.status = 'open'
        and s.season_predictions_locked_at is null
    )
  );

create or replace function public.set_season_predictions_lock(
  p_season_id uuid,
  p_locked boolean
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;
  update public.seasons
    set season_predictions_locked_at =
      case when p_locked then now() else null end
  where id = p_season_id;
  return found;
end;
$$;

grant execute on function public.set_season_predictions_lock(uuid, boolean)
  to authenticated;;
