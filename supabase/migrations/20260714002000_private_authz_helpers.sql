-- P0: move authorization helper logic out of the exposed public API schema.

create schema if not exists private;

create or replace function private.is_active_profile()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.status = 'active'
  );
$$;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.status = 'active'
  );
$$;

create or replace function private.is_match_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_admin();
$$;

create or replace function private.is_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and lower(coalesce(p.role::text, '')) in ('moderateur', 'moderator')
      and p.status = 'active'
  );
$$;

revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

revoke execute on function private.is_active_profile() from public, anon;
revoke execute on function private.is_admin() from public, anon;
revoke execute on function private.is_match_staff() from public, anon;
revoke execute on function private.is_moderator() from public, anon;

grant execute on function private.is_active_profile() to authenticated, service_role;
grant execute on function private.is_admin() to authenticated, service_role;
grant execute on function private.is_match_staff() to authenticated, service_role;
grant execute on function private.is_moderator() to authenticated, service_role;

-- Keep compatibility for privileged database functions, but remove these
-- wrappers from direct Data API execution.
create or replace function public.is_active_profile()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select private.is_active_profile(); $$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select private.is_admin(); $$;

create or replace function public.is_match_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select private.is_match_staff(); $$;

create or replace function public.is_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select private.is_moderator(); $$;

revoke execute on function public.is_active_profile() from public, anon, authenticated;
revoke execute on function public.is_admin() from public, anon, authenticated;
revoke execute on function public.is_match_staff() from public, anon, authenticated;
revoke execute on function public.is_moderator() from public, anon, authenticated;

grant execute on function public.is_active_profile() to service_role;
grant execute on function public.is_admin() to service_role;
grant execute on function public.is_match_staff() to service_role;
grant execute on function public.is_moderator() to service_role;

-- Rewrite RLS policies to use private helpers. These functions remain callable
-- by the authenticated role for policy evaluation, but are not exposed by the
-- Data API because the private schema is not an exposed API schema.
alter policy match_predictions_owner_insert
on public.match_predictions
with check (
  profile_id = (select auth.uid())
  and (select private.is_active_profile())
  and exists (
    select 1
    from public.matches m
    where m.id = match_predictions.match_id
      and m.status = 'a_venir'
      and now() < (
        (m.match_date + coalesce(m.match_time, time '00:00:00'))
        at time zone 'Europe/Paris'
      ) - interval '5 minutes'
  )
);

alter policy match_predictions_owner_update_window
on public.match_predictions
using (profile_id = (select auth.uid()))
with check (
  profile_id = (select auth.uid())
  and (select private.is_active_profile())
  and exists (
    select 1
    from public.matches m
    where m.id = match_predictions.match_id
      and m.status = 'a_venir'
      and now() < (
        (m.match_date + coalesce(m.match_time, time '00:00:00'))
        at time zone 'Europe/Paris'
      ) - interval '5 minutes'
  )
);

alter policy season_predictions_owner_insert
on public.season_predictions
with check (
  predictor_profile_id = (select auth.uid())
  and (select private.is_active_profile())
  and exists (
    select 1
    from public.seasons s
    where s.id = season_predictions.season_id
      and s.status = 'open'
      and s.season_predictions_locked_at is null
  )
);

alter policy season_predictions_owner_update
on public.season_predictions
using (predictor_profile_id = (select auth.uid()))
with check (
  predictor_profile_id = (select auth.uid())
  and (select private.is_active_profile())
  and exists (
    select 1
    from public.seasons s
    where s.id = season_predictions.season_id
      and s.status = 'open'
      and s.season_predictions_locked_at is null
  )
);

alter policy opponents_admin_insert
on public.opponents
with check ((select private.is_admin()) or (select private.is_moderator()));

alter policy opponents_moderator_update
on public.opponents
using ((select private.is_moderator()))
with check ((select private.is_moderator()));

alter policy opponents_moderator_delete
on public.opponents
using ((select private.is_moderator()));

alter policy matches_authorized_update
on public.matches
using (
  (select private.is_moderator())
  or ((select private.is_admin()) and status <> 'archive')
)
with check ((select private.is_moderator()) or (select private.is_admin()));

alter policy matches_staff_insert
on public.matches
with check (
  (select private.is_match_staff())
  and created_by = (select auth.uid())
);

alter policy matches_staff_delete
on public.matches
using ((select private.is_match_staff()));

alter policy profiles_update_authorized
on public.profiles
using (id = (select auth.uid()) or (select private.is_match_staff()))
with check (id = (select auth.uid()) or (select private.is_match_staff()));

alter policy season_players_staff_insert
on public.season_players
with check ((select private.is_match_staff()));

alter policy season_players_staff_update
on public.season_players
using ((select private.is_match_staff()))
with check ((select private.is_match_staff()));

alter policy season_players_staff_delete
on public.season_players
using ((select private.is_match_staff()));

alter policy seasons_staff_insert
on public.seasons
with check ((select private.is_match_staff()));

alter policy seasons_staff_update
on public.seasons
using ((select private.is_match_staff()))
with check ((select private.is_match_staff()));

alter policy seasons_staff_delete
on public.seasons
using ((select private.is_match_staff()));
