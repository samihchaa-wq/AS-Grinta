-- Éligibilité HDM : jusqu'ici, dès qu'une compo était publiée, seuls les
-- joueurs de la compo publiée pouvaient voter / être votés. Un joueur
-- réellement présent (a fortiori buteur) ajouté après la publication était
-- exclu du scrutin.
--
-- Nouvelle règle (purement additive) : est candidat/votant quiconque est
-- marqué présent OU figure dans la compo publiée (terrain ou banc). La liste
-- étant recalculée en direct, l'effet est immédiat sur les scrutins ouverts.

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
  from public, anon, authenticated;
