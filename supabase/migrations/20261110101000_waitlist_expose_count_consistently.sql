-- Une seule source de données pour la vue admin et la vue lecture seule.
begin;

-- Seuls les contrôles d'accès diffèrent entre les deux RPC.
create or replace function private.sport_waitlist_payload(p_season_id uuid)
returns jsonb
language sql stable security definer set search_path to ''
as $$
  select jsonb_build_object(
    'season_id', s.id,
    'season_name', s.name,
    'entries', coalesce(jsonb_agg(jsonb_build_object(
      'season_player_id', p.id,
      'first_name', p.first_name,
      'last_name', p.last_name,
      'display_name', coalesce(nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''), btrim(p.first_name)),
      'position', e.position,
      'previous_season_attendance_count', e.previous_season_attendance_count,
      'previous_season_match_count', e.previous_season_match_count,
      'current_season_waitlist_count', e.manual_waitlist_count,
      'source', e.source,
      'updated_at', e.updated_at
    ) order by e.position) filter (where p.id is not null), '[]'::jsonb)
  )
  from public.seasons s
  left join public.sport_waitlist_entries e on e.season_id = s.id
  left join public.season_players p on p.id = e.season_player_id
  left join public.profiles profile on profile.id = p.profile_id
  where s.id = p_season_id
  group by s.id, s.name;
$$;

create or replace function private.get_sport_waitlist(p_season_id uuid default null)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v_season_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  v_season_id := private.resolve_open_sport_season(p_season_id);
  perform private.ensure_sport_waitlist(v_season_id, (select auth.uid()));
  perform private.finalize_due_waitlist_turns_for_season(v_season_id);
  return private.sport_waitlist_payload(v_season_id);
end;
$$;

create or replace function private.get_sport_waitlist_readonly(p_season_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  return private.sport_waitlist_payload(
    private.resolve_open_sport_season(p_season_id)
  );
end;
$$;

-- Ne pas exposer les fonctions privilégiées via la Data API.
revoke all on function private.sport_waitlist_payload(uuid)
  from public, anon, authenticated;
revoke all on function private.get_sport_waitlist(uuid)
  from public, anon, authenticated;
revoke all on function private.get_sport_waitlist_readonly(uuid)
  from public, anon, authenticated;

commit;
