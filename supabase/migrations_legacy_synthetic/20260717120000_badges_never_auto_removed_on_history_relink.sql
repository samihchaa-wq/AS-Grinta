-- Règle : un badge gagné est acquis à vie. Le rattachement d'historique ne
-- doit JAMAIS retirer de badge de palier — il ne fait qu'ajouter ceux
-- nouvellement mérités. (Le retrait reste possible manuellement via
-- staff_revoke_badge.)
create or replace function public.staff_set_historical_profile(
  p_profile_id uuid, p_historical_id bigint
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_name text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_profile_id is null then
    raise exception 'Profile id is required' using errcode = '22023';
  end if;

  -- Détache l'historique actuellement rattaché à ce compte.
  update public.historical_player_statistics
    set profile_id = null, updated_at = now()
    where profile_id = p_profile_id;

  -- Rattache toutes les lignes du joueur choisi (même nom) à ce compte.
  if p_historical_id is not null then
    select player_name into v_name
      from public.historical_player_statistics where id = p_historical_id;
    if v_name is null then
      raise exception 'Historical record not found' using errcode = 'P0002';
    end if;
    update public.historical_player_statistics
      set profile_id = p_profile_id, updated_at = now()
      where lower(btrim(player_name)) = lower(btrim(v_name));
  end if;

  -- Ajoute les badges nouvellement mérités (jamais de retrait automatique :
  -- un badge gagné reste acquis à vie).
  perform public.recalculate_profile_badges(p_profile_id);
  return true;
end;
$function$;

grant execute on function public.staff_set_historical_profile(uuid, bigint) to authenticated;
