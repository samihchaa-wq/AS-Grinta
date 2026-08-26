-- Read-only data contract for the finished-match modules.
--
-- The final squad must be visible to every active member once the match has
-- been validated, without widening direct RLS access to match_sport_participants.

create or replace function private.get_completed_match_effectif(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select case
    when match.status not in ('termine', 'archive')
      or workflow.presence_state <> 'confirmed'
      then null
    else jsonb_build_object(
      'match_id', match.id,
      'players', coalesce(
        jsonb_agg(
          jsonb_build_object(
            'participant_id', participant.id,
            'display_name', case
              when guest.id is not null then coalesce(
                nullif(btrim(guest.first_name), ''),
                nullif(btrim(concat_ws(' ', guest.first_name, guest.last_name)), ''),
                'Invité'
              )
              else coalesce(
                nullif(btrim(profile.surnom), ''),
                nullif(btrim(profile.first_name), ''),
                nullif(btrim(player.first_name), ''),
                nullif(btrim(concat_ws(' ', player.first_name, player.last_name)), ''),
                'Joueur'
              )
            end,
            'is_guest', guest.id is not null,
            'presence_status', case participant.final_presence_status
              when 'present' then 'present'
              when 'actual_absent' then 'absent'
              else null
            end,
            'final_selection_status', participant.final_selection_status
          )
          order by
            case participant.final_presence_status
              when 'present' then 0
              when 'actual_absent' then 1
              else 2
            end,
            lower(coalesce(
              nullif(btrim(profile.surnom), ''),
              nullif(btrim(profile.first_name), ''),
              nullif(btrim(player.first_name), ''),
              nullif(btrim(guest.first_name), ''),
              ''
            )),
            participant.id
        ) filter (
          where participant.id is not null
            and participant.final_presence_status in ('present', 'actual_absent')
        ),
        '[]'::jsonb
      )
    )
  end
  into v_result
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_participants participant
    on participant.match_id = match.id
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  where match.id = p_match_id
  group by match.id, match.status, workflow.presence_state;

  return v_result;
end;
$function$;

revoke all on function private.get_completed_match_effectif(uuid)
  from public, anon, authenticated;
grant execute on function private.get_completed_match_effectif(uuid)
  to authenticated, service_role;

create or replace function public.get_completed_match_effectif(p_match_id uuid)
returns jsonb
language sql
stable
set search_path to ''
as $function$
  select private.get_completed_match_effectif(p_match_id);
$function$;

revoke all on function public.get_completed_match_effectif(uuid)
  from public, anon;
grant execute on function public.get_completed_match_effectif(uuid)
  to authenticated, service_role;

-- Historical sources currently know who was present but do not reliably know
-- who was absent. NULL deliberately means "not extracted / unknown", while []
-- means that the source explicitly confirms that nobody was absent. This lets
-- the UI hide the Effectif module until the archive is actually complete.
alter table public.historical_match_details
  add column if not exists absent_names jsonb;

alter table public.historical_match_details
  drop constraint if exists historical_match_details_absent_names_array;
alter table public.historical_match_details
  add constraint historical_match_details_absent_names_array
  check (absent_names is null or jsonb_typeof(absent_names) = 'array');

comment on column public.historical_match_details.absent_names is
  'Names explicitly marked absent by the historical source. NULL means the source did not provide reliable absence data.';

-- Return the optional absence list through the existing read-only archive RPC.
-- The return type changes, so PostgreSQL requires a drop/recreate.
drop function if exists public.get_historical_match_detail(uuid);
drop function if exists private.get_historical_match_detail(uuid);

create function private.get_historical_match_detail(p_match_id uuid)
returns table (
  formation text,
  field_players jsonb,
  bench_players jsonb,
  present_names jsonb,
  absent_names jsonb,
  scorers jsonb,
  motm_names jsonb,
  photo_urls jsonb
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  return query
  select
    d.formation,
    d.field_players,
    d.bench_players,
    d.present_names,
    d.absent_names,
    d.scorers,
    d.motm_names,
    coalesce(
      (
        select jsonb_object_agg(
          hmp.source_name,
          coalesce(pr.photo_url, sp.photo_url)
        )
        from public.historical_match_players hmp
        left join public.profiles pr on pr.player_id = hmp.player_id
        left join lateral (
          select season_players.photo_url
          from public.season_players
          where season_players.player_id = hmp.player_id
            and season_players.photo_url is not null
          order by season_players.joined_at desc
          limit 1
        ) sp on true
        where hmp.match_id = d.match_id
          and coalesce(pr.photo_url, sp.photo_url) is not null
      ),
      '{}'::jsonb
    ) as photo_urls
  from public.historical_match_details d
  where d.match_id = p_match_id;
end;
$function$;

revoke all on function private.get_historical_match_detail(uuid)
  from public, anon;
grant execute on function private.get_historical_match_detail(uuid)
  to authenticated, service_role;

create function public.get_historical_match_detail(p_match_id uuid)
returns table (
  formation text,
  field_players jsonb,
  bench_players jsonb,
  present_names jsonb,
  absent_names jsonb,
  scorers jsonb,
  motm_names jsonb,
  photo_urls jsonb
)
language sql
stable
set search_path to ''
as $function$
  select * from private.get_historical_match_detail(p_match_id);
$function$;

revoke all on function public.get_historical_match_detail(uuid)
  from public, anon;
grant execute on function public.get_historical_match_detail(uuid)
  to authenticated, service_role;
