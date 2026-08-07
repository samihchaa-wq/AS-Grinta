-- merge_player_identities a été écrite avant historical_player_name_links et
-- ne la reprojetait pas : toute fusion touchant une identité déjà résolue
-- depuis les archives échouait sur la contrainte de clé étrangère.
create or replace function private.merge_player_identities(
  p_source_player_id uuid,
  p_target_player_id uuid
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if p_source_player_id is null
     or p_target_player_id is null
     or p_source_player_id = p_target_player_id then
    return;
  end if;

  if not exists (
    select 1 from public.players p where p.id = p_source_player_id
  ) or not exists (
    select 1 from public.players p where p.id = p_target_player_id
  ) then
    raise exception 'Canonical player identity not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.profiles p where p.player_id = p_source_player_id
  ) then
    raise exception 'Cannot merge two account-backed player identities'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.historical_match_players source_row
    join public.historical_match_players target_row
      on target_row.match_id = source_row.match_id
     and target_row.player_id = p_target_player_id
    where source_row.player_id = p_source_player_id
  ) then
    raise exception 'Archived match contains both player identities; manual resolution required'
      using errcode = '23514';
  end if;

  delete from public.player_aliases source_alias
  using public.player_aliases target_alias
  where source_alias.player_id = p_source_player_id
    and target_alias.player_id = p_target_player_id
    and private.normalize_player_name(source_alias.alias)
      = private.normalize_player_name(target_alias.alias);

  update public.player_aliases
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.historical_match_players
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.historical_player_name_links
  set player_id = p_target_player_id, updated_at = now()
  where player_id = p_source_player_id;

  update public.historical_player_statistics
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.guest_players
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.season_players
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  delete from public.players
  where id = p_source_player_id;
end;
$function$;

revoke all on function private.merge_player_identities(uuid, uuid)
  from public, anon, authenticated;
