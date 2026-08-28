begin;

-- Expose les passes décisives sur la composition publiée d'un match terminé.
-- Le calcul/statut reste porté par match_sport_participants.final_assists :
-- cette couche ne fait qu'enrichir le JSON déjà produit par l'implémentation
-- privée, exactement comme les buts sont exposés aujourd'hui.
create or replace function public.get_published_match_composition(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_entries jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  v_result := private.get_published_match_composition(p_match_id);
  if v_result is null then
    return null;
  end if;

  select coalesce(
    jsonb_agg(
      entry.value || jsonb_build_object(
        'assists', coalesce(participant.final_assists, 0)
      )
      order by entry.ordinality
    ),
    '[]'::jsonb
  )
  into v_entries
  from jsonb_array_elements(coalesce(v_result -> 'entries', '[]'::jsonb))
    with ordinality as entry(value, ordinality)
  left join public.match_sport_participants participant
    on participant.match_id = p_match_id
   and participant.id = (entry.value ->> 'participant_id')::uuid;

  return v_result || jsonb_build_object('entries', v_entries);
end;
$function$;

-- Conserver explicitement la frontière de sécurité de la RPC publique.
revoke execute on function public.get_published_match_composition(uuid)
  from public, anon;
grant execute on function public.get_published_match_composition(uuid)
  to authenticated, service_role;

commit;
