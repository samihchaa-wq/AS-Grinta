create or replace function private.get_match_availability_board(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'kickoff_at', match.kickoff_at,
    'availability_state', case
      when now() >= match.kickoff_at then 'closed'
      when now() >= workflow.availability_opens_at
        and workflow.availability_state = 'pending' then 'open'
      else workflow.availability_state::text
    end,
    'availability_opens_at', workflow.availability_opens_at,
    'composition_published', exists (
      select 1
      from public.match_composition_publications publication
      where publication.match_id = match.id
    ),
    'players', coalesce(jsonb_agg(
      jsonb_build_object(
        'first_name', player.first_name,
        'last_name', player.last_name,
        'status', participant.availability_status
      )
      order by
        lower(player.first_name),
        lower(player.last_name)
    ) filter (where participant.id is not null), '[]'::jsonb)
  )
  into v_result
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_participants participant
    on participant.match_id = match.id
   and participant.is_eligible
   and participant.season_player_id is not null
  left join public.season_players player
    on player.id = participant.season_player_id
  where match.id = p_match_id
  group by match.id, workflow.match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

create or replace function public.get_match_availability_board(p_match_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.get_match_availability_board(p_match_id); $function$;

revoke execute on function private.get_match_availability_board(uuid) from public, anon;
grant execute on function private.get_match_availability_board(uuid) to authenticated, service_role;
revoke execute on function public.get_match_availability_board(uuid) from public, anon;
grant execute on function public.get_match_availability_board(uuid) to authenticated, service_role;

comment on function public.get_match_availability_board(uuid) is
  'Present/absent/no-response lists for one match, visible to active profiles until the composition is published.';
