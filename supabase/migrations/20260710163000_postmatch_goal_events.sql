begin;

alter table public.goals
  add column if not exists scorer_display_name text,
  add column if not exists assist_display_name text;

alter table public.goals drop constraint if exists goals_players_consistency;
alter table public.goals add constraint goals_players_consistency check (
  (
    team='adverse'
    and scorer_profile_id is null
    and scorer_display_name is null
    and assist_profile_id is null
    and assist_display_name is null
    and assist_type is null
  )
  or
  (
    team='as_grinta'
    and goal_type='csc_adverse'
    and scorer_profile_id is null
    and scorer_display_name is null
    and assist_profile_id is null
    and assist_display_name is null
    and assist_type is null
  )
  or
  (
    team='as_grinta'
    and goal_type in ('jeu','penalty','coup_franc')
    and (
      (scorer_profile_id is not null and nullif(btrim(coalesce(scorer_display_name,'')),'') is null)
      or
      (scorer_profile_id is null and nullif(btrim(coalesce(scorer_display_name,'')),'') is not null)
    )
    and (
      (
        assist_type='connu'
        and (
          (assist_profile_id is not null and nullif(btrim(coalesce(assist_display_name,'')),'') is null)
          or
          (assist_profile_id is null and nullif(btrim(coalesce(assist_display_name,'')),'') is not null)
        )
      )
      or
      (
        assist_type in ('sans_passe','inconnu')
        and assist_profile_id is null
        and nullif(btrim(coalesce(assist_display_name,'')),'') is null
      )
    )
    and assist_profile_id is distinct from scorer_profile_id
  )
);

create or replace function public.finalize_match_postgame(
  p_match_id uuid,
  p_score_grinta integer,
  p_score_adverse integer,
  p_motm_profile_id uuid,
  p_player_stats jsonb,
  p_guest_stats jsonb default '[]'::jsonb,
  p_goals jsonb default '[]'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path='public'
as $$
declare
  item jsonb;
  goal_item jsonb;
  computed_score_grinta integer := 0;
  scorer_profile uuid;
  assister_profile uuid;
  scorer_name text;
  assister_name text;
begin
  if not public.is_admin() then raise exception 'Admin role required'; end if;
  if p_score_adverse < 0 then raise exception 'Score adverse invalide'; end if;
  if not exists(select 1 from public.matches where id=p_match_id and status='a_venir') then
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

  computed_score_grinta := jsonb_array_length(coalesce(p_goals,'[]'::jsonb));

  delete from public.goals where match_id=p_match_id;
  delete from public.match_player_stats where match_id=p_match_id;
  delete from public.match_guest_stats where match_id=p_match_id;
  delete from public.match_motm where match_id=p_match_id;
  delete from public.match_participants where match_id=p_match_id;

  for item in select * from jsonb_array_elements(coalesce(p_player_stats,'[]'::jsonb)) loop
    insert into public.match_player_stats(
      match_id,profile_id,present,goals,assists,penalty_faults,clean_sheet
    )
    values(
      p_match_id,
      (item->>'profile_id')::uuid,
      coalesce((item->>'present')::boolean,false),
      0,
      0,
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
    insert into public.match_guest_stats(
      match_id,display_name,position,present,goals,assists,penalty_faults
    )
    values(
      p_match_id,
      btrim(item->>'display_name'),
      coalesce(nullif(btrim(item->>'position'),''),'Joueur'),
      coalesce((item->>'present')::boolean,true),
      0,
      0,
      greatest(coalesce((item->>'penalty_faults')::integer,0),0)
    );
  end loop;

  for goal_item in select * from jsonb_array_elements(coalesce(p_goals,'[]'::jsonb)) loop
    scorer_profile := nullif(goal_item->>'scorer_profile_id','')::uuid;
    assister_profile := nullif(goal_item->>'assist_profile_id','')::uuid;
    scorer_name := nullif(btrim(coalesce(goal_item->>'scorer_display_name','')),'');
    assister_name := nullif(btrim(coalesce(goal_item->>'assist_display_name','')),'');

    if scorer_profile is not null and not exists (
      select 1 from public.match_participants
      where match_id=p_match_id and profile_id=scorer_profile
    ) then
      raise exception 'Scorer must be a present player';
    end if;
    if assister_profile is not null and not exists (
      select 1 from public.match_participants
      where match_id=p_match_id and profile_id=assister_profile
    ) then
      raise exception 'Assister must be a present player';
    end if;
    if scorer_name is not null and not exists (
      select 1 from public.match_guest_stats
      where match_id=p_match_id and present and lower(display_name)=lower(scorer_name)
    ) then
      raise exception 'Guest scorer must be present';
    end if;
    if assister_name is not null and not exists (
      select 1 from public.match_guest_stats
      where match_id=p_match_id and present and lower(display_name)=lower(assister_name)
    ) then
      raise exception 'Guest assister must be present';
    end if;

    insert into public.goals(
      match_id,team,minute,goal_type,
      scorer_profile_id,scorer_display_name,
      assist_type,assist_profile_id,assist_display_name
    ) values(
      p_match_id,
      'as_grinta',
      greatest(least(coalesce((goal_item->>'minute')::integer,0),100),0),
      coalesce(nullif(goal_item->>'goal_type',''),'jeu'),
      scorer_profile,
      scorer_name,
      case when assister_profile is not null or assister_name is not null
        then 'connu' else 'sans_passe' end,
      assister_profile,
      assister_name
    );
  end loop;

  update public.match_player_stats s
  set goals=(
        select count(*) from public.goals g
        where g.match_id=p_match_id and g.scorer_profile_id=s.profile_id
      ),
      assists=(
        select count(*) from public.goals g
        where g.match_id=p_match_id and g.assist_profile_id=s.profile_id
      )
  where s.match_id=p_match_id;

  update public.match_guest_stats s
  set goals=(
        select count(*) from public.goals g
        where g.match_id=p_match_id
          and lower(g.scorer_display_name)=lower(s.display_name)
      ),
      assists=(
        select count(*) from public.goals g
        where g.match_id=p_match_id
          and lower(g.assist_display_name)=lower(s.display_name)
      )
  where s.match_id=p_match_id;

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
  uuid,integer,integer,uuid,jsonb,jsonb,jsonb
) from public,anon;
grant execute on function public.finalize_match_postgame(
  uuid,integer,integer,uuid,jsonb,jsonb,jsonb
) to authenticated;

commit;
