-- La liste d'attente n'était consultable que par l'admin. Les joueurs
-- doivent pouvoir la voir (ordre, présence saison précédente, nombre de
-- fois en liste d'attente), sans jamais pouvoir la modifier. Contrairement
-- à la version admin, cette lecture ne déclenche aucun effet de bord
-- (pas d'initialisation ni de clôture des tours en retard) : elle se
-- contente de lire l'état déjà maintenu par l'admin.
create or replace function private.get_sport_waitlist_readonly(
  p_season_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_season_id uuid;
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  v_season_id := private.resolve_open_sport_season(p_season_id);

  select jsonb_build_object(
    'season_id', season.id,
    'season_name', season.name,
    'entries', coalesce(jsonb_agg(
      jsonb_build_object(
        'season_player_id', player.id,
        'first_name', player.first_name,
        'last_name', player.last_name,
        'display_name', coalesce(nullif(btrim(profile.surnom), ''), btrim(player.first_name)),
        'position', entry.position,
        'previous_season_attendance_count', entry.previous_season_attendance_count,
        'previous_season_match_count', entry.previous_season_match_count,
        'source', entry.source,
        'updated_at', entry.updated_at
      )
      order by entry.position
    ), '[]'::jsonb)
  )
  into v_result
  from public.seasons season
  left join public.sport_waitlist_entries entry on entry.season_id = season.id
  left join public.season_players player on player.id = entry.season_player_id
  left join public.profiles profile on profile.id = player.profile_id
  where season.id = v_season_id
  group by season.id, season.name;

  return v_result;
end;
$function$;

create or replace function public.get_sport_waitlist(p_season_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.enrich_sport_waitlist_history(
    private.get_sport_waitlist_readonly(p_season_id)
  );
$function$;

revoke all on function private.get_sport_waitlist_readonly(uuid) from public, anon;
revoke all on function public.get_sport_waitlist(uuid) from public, anon;

grant execute on function private.get_sport_waitlist_readonly(uuid) to authenticated;
grant execute on function public.get_sport_waitlist(uuid) to authenticated;

comment on function public.get_sport_waitlist(uuid) is
  'Lecture seule de la liste d''attente de la saison, accessible à tout joueur actif ; aucune modification possible par cette voie.';
