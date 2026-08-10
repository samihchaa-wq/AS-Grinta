begin;

alter table public.profiles drop constraint if exists profiles_status_check;
alter table public.profiles add constraint profiles_status_check
  check (status in ('pending','active','archived'));

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(
    id,email,first_name,last_name,role,is_goalkeeper,status
  ) values (
    new.id,
    coalesce(new.email,''),
    coalesce(new.raw_user_meta_data->>'first_name',''),
    coalesce(new.raw_user_meta_data->>'last_name',''),
    'pronostiqueur',
    false,
    case
      when coalesce((new.raw_user_meta_data->>'approval_required')::boolean, false)
        then 'pending'
      else 'active'
    end
  )
  on conflict(id) do update
  set email=excluded.email,
      first_name=case when public.profiles.first_name='' then excluded.first_name else public.profiles.first_name end,
      last_name=case when public.profiles.last_name='' then excluded.last_name else public.profiles.last_name end,
      updated_at=now();
  return new;
end;
$$;

drop policy if exists matches_admin_insert on public.matches;
create policy matches_admin_insert on public.matches
for insert to authenticated
with check (
  (public.is_admin() or public.is_moderator())
  and created_by = auth.uid()
);

insert into public.season_players(season_id, profile_id, is_goalkeeper_snapshot)
select s.id, p.id, p.is_goalkeeper
from public.seasons s
cross join public.profiles p
where s.status='open' and p.status='active'
on conflict (season_id,profile_id) do nothing;

update public.matches
set match_time = time '21:00:00'
where status='archive' and match_time is null;

commit;
