create or replace function private.create_player_identity(p_display_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player_id uuid;
  v_display_name text := nullif(btrim(p_display_name), '');
  v_normalized text;
  v_candidate_count integer;
begin
  if v_display_name is null then
    raise exception 'Player display name is required' using errcode = '22023';
  end if;

  v_normalized := private.normalize_player_name(v_display_name);

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(coalesce(v_normalized, v_display_name), 0)
  );

  select count(*)::integer, min(candidate.player_id)
    into v_candidate_count, v_player_id
  from (
    select distinct pa.player_id
    from public.player_aliases pa
    where private.normalize_player_name(pa.alias) = v_normalized
      and not exists (
        select 1 from public.profiles p where p.player_id = pa.player_id
      )
      and not exists (
        select 1 from public.season_players sp where sp.player_id = pa.player_id
      )
      and not exists (
        select 1 from public.guest_players gp where gp.player_id = pa.player_id
      )
      and not exists (
        select 1 from public.historical_match_players hmp where hmp.player_id = pa.player_id
      )
      and not exists (
        select 1 from public.historical_player_name_links hpnl where hpnl.player_id = pa.player_id
      )
      and not exists (
        select 1 from public.historical_player_statistics hps where hps.player_id = pa.player_id
      )
  ) candidate;

  if v_candidate_count = 1 and v_player_id is not null then
    insert into public.player_aliases(player_id, alias)
    values (v_player_id, v_display_name)
    on conflict do nothing;
    return v_player_id;
  end if;

  insert into public.players(display_name)
  values (v_display_name)
  returning id into v_player_id;

  insert into public.player_aliases(player_id, alias)
  values (v_player_id, v_display_name)
  on conflict do nothing;

  return v_player_id;
end;
$function$;

-- Remove audit/test identities only when they are still completely unreferenced.
delete from public.players p
where p.id in (
  'd7463354-676c-4312-a5b1-43a6868a8c6c'::uuid,
  'af099c78-139d-4cff-ba9c-43ad26c2f52d'::uuid,
  'e5399af5-1679-42da-a526-0d5c86b17498'::uuid,
  '347067ed-9173-466d-8641-eea6036d0d61'::uuid
)
  and not exists (select 1 from public.profiles x where x.player_id = p.id)
  and not exists (select 1 from public.season_players x where x.player_id = p.id)
  and not exists (select 1 from public.guest_players x where x.player_id = p.id)
  and not exists (select 1 from public.historical_match_players x where x.player_id = p.id)
  and not exists (select 1 from public.historical_player_name_links x where x.player_id = p.id)
  and not exists (select 1 from public.historical_player_statistics x where x.player_id = p.id);
