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

  select count(*)::integer,
         min(candidate.player_id::text)::uuid
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
