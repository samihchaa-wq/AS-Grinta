-- « Recommencer » : remettre un suivi en direct à zéro.
--
-- Le coach peut lancer le match par erreur, ou vouloir tout reprendre après
-- une saisie ratée. Jusqu'ici la seule issue était de terminer le match puis
-- de le publier, ce qui figeait des données fausses.
--
-- Cette RPC efface la totalité de ce qui a été saisi en direct — buts,
-- remplacements, chronomètre, score — et replace la composition telle qu'elle
-- était au coup d'envoi. La session repasse à « not_started » : on retrouve
-- l'écran de préparation, où le temps de jeu et la composition sont encore
-- modifiables avant de relancer.
--
-- La composition est restaurée en rejouant les remplacements à l'envers, du
-- plus récent au plus ancien. C'est la seule méthode exacte : le zonage seul
-- ne suffit pas, car un titulaire qui revient sur le terrain a besoin de sa
-- position, et la contrainte de la table exige des coordonnées non nulles sur
-- le terrain et nulles sur le banc. Rejouer à l'envers rend au sortant la
-- place exacte qu'occupait son remplaçant, y compris quand plusieurs
-- changements se sont enchaînés sur le même poste.
--
-- Un match déjà exporté n'est jamais concerné : son compte rendu est publié et
-- ses statistiques comptent pour la saison.

create or replace function private.restart_match_live_session(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_state public.match_live_state;
  v_exported boolean;
  v_events integer;
  v_substitution record;
  v_x numeric(7,6);
  v_y numeric(7,6);
  v_slot_label text;
  v_in_order integer;
  v_out_order integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, session.exported
  into v_state, v_exported
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    raise exception 'No live session for this match' using errcode = 'P0002';
  end if;
  if v_exported then
    raise exception 'This match has already been exported' using errcode = '22023';
  end if;
  if v_state = 'not_started' then
    raise exception 'The match has not been started yet' using errcode = '22023';
  end if;

  select count(*) into v_events
  from public.match_live_events
  where match_id = p_match_id;

  -- On défait les remplacements du plus récent au plus ancien : à chaque
  -- étape, l'entrant est forcément encore sur le terrain, et il rend sa place
  -- exacte au sortant.
  for v_substitution in
    select event.player_in_participant_id as player_in,
           event.player_out_participant_id as player_out
    from public.match_live_events event
    where event.match_id = p_match_id
      and event.event_type = 'substitution'
    order by event.created_at desc, event.id desc
  loop
    select entry.x, entry.y, entry.slot_label, entry.sort_order
    into v_x, v_y, v_slot_label, v_in_order
    from public.match_composition_entries entry
    where entry.match_id = p_match_id
      and entry.participant_id = v_substitution.player_in
      and entry.zone = 'field';

    -- L'entrant a déjà quitté le terrain autrement : rien de fiable à rendre,
    -- on laisse la ligne en l'état plutôt que de fabriquer une position.
    continue when not found;

    select entry.sort_order into v_out_order
    from public.match_composition_entries entry
    where entry.match_id = p_match_id
      and entry.participant_id = v_substitution.player_out;

    update public.match_composition_entries
    set zone = 'bench',
        x = null,
        y = null,
        slot_label = null,
        sort_order = coalesce(v_out_order, sort_order)
    where match_id = p_match_id
      and participant_id = v_substitution.player_in;

    update public.match_composition_entries
    set zone = 'field',
        x = v_x,
        y = v_y,
        slot_label = v_slot_label,
        sort_order = v_in_order
    where match_id = p_match_id
      and participant_id = v_substitution.player_out;
  end loop;

  delete from public.match_live_events where match_id = p_match_id;

  update public.match_live_sessions
  set state = 'not_started',
      half = 1,
      elapsed_seconds = 0,
      running_since = null,
      score_as_grinta = 0,
      score_adverse = 0,
      started_at = null,
      finished_at = null,
      starting_composition_version = null,
      starting_lineup_snapshot = null,
      lineup_revision = lineup_revision + 1,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'restart_match_live', v_actor, v_reason,
    jsonb_build_object('deleted_events', v_events, 'previous_state', v_state)
  );

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function public.coach_restart_match_live_session(
  p_match_id uuid, p_reason text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.restart_match_live_session(p_match_id, p_reason); $function$;

revoke execute on function private.restart_match_live_session(uuid, text)
  from public, anon;
grant execute on function private.restart_match_live_session(uuid, text)
  to authenticated, service_role;

revoke execute on function public.coach_restart_match_live_session(uuid, text)
  from public, anon;
grant execute on function public.coach_restart_match_live_session(uuid, text)
  to authenticated, service_role;

comment on function public.coach_restart_match_live_session(uuid, text) is
  'Wipes a non-exported live session (events, clock, score) and restores the kickoff lineup.';
