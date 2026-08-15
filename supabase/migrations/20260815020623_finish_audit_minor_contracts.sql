begin;

-- A match without a kickoff time cannot participate safely in the prediction,
-- weather or lifecycle rules. All current creation/update RPCs already require
-- a time, so make the table enforce the same contract.
do $block$
begin
  if exists (
    select 1
    from public.matches
    where match_time is null
  ) then
    raise exception 'Cannot make matches.match_time NOT NULL while null values remain';
  end if;
end;
$block$;

alter table public.matches
  alter column match_time set not null;

comment on column public.matches.match_time is
  'Local Europe/Paris kickoff time. Required; kickoff_at is synchronized from match_date + match_time.';

-- The previous RPC name suggested that reading an internal composition was an
-- administrator-only action even though its contract intentionally allows any
-- active profile. Introduce a correctly named canonical read RPC.
create or replace function public.get_internal_composition(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_match_type text;
  v_team1_name text;
  v_team2_name text;
  v_entries jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select match_type into v_match_type
  from public.matches
  where id = p_match_id;

  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;

  select comp.team1_name, comp.team2_name
  into v_team1_name, v_team2_name
  from public.match_internal_compositions comp
  where comp.match_id = p_match_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', participant.id,
      'season_player_id', participant.season_player_id,
      'guest_player_id', participant.guest_player_id,
      'display_name', coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ),
      'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
      'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
      'is_guest', participant.guest_player_id is not null,
      'team_no', entry.team_no,
      'sort_order', coalesce(entry.sort_order, 999)
    )
    order by coalesce(entry.sort_order, 999),
      coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      )
  ), '[]'::jsonb)
  into v_entries
  from public.match_sport_participants participant
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  left join public.match_internal_composition_entries entry
    on entry.match_id = p_match_id
   and entry.participant_id = participant.id
  where participant.match_id = p_match_id
    and participant.convocation_status = 'convoked';

  return jsonb_build_object(
    'match_id', p_match_id,
    'team1_name', coalesce(v_team1_name, 'Équipe 1'),
    'team2_name', coalesce(v_team2_name, 'Équipe 2'),
    'entries', v_entries
  );
end;
$function$;

revoke all on function public.get_internal_composition(uuid)
  from public, anon;
grant execute on function public.get_internal_composition(uuid)
  to authenticated, service_role;

comment on function public.get_internal_composition(uuid) is
  'Returns the internal-team composition to any active authenticated profile.';

-- Keep the historical name as a compatibility alias for already-deployed web
-- clients. It carries no privileges itself and delegates to the canonical RPC.
create or replace function public.admin_get_internal_composition(p_match_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  select public.get_internal_composition(p_match_id);
$function$;

revoke all on function public.admin_get_internal_composition(uuid)
  from public, anon;
grant execute on function public.admin_get_internal_composition(uuid)
  to authenticated, service_role;

comment on function public.admin_get_internal_composition(uuid) is
  'Compatibility alias. New clients must call public.get_internal_composition(uuid).';

-- CREATE OR REPLACE can accidentally restore implicit EXECUTE privileges when
-- defaults drift. Reassert the application-owned function defaults so future
-- postgres-owned RPCs remain deny-by-default until explicitly granted.
alter default privileges for role postgres
  revoke execute on functions from public;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated;
alter default privileges for role postgres in schema public
  grant execute on functions to service_role;

commit;
