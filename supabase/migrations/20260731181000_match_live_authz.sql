-- Coach-or-admin write access to the Tableau Blanc: admin always qualifies;
-- otherwise the caller must be the season_players row flagged is_coach=true
-- (set in the roster admin "Ajouter un joueur" dialog) for the match's season,
-- linked via season_players.profile_id. Not a profiles.role concept.

create or replace function private.is_match_coach_or_admin(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_admin()
    or exists (
      select 1
      from public.season_players sp
      join public.matches m on m.season_id = sp.season_id
      where m.id = p_match_id
        and sp.profile_id = (select auth.uid())
        and sp.is_coach = true
        and sp.is_active = true
    );
$$;

revoke execute on function private.is_match_coach_or_admin(uuid) from public, anon;
grant execute on function private.is_match_coach_or_admin(uuid) to authenticated, service_role;
