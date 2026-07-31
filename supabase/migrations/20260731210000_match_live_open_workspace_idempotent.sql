begin;

-- Deux problèmes trouvés en testant le Tableau Blanc :
-- 1. Avant qu'une session live existe, le bundle renvoyé au client n'a
--    jamais de "lineup", donc l'écran de préparation restait bloqué sur
--    "Composition indisponible" et le bouton "Démarrer le match" (le seul
--    endroit qui ouvrait la session) ne pouvait jamais s'afficher. Le client
--    ouvre maintenant la session automatiquement à l'arrivée sur l'écran.
-- 2. Une fois ce changement fait, "Démarrer le match" rouvre la session une
--    deuxième fois (pour transmettre le temps de jeu saisi) : la version
--    précédente recopiait alors systématiquement la composition publiée,
--    effaçant les corrections en glisser-déposer faites entre-temps. On ne
--    recopie plus la publication qu'à la toute première ouverture ; un
--    second appel pendant que l'état est encore "not_started" se contente de
--    mettre à jour le temps de jeu.
create or replace function private.open_match_live_workspace(
  p_match_id uuid,
  p_planned_duration_minutes integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_match_status text;
  v_default_duration integer;
  v_existing_state public.match_live_state;
  v_publication_snapshot jsonb;
  v_formation text;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select match.status, match.planned_duration_minutes
  into v_match_status, v_default_duration
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' then
    raise exception 'Live tracking is only available for upcoming matches'
      using errcode = '22023';
  end if;

  select session.state into v_existing_state
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if found then
    if v_existing_state <> 'not_started' then
      -- Already started: just return current state, no reset.
      return private.match_live_snapshot(p_match_id);
    end if;

    -- Already open and still not started: only refresh the planned
    -- duration, never touch match_composition_entries again (that would
    -- discard any pre-kickoff drag-and-drop corrections).
    update public.match_live_sessions
    set planned_duration_minutes =
          greatest(1, least(200, coalesce(p_planned_duration_minutes, planned_duration_minutes))),
        updated_by = v_actor,
        updated_at = now()
    where match_id = p_match_id;

    return private.match_live_snapshot(p_match_id);
  end if;

  select publication.snapshot, publication.formation_code
  into v_publication_snapshot, v_formation
  from public.match_composition_publications publication
  where publication.match_id = p_match_id
  order by publication.version desc
  limit 1;

  if v_publication_snapshot is null then
    raise exception 'No published composition to start from' using errcode = '22023';
  end if;

  insert into public.match_live_sessions (
    match_id, state, planned_duration_minutes, updated_by
  ) values (
    p_match_id, 'not_started',
    greatest(1, least(200, coalesce(p_planned_duration_minutes, v_default_duration))),
    v_actor
  );

  delete from public.match_composition_entries where match_id = p_match_id;
  insert into public.match_composition_entries (
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select
    p_match_id,
    (entry ->> 'participant_id')::uuid,
    (entry ->> 'zone')::public.sport_composition_zone,
    case when entry ->> 'x' is null then null else (entry ->> 'x')::numeric end,
    case when entry ->> 'y' is null then null else (entry ->> 'y')::numeric end,
    entry ->> 'slot_label',
    coalesce((entry ->> 'sort_order')::integer, 0)
  from jsonb_array_elements(v_publication_snapshot -> 'entries') entry
  where (entry ->> 'zone') in ('field', 'bench', 'not_selected');

  update public.match_compositions
  set formation_code = v_formation,
      last_modified_at = now(),
      last_modified_by = v_actor
  where match_id = p_match_id;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

commit;
