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
  if not exists(
    select 1 from public.matches
    where id=p_match_id and status='a_venir'
  ) then
    raise exception 'Only upcoming matches can be validated';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_guest_stats,'[]'::jsonb)) g1
    join jsonb_array_elements(coalesce(p_guest_stats,'[]'::jsonb)) g2
      on lower(btrim(g1->>'display_name'))=lower(btrim(g2->>'display_name'))
     and g1::text<g2::text
  ) then
    raise exception 'Guest names must be unique';
  end if;

  for item in
    select * from jsonb_array_elements(
      coalesce(p_player_stats,'[]'::jsonb) ||
      coalesce(p_guest_stats,'[]'::jsonb)
    )
  loop
    item_present := coalesce((item->>'present')::boolean,false);
    item_goals := coalesce((item->>'goals')::integer,0);
    item_assists := coalesce((item->>'assists')::integer,0);
    item_penalty_faults := coalesce((item->>'penalty_faults')::integer,0);
    item_clean_sheet := coalesce((item->>'clean_sheet')::boolean,false);

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
    if btrim(coalesce(item->>'display_name',''))='' then
      raise exception 'Nom invité requis';
    end if;

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
