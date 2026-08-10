create or replace function private.match_motm_candidate_participants(p_match_id uuid)
returns table (participant_id uuid)
language sql
stable
security definer
set search_path = ''
as $function$
  select participant.id
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (
      participant.final_presence_status = 'present'
      or exists (
        select 1 from public.match_composition_entries entry
        where entry.match_id = p_match_id
          and entry.participant_id = participant.id
          and entry.zone in ('field', 'bench')
      )
    );
$function$;

revoke all on function private.match_motm_candidate_participants(uuid)
  from public, anon, authenticated;;
