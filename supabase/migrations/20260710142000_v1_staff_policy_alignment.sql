begin;

create or replace function public.guard_sensitive_profile_fields()
returns trigger
language plpgsql
security definer
set search_path='public'
as $$
begin
  if auth.uid()=old.id and not public.is_match_staff() then
    if new.role is distinct from old.role
       or new.status is distinct from old.status
       or new.is_goalkeeper is distinct from old.is_goalkeeper then
      raise exception 'Sensitive profile fields require a staff role';
    end if;
  end if;
  return new;
end;
$$;

drop policy if exists profiles_update_authorized on public.profiles;
create policy profiles_update_authorized
on public.profiles for update to authenticated
using (id=(select auth.uid()) or public.is_match_staff())
with check (id=(select auth.uid()) or public.is_match_staff());

drop policy if exists seasons_moderator_insert on public.seasons;
drop policy if exists seasons_moderator_update on public.seasons;
drop policy if exists seasons_moderator_delete on public.seasons;
create policy seasons_staff_insert on public.seasons
for insert to authenticated with check (public.is_match_staff());
create policy seasons_staff_update on public.seasons
for update to authenticated using (public.is_match_staff()) with check (public.is_match_staff());
create policy seasons_staff_delete on public.seasons
for delete to authenticated using (public.is_match_staff());

drop policy if exists season_players_moderator_insert on public.season_players;
drop policy if exists season_players_moderator_update on public.season_players;
drop policy if exists season_players_moderator_delete on public.season_players;
create policy season_players_staff_insert on public.season_players
for insert to authenticated with check (public.is_match_staff());
create policy season_players_staff_update on public.season_players
for update to authenticated using (public.is_match_staff()) with check (public.is_match_staff());
create policy season_players_staff_delete on public.season_players
for delete to authenticated using (public.is_match_staff());

commit;
