-- Renforce la synchronisation Effectif / Sur papier / Sur terrain lorsque le
-- nombre de convoqués reste identique mais que leur identité change.
create or replace function private.internal_composition_visual_is_complete(
  p_match_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_expected integer;
  v_stored integer;
  v_team1_count integer;
  v_team2_count integer;
  v_team1_field integer;
  v_team2_field integer;
  v_team1_bench integer;
  v_team2_bench integer;
  v_team1_formation text;
  v_team2_formation text;
begin
  select count(*)::integer
  into v_expected
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.convocation_status = 'convoked';

  if v_expected = 0 then
    return false;
  end if;

  select composition.team1_formation, composition.team2_formation
  into v_team1_formation, v_team2_formation
  from public.match_internal_compositions composition
  where composition.match_id = p_match_id;

  if v_team1_formation is null or v_team2_formation is null then
    return false;
  end if;

  select
    count(*)::integer,
    count(*) filter (where entry.team_no = 1)::integer,
    count(*) filter (where entry.team_no = 2)::integer,
    count(*) filter (
      where entry.team_no = 1 and entry.zone = 'field'
    )::integer,
    count(*) filter (
      where entry.team_no = 2 and entry.zone = 'field'
    )::integer,
    count(*) filter (
      where entry.team_no = 1 and entry.zone = 'bench'
    )::integer,
    count(*) filter (
      where entry.team_no = 2 and entry.zone = 'bench'
    )::integer
  into
    v_stored,
    v_team1_count,
    v_team2_count,
    v_team1_field,
    v_team2_field,
    v_team1_bench,
    v_team2_bench
  from public.match_internal_composition_entries entry
  where entry.match_id = p_match_id;

  if v_stored <> v_expected
     or exists (
       select 1
       from public.match_internal_composition_entries entry
       where entry.match_id = p_match_id
         and not exists (
           select 1
           from public.match_sport_participants participant
           where participant.id = entry.participant_id
             and participant.match_id = p_match_id
             and participant.convocation_status = 'convoked'
         )
     )
     or exists (
       select 1
       from public.match_sport_participants participant
       where participant.match_id = p_match_id
         and participant.convocation_status = 'convoked'
         and not exists (
           select 1
           from public.match_internal_composition_entries entry
           where entry.match_id = p_match_id
             and entry.participant_id = participant.id
         )
     )
     or v_team1_count = 0
     or v_team2_count = 0
     or v_team1_field <> least(v_team1_count, 11)
     or v_team2_field <> least(v_team2_count, 11)
     or v_team1_bench <> greatest(v_team1_count - 11, 0)
     or v_team2_bench <> greatest(v_team2_count - 11, 0)
     or v_team1_formation <> private.internal_default_formation_code(v_team1_count)
     or v_team2_formation <> private.internal_default_formation_code(v_team2_count)
     or exists (
       select 1
       from public.match_internal_composition_entries entry
       where entry.match_id = p_match_id
         and (
           entry.team_no is null
           or entry.zone = 'available'
           or (
             entry.zone = 'field'
             and (
               entry.x is null
               or entry.y is null
               or entry.slot_label is null
             )
           )
         )
     )
     or exists (
       select 1
       from public.match_internal_composition_entries entry
       where entry.match_id = p_match_id
         and entry.zone = 'field'
       group by entry.team_no, entry.slot_label
       having count(*) > 1
     )
     or exists (
       select 1
       from public.match_internal_composition_entries entry
       where entry.match_id = p_match_id
         and entry.zone = 'field'
         and (
           (entry.team_no = 1 and not (
             entry.slot_label = any(
               private.internal_v4_formation_slots(v_team1_formation)
             )
           ))
           or
           (entry.team_no = 2 and not (
             entry.slot_label = any(
               private.internal_v4_formation_slots(v_team2_formation)
             )
           ))
         )
     ) then
    return false;
  end if;

  return true;
end;
$function$;

revoke all on function private.internal_composition_visual_is_complete(uuid)
  from public, anon, authenticated;
grant execute on function private.internal_composition_visual_is_complete(uuid)
  to service_role;
