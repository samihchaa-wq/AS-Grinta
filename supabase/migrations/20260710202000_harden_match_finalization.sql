begin;

create or replace function public.finalize_match_postgame(
  p_match_id uuid,
  p_score_grinta integer,
  p_score_adverse integer,
  p_motm_profile_id uuid,
  p_player_stats jsonb,
  p_guest_stats jsonb default '[]'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path='public'
as $$
declare
  item jsonb;
  match_season_id uuid;
  profile_id_value uuid;
  computed_score_grinta integer := 0;
  computed_assists integer := 0;
  item_present boolean;
  item_goals integer;
  item_assists integer;
  item_penalty_faults integer;
  item_clean_sheet boolean;
begin
  if not public.is_admin() then
    raise exception 'Admin role required';
  end if;
  if p_score_adverse < 0 then
    raise exception 'Score adverse invalide';
  end if;

  select season_id into match_season_id
  from public.matches
  where id=p_match_id and status='a_venir'
  for update;

  if match_season_id is null then
    raise exception 'Only upcoming matches can be validated';
  end if;

  if jsonb_typeof(coalesce(p_player_stats,'[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_guest_stats,'[]'::jsonb)) <> 'array' then
    raise exception 'Invalid statistics payload';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_player_stats,'[]'::jsonb)) item
    group by item->>'profile_id'
    having count(*)>1 or nullif(item->>'profile_id','') is null
  ) then
    raise exception 'Player list contains duplicates or invalid identifiers';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_guest_stats,'[]'::jsonb))
      with ordinality as guest(item,position)
    group by lower(btrim(guest.item->>'display_name'))
    having count(*)>1
       or nullif(lower(btrim(guest.item->>'display_name')),'') is null
  ) then
    raise exception 'Guest names must be present and unique';
  end if;

  for item in
    select * from jsonb_array_elements(coalesce(p_player_stats,'[]'::jsonb))
  loop
    profile_id_value := nullif(item->>'profile_id','')::uuid;
    item_present := coalesce((item->>'present')::boolean,false);
    item_goals := coalesce((item->>'goals')::integer,0);
    item_assists := coalesce((item->>'assists')::integer,0);
    item_penalty_faults := coalesce((item->>'penalty_faults')::integer,0);
    item_clean_sheet := coalesce((item->>'clean_sheet')::boolean,false);

    if not exists (
      select 1
      from public.season_players sp
      join public.profiles p on p.id=sp.profile_id
      where sp.season_id=match_season_id
        and sp.profile_id=profile_id_value
        and p.status='active'
    ) then
      raise exception 'Player is not active in the match season squad';
    end if;

    if item_clean_sheet and not exists (
      select 1
      from public.season_players sp
      where sp.season_id=match_season_id
        and sp.profile_id=profile_id_value
        and sp.is_goalkeeper_snapshot=true
    ) then
      raise exception 'Only a goalkeeper can receive a clean sheet';
    end if;

    if item_goals < 0 or item_assists < 0 or item_penalty_faults < 0 then
      raise exception 'Negative statistics are not allowed';
    end if;
    if not item_present and (
      item_goals>0 or item_assists>0 or item_penalty_faults>0 or item_clean_sheet
    ) then
      raise exception 'Absent players cannot have statistics';
    end if;
    if item_clean_sheet and p_score_adverse>0 then
      raise exception 'Clean sheet is impossible when the opponent scored';
    end if;

    computed_score_grinta := computed_score_grinta + item_goals;
    computed_assists := computed_assists + item_assists;
  end loop;

  for item in
    select * from jsonb_array_elements(coalesce(p_guest_stats,'[]'::jsonb))
  loop
    item_present := coalesce((item->>'present')::boolean,true);
    item_goals := coalesce((item->>'goals')::integer,0);
    item_assists := coalesce((item->>'assists')::integer,0);
    item_penalty_faults := coalesce((item->>'penalty_faults')::integer,0);

    if item_goals < 0 or item_assists < 0 or item_penalty_faults < 0 then
      raise exception 'Negative statistics are not allowed';
    end if;
    if not item_present and (
      item_goals>0 or item_assists>0 or item_penalty_faults>0
    ) then
      raise exception 'Absent guests cannot have statistics';
    end if;

    computed_score_grinta := computed_score_grinta + item_goals;
    computed_assists := computed_assists + item_assists;
  end loop;

  if computed_assists>computed_score_grinta then
    raise exception 'Assists cannot exceed goals';
  end if;

  delete from public.match_player_stats where match_id=p_match_id;
  delete from public.match_guest_stats where match_id=p_match_id;
  delete from public.match_motm where match_id=p_match_id;
  delete from public.match_participants where match_id=p_match_id;

  for item in
    select * from jsonb_array_elements(coalesce(p_player_stats,'[]'::jsonb))
  loop
    insert into public.match_player_stats(
      match_id,profile_id,present,goals,assists,penalty_faults,clean_sheet
    )
    values(
      p_match_id,
      (item->>'profile_id')::uuid,
      coalesce((item->>'present')::boolean,false),
      coalesce((item->>'goals')::integer,0),
      coalesce((item->>'assists')::integer,0),
      coalesce((item->>'penalty_faults')::integer,0),
      coalesce((item->>'clean_sheet')::boolean,false)
    );

    if coalesce((item->>'present')::boolean,false) then
      insert into public.match_participants(match_id,profile_id)
      values(p_match_id,(item->>'profile_id')::uuid)
      on conflict(match_id,profile_id) do nothing;
    end if;
  end loop;

  for item in
    select * from jsonb_array_elements(coalesce(p_guest_stats,'[]'::jsonb))
  loop
    insert into public.match_guest_stats(
      match_id,display_name,position,present,goals,assists,penalty_faults
    )
    values(
      p_match_id,
      btrim(item->>'display_name'),
      coalesce(nullif(btrim(item->>'position'),''),'Joueur'),
      coalesce((item->>'present')::boolean,true),
      coalesce((item->>'goals')::integer,0),
      coalesce((item->>'assists')::integer,0),
      coalesce((item->>'penalty_faults')::integer,0)
    );
  end loop;

  if p_motm_profile_id is not null then
    if not exists(
      select 1 from public.match_participants
      where match_id=p_match_id and profile_id=p_motm_profile_id
    ) then
      raise exception 'MOTM must be a present player';
    end if;

    insert into public.match_motm(match_id,profile_id,created_by)
    values(p_match_id,p_motm_profile_id,auth.uid());
  end if;

  update public.matches
  set score_as_grinta=computed_score_grinta,
      score_adverse=p_score_adverse,
      status='termine',
      result_validated_at=now(),
      updated_at=now()
  where id=p_match_id and status='a_venir';

  return found;
end;
$$;

revoke all on function public.finalize_match_postgame(
  uuid,integer,integer,uuid,jsonb,jsonb
) from public,anon;
grant execute on function public.finalize_match_postgame(
  uuid,integer,integer,uuid,jsonb,jsonb
) to authenticated;

commit;
