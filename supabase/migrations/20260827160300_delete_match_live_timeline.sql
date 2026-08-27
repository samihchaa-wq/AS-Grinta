begin;

-- Supprimer les « Faits du match » d'un Live mal rempli.
--
-- Avant la validation du compte rendu, le coach peut déjà tout reprendre :
-- corriger un but, retirer un événement, ou relancer la session. Après la
-- validation, la chronologie était figée et s'affichait obligatoirement, même
-- quand elle contredisait la feuille de match corrigée.
--
-- Cette action d'administration efface la chronologie, et rien d'autre : le
-- score, les statistiques, la composition publiée et le vote Homme du match
-- restent intacts. Le bloc « Faits du match » disparaît simplement de la fiche.

create or replace function private.delete_match_live_timeline(
  p_match_id uuid,
  p_reason text default null::text
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_exported boolean;
  v_deleted integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select session.exported
  into v_exported
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    raise exception 'No live session for this match' using errcode = 'P0002';
  end if;

  -- Tant que le compte rendu n'est pas publié, la reprise normale reste la
  -- correction ou la relance de la session : on ne double pas ce chemin.
  if not coalesce(v_exported, false) then
    raise exception 'Restart the live session instead of deleting its timeline'
      using errcode = '22023';
  end if;

  with removed as (
    delete from public.match_live_events
    where match_id = p_match_id
    returning 1
  )
  select count(*)::integer into v_deleted from removed;

  update public.match_live_sessions
  set updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'delete_match_live_timeline',
    v_actor,
    v_reason,
    jsonb_build_object('deleted_events', v_deleted)
  );

  return v_deleted;
end;
$function$;

alter function private.delete_match_live_timeline(uuid, text) owner to postgres;
revoke all on function private.delete_match_live_timeline(uuid, text)
  from public, anon, authenticated;
grant execute on function private.delete_match_live_timeline(uuid, text)
  to service_role;

create or replace function public.admin_delete_match_live_timeline(
  p_match_id uuid,
  p_reason text default null::text
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.delete_match_live_timeline(p_match_id, p_reason);
end;
$function$;

alter function public.admin_delete_match_live_timeline(uuid, text) owner to postgres;
revoke all on function public.admin_delete_match_live_timeline(uuid, text)
  from public, anon;
grant execute on function public.admin_delete_match_live_timeline(uuid, text)
  to authenticated, service_role;

comment on function public.admin_delete_match_live_timeline(uuid, text) is
  'Efface la chronologie Live d''un match déjà exporté. Ne touche ni au score, ni aux statistiques, ni à la composition, ni au vote Homme du match.';

commit;
