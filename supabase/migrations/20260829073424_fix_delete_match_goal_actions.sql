begin;

-- `match_sport_goal_actions` references match participants with ON DELETE
-- RESTRICT. The goal-action table was introduced after the delete_match RPC,
-- so deleting participants first aborts the whole transaction. Remove the
-- durable goal facts before their referenced participants.
create or replace function public.delete_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_kickoff_at timestamptz;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select match.kickoff_at
  into v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if v_kickoff_at is null or now() >= v_kickoff_at + interval '24 hours' then
    raise exception 'Un match ne peut être supprimé que jusqu’à 24 heures après son coup d’envoi.'
      using errcode = '22023';
  end if;

  perform set_config('as_grinta.allow_postmatch_composition_write', 'on', true);
  perform set_config('as_grinta.allow_match_delete', 'on', true);

  -- Must happen before deleting match_sport_participants because scorer and
  -- assist participant foreign keys are intentionally ON DELETE RESTRICT.
  delete from public.match_sport_goal_actions where match_id = p_match_id;

  delete from public.match_live_events where match_id = p_match_id;
  delete from public.match_live_sessions where match_id = p_match_id;
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
  return true;
end;
$function$;

alter function public.delete_match(uuid) owner to postgres;
revoke all on function public.delete_match(uuid) from public, anon;
grant execute on function public.delete_match(uuid) to authenticated, service_role;

comment on function public.delete_match(uuid) is
  'Suppression complète d''un match par le staff jusqu''à 24 heures après son coup d''envoi. Efface le match et toutes ses données dépendantes, y compris les faits de buts.';

commit;
