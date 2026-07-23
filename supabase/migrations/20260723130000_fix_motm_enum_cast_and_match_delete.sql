-- Correctifs :
-- 1) ensure_match_motm_election / admin_restart_match_motm_vote : le CASE
--    renvoyant des littéraux texte ('draft'/'cancelled'/'open') doit être
--    casté explicitement vers l'enum public.sport_vote_state avant insertion
--    (Postgres n'applique pas la conversion implicite pour un CASE dans un
--    INSERT ... VALUES). Sans ce cast, toute finalisation de match échouait.
-- 2) delete_match : purge tout le sous-arbre « gestion sportive » (contraintes
--    ON DELETE RESTRICT) avant de supprimer le match, sinon la suppression
--    d'un match sportif est impossible.

create or replace function private.ensure_match_motm_election(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_exists boolean;
  v_kickoff timestamptz;
  v_has_source boolean;
  v_has_ballot boolean;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_version integer;
  v_state public.sport_vote_state;
begin
  select true into v_exists
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;
  if v_exists then
    return;
  end if;

  select match.kickoff_at into v_kickoff
  from public.matches match
  where match.id = p_match_id;
  if v_kickoff is null then
    return;
  end if;

  v_has_source := exists (
    select 1 from public.match_composition_publications pub
    where pub.match_id = p_match_id
  ) or exists (
    select 1 from public.match_sport_finalization_versions version
    where version.match_id = p_match_id
  );
  if not v_has_source then
    return;
  end if;

  v_opens_at := private.match_motm_opens_at(p_match_id);
  v_closes_at := v_kickoff + interval '24 hours';
  v_version := private.match_motm_anchor_version(p_match_id);
  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  v_state := (case when v_has_ballot then 'draft' else 'cancelled' end)::public.sport_vote_state;

  insert into public.match_sport_motm_elections (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    v_state,
    case when v_has_ballot then v_opens_at else null end,
    case when v_has_ballot then v_closes_at else null end,
    null, 0, 0, now(), now()
  )
  on conflict (match_id) do nothing;

  update public.match_sport_workflows
  set vote_state = v_state,
      updated_at = now()
  where match_id = p_match_id;
end;
$function$;

create or replace function private.admin_restart_match_motm_vote(
  p_match_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_has_ballot boolean;
  v_version integer;
  v_state public.sport_vote_state;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.matches match where match.id = p_match_id) then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  v_version := private.match_motm_anchor_version(p_match_id);
  v_state := (case when v_has_ballot then 'open' else 'cancelled' end)::public.sport_vote_state;

  insert into public.match_sport_motm_elections as election (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    v_state,
    case when v_has_ballot then now() else null end,
    case when v_has_ballot then now() + interval '24 hours' else null end,
    null, 0, 0, now(), now()
  )
  on conflict (match_id) do update
  set finalization_version = excluded.finalization_version,
      state = excluded.state,
      opens_at = excluded.opens_at,
      closes_at = excluded.closes_at,
      closed_at = null,
      total_votes = 0,
      max_votes = 0,
      updated_at = now();

  update public.match_sport_workflows
  set vote_state = v_state, updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'restart_motm_vote', v_actor, v_reason,
    jsonb_build_object('anchor_version', v_version, 'state', v_state)
  );

  return jsonb_build_object('match_id', p_match_id, 'state', v_state);
end;
$function$;

create or replace function public.delete_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  -- Purge du sous-arbre « gestion sportive » (contraintes RESTRICT), des
  -- enfants vers les parents, avant la suppression du match.
  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;
  delete from public.match_sport_motm_elections where match_id = p_match_id;
  delete from public.match_composition_entries where match_id = p_match_id;
  delete from public.match_composition_publications where match_id = p_match_id;
  delete from public.match_compositions where match_id = p_match_id;
  delete from public.match_sport_participant_events where match_id = p_match_id;
  delete from public.sport_availability_notification_events where match_id = p_match_id;
  delete from public.match_sport_finalization_versions where match_id = p_match_id;
  delete from public.match_sport_finalizations where match_id = p_match_id;
  delete from public.match_sport_participants where match_id = p_match_id;
  delete from public.match_sport_workflows where match_id = p_match_id;
  delete from public.match_attendance where match_id = p_match_id;
  delete from public.match_player_stats where match_id = p_match_id;
  delete from public.match_predictions where match_id = p_match_id;
  delete from public.match_odds where match_id = p_match_id;
  delete from public.push_delivery_log where match_id = p_match_id;
  delete from public.push_notification_log where match_id = p_match_id;

  delete from public.matches where id = p_match_id;
  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$function$;
