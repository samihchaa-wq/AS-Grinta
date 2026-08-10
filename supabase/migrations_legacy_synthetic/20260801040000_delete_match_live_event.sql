-- Retirer un buteur ou un couple de remplacements saisi par erreur.
--
-- Le « − » du score décrémentait le compteur sans supprimer l'événement :
-- le buteur restait donc listé dans « Buteurs » alors que son but avait
-- disparu du score. Il n'existait par ailleurs aucun moyen d'annuler un
-- remplacement mal saisi.
--
-- Cette RPC supprime un événement précis. Pour un but, elle corrige aussi
-- le score en conséquence. Pour un remplacement, elle retire uniquement la
-- ligne du journal (et donc le compteur de fois sur le banc) : les joueurs
-- ne sont pas replacés automatiquement sur le terrain, car d'autres
-- changements ont pu intervenir depuis. Le coach ajuste les positions en
-- glisser-déposer s'il le souhaite.

create or replace function private.delete_match_live_event(
  p_match_id uuid,
  p_event_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_exported boolean;
  v_score_us integer;
  v_score_them integer;
  v_type text;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, session.exported,
         session.score_as_grinta, session.score_adverse
  into v_state, v_exported, v_score_us, v_score_them
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state not in ('running', 'paused', 'halftime', 'finished') then
    raise exception 'The match is not currently live' using errcode = '22023';
  end if;
  if coalesce(v_exported, false) then
    raise exception 'This match has already been exported' using errcode = '22023';
  end if;

  select event.event_type into v_type
  from public.match_live_events event
  where event.id = p_event_id and event.match_id = p_match_id
  for update;

  if not found then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;

  delete from public.match_live_events
  where id = p_event_id and match_id = p_match_id;

  if v_type = 'goal_us' then
    update public.match_live_sessions
    set score_as_grinta = greatest(0, v_score_us - 1),
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif v_type = 'goal_them' then
    update public.match_live_sessions
    set score_adverse = greatest(0, v_score_them - 1),
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  else
    update public.match_live_sessions
    set updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  end if;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function public.coach_delete_match_live_event(
  p_match_id uuid, p_event_id uuid
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.delete_match_live_event(p_match_id, p_event_id); $function$;

revoke execute on function private.delete_match_live_event(uuid, uuid) from public, anon;
revoke execute on function public.coach_delete_match_live_event(uuid, uuid) from public, anon;

grant execute on function private.delete_match_live_event(uuid, uuid) to authenticated, service_role;
grant execute on function public.coach_delete_match_live_event(uuid, uuid) to authenticated, service_role;
