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
begin
  if not public.is_admin() then raise exception 'Admin role required'; end if;
  if p_score_adverse < 0 then raise exception 'Score adverse invalide'; end if;
  if not exists(select 1 from public.matches where id=p_match_id and status='a_venir') then
    raise exception 'Only upcoming matches can be validated';
  end if;

  select coalesce(sum(coalesce((x->>'goals')::integer,0)),0)::integer
    into computed_score_grinta
  from jsonb_array_elements(coalesce(p_player_stats,'[]'::jsonb)) x;
  select computed_score_grinta + coalesce(sum(coalesce((x->>'goals')::integer,0)),0)::integer
    into computed_score_grinta
  from jsonb_array_elements(coalesce(p_guest_stats,'[]'::jsonb)) x;

  delete from public.match_player_stats where match_id=p_match_id;
  delete from public.match_guest_stats where match_id=p_match_id;
  delete from public.match_motm where match_id=p_match_id;
  delete from public.match_participants where match_id=p_match_id;

  for item in select * from jsonb_array_elements(coalesce(p_player_stats,'[]'::jsonb)) loop
    insert into public.match_player_stats(match_id,profile_id,present,goals,assists,penalty_faults,clean_sheet)
    values(
      p_match_id,
      (item->>'profile_id')::uuid,
      coalesce((item->>'present')::boolean,false),
      greatest(coalesce((item->>'goals')::integer,0),0),
      greatest(coalesce((item->>'assists')::integer,0),0),
      greatest(coalesce((item->>'penalty_faults')::integer,0),0),
      coalesce((item->>'clean_sheet')::boolean,false)
    );
    if coalesce((item->>'present')::boolean,false) then
      insert into public.match_participants(match_id,profile_id)
      values(p_match_id,(item->>'profile_id')::uuid)
      on conflict(match_id,profile_id) do nothing;
    end if;
  end loop;

  for item in select * from jsonb_array_elements(coalesce(p_guest_stats,'[]'::jsonb)) loop
    if btrim(coalesce(item->>'display_name',''))='' then raise exception 'Nom invité requis'; end if;
    insert into public.match_guest_stats(match_id,display_name,position,present,goals,assists,penalty_faults)
    values(
      p_match_id,
      btrim(item->>'display_name'),
      coalesce(nullif(btrim(item->>'position'),''),'Joueur'),
      coalesce((item->>'present')::boolean,true),
      greatest(coalesce((item->>'goals')::integer,0),0),
      greatest(coalesce((item->>'assists')::integer,0),0),
      greatest(coalesce((item->>'penalty_faults')::integer,0),0)
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

revoke all on function public.finalize_match_postgame(uuid,integer,integer,uuid,jsonb,jsonb) from public, anon;
grant execute on function public.finalize_match_postgame(uuid,integer,integer,uuid,jsonb,jsonb) to authenticated;
