-- Final integration and release-readiness helpers for the optional sports module.
-- Additive, server-authoritative and inert while sports_management is disabled.

create or replace function private.list_admin_match_motm_votes()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'match_id', election.match_id,
      'opponent_name', opponent.name,
      'kickoff_at', match.kickoff_at,
      'score_as_grinta', match.score_as_grinta,
      'score_adverse', match.score_adverse,
      'state', election.state,
      'opens_at', election.opens_at,
      'closes_at', election.closes_at,
      'closed_at', election.closed_at,
      'finalization_version', election.finalization_version,
      'eligible_voter_count', eligible.count,
      'votes_received', votes.count,
      'candidate_count', candidates.count,
      'participation_rate', case
        when eligible.count = 0 then 0
        else round((votes.count::numeric * 100) / eligible.count, 1)
      end,
      'open_notification_sent', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_open'
      ),
      'reminder_notification_sent', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_reminder'
      ),
      'results_notification_sent', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_results'
      )
    ) order by coalesce(election.closes_at, match.kickoff_at) desc, election.match_id
  ), '[]'::jsonb)
  into v_result
  from public.match_sport_motm_elections election
  join public.matches match on match.id = election.match_id
  join public.opponents opponent on opponent.id = match.opponent_id
  cross join lateral (
    select count(distinct profile.id)::integer as count
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where participant.match_id = election.match_id
      and participant.final_presence_status = 'present'
      and profile.status = 'active'
  ) eligible
  cross join lateral (
    select count(*)::integer as count
    from public.match_sport_motm_votes vote
    where vote.match_id = election.match_id
      and vote.finalization_version = election.finalization_version
  ) votes
  cross join lateral (
    select count(*)::integer as count
    from public.match_sport_participants participant
    where participant.match_id = election.match_id
      and participant.final_presence_status = 'present'
  ) candidates;

  return v_result;
end;
$function$;

create or replace function private.get_admin_match_motm_dashboard(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  perform private.close_match_motm_election(p_match_id, true);

  select jsonb_build_object(
    'match_id', election.match_id,
    'opponent_name', opponent.name,
    'kickoff_at', match.kickoff_at,
    'score_as_grinta', match.score_as_grinta,
    'score_adverse', match.score_adverse,
    'state', election.state,
    'opens_at', election.opens_at,
    'closes_at', election.closes_at,
    'closed_at', election.closed_at,
    'finalization_version', election.finalization_version,
    'eligible_voter_count', eligible.count,
    'votes_received', votes.count,
    'candidate_count', candidates.count,
    'participation_rate', case
      when eligible.count = 0 then 0
      else round((votes.count::numeric * 100) / eligible.count, 1)
    end,
    'total_votes', case when election.state = 'closed' then election.total_votes else null end,
    'max_votes', case when election.state = 'closed' then election.max_votes else null end,
    'notifications', jsonb_build_object(
      'open', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_open'
      ),
      'reminder', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_reminder'
      ),
      'results', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_results'
      )
    ),
    'winners', case when election.state = 'closed' then coalesce((
      select jsonb_agg(jsonb_build_object(
        'participant_id', participant.id,
        'display_name', case
          when guest.id is not null then
            btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
          else btrim(concat_ws(' ', player.first_name, player.last_name))
        end,
        'is_guest', guest.id is not null,
        'votes_count', result.votes_count
      ) order by lower(coalesce(player.first_name, guest.first_name)), participant.id)
      from public.match_sport_motm_results result
      join public.match_sport_participants participant
        on participant.id = result.participant_id
       and participant.match_id = result.match_id
      left join public.season_players player on player.id = participant.season_player_id
      left join public.guest_players guest on guest.id = participant.guest_player_id
      where result.match_id = election.match_id and result.is_winner
    ), '[]'::jsonb) else '[]'::jsonb end,
    'actions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'action', audit.action,
        'reason', audit.reason,
        'created_at', audit.created_at,
        'actor_name', btrim(concat_ws(' ', profile.first_name, profile.last_name)),
        'metadata', audit.metadata
      ) order by audit.created_at desc, audit.id desc)
      from private.sport_admin_audit_log audit
      left join public.profiles profile on profile.id = audit.actor_profile_id
      where audit.match_id = election.match_id
        and audit.action in (
          'open_motm_vote',
          'reset_motm_vote_after_correction',
          'restart_motm_vote',
          'cancel_motm_vote',
          'close_motm_vote_early'
        )
    ), '[]'::jsonb)
  ) into v_result
  from public.match_sport_motm_elections election
  join public.matches match on match.id = election.match_id
  join public.opponents opponent on opponent.id = match.opponent_id
  cross join lateral (
    select count(distinct profile.id)::integer as count
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where participant.match_id = election.match_id
      and participant.final_presence_status = 'present'
      and profile.status = 'active'
  ) eligible
  cross join lateral (
    select count(*)::integer as count
    from public.match_sport_motm_votes vote
    where vote.match_id = election.match_id
      and vote.finalization_version = election.finalization_version
  ) votes
  cross join lateral (
    select count(*)::integer as count
    from public.match_sport_participants participant
    where participant.match_id = election.match_id
      and participant.final_presence_status = 'present'
  ) candidates
  where election.match_id = p_match_id;

  if v_result is null then
    raise exception 'MOTM vote is unavailable' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

create or replace function private.admin_close_match_motm_vote_early(
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
  v_version integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is null then
    raise exception 'A reason is required' using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select election.finalization_version into v_version
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id and election.state = 'open'
  for update;
  if not found then
    raise exception 'Only an open MOTM vote can be closed early' using errcode = '22023';
  end if;

  if not private.close_match_motm_election(p_match_id, false) then
    raise exception 'MOTM vote could not be closed' using errcode = '22023';
  end if;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'close_motm_vote_early',
    v_actor,
    v_reason,
    jsonb_build_object('finalization_version', v_version)
  );

  return private.get_admin_match_motm_dashboard(p_match_id);
end;
$function$;

create or replace function private.get_match_sport_statistics_integrity(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', finalization.match_id,
    'finalization_version', finalization.version,
    'permanent_present_expected', expected.present_count,
    'attendance_rows', actual.attendance_count,
    'goals_expected', expected.goals_count,
    'goals_in_statistics', actual.goals_count,
    'clean_sheets_expected', expected.clean_sheet_count,
    'clean_sheets_in_statistics', actual.clean_sheet_count,
    'permanent_motm_expected', expected.motm_count,
    'motm_rows', actual.motm_count,
    'attendance_ok', expected.present_count = actual.attendance_count,
    'goals_ok', expected.goals_count = actual.goals_count,
    'clean_sheets_ok', expected.clean_sheet_count = actual.clean_sheet_count,
    'motm_ok', expected.motm_count = actual.motm_count,
    'all_ok', expected.present_count = actual.attendance_count
      and expected.goals_count = actual.goals_count
      and expected.clean_sheet_count = actual.clean_sheet_count
      and expected.motm_count = actual.motm_count
  ) into v_result
  from public.match_sport_finalizations finalization
  cross join lateral (
    select
      count(*) filter (
        where participant.final_presence_status = 'present'
          and participant.season_player_id is not null
      )::integer as present_count,
      coalesce(sum(participant.final_goals) filter (
        where participant.season_player_id is not null
      ), 0)::integer as goals_count,
      count(*) filter (
        where participant.season_player_id is not null
          and participant.final_clean_sheet
      )::integer as clean_sheet_count,
      (
        select count(*)::integer
        from public.match_sport_motm_results result
        join public.match_sport_participants winner
          on winner.id = result.participant_id and winner.match_id = result.match_id
        where result.match_id = finalization.match_id
          and result.is_winner
          and winner.season_player_id is not null
      ) as motm_count
    from public.match_sport_participants participant
    where participant.match_id = finalization.match_id
  ) expected
  cross join lateral (
    select
      (select count(*)::integer from public.match_attendance attendance
       where attendance.match_id = finalization.match_id) as attendance_count,
      (select coalesce(sum(stats.goals), 0)::integer from public.match_player_stats stats
       where stats.match_id = finalization.match_id) as goals_count,
      (select count(*)::integer from public.match_player_stats stats
       where stats.match_id = finalization.match_id and stats.clean_sheet) as clean_sheet_count,
      (select count(*)::integer from public.match_man_of_match motm
       where motm.match_id = finalization.match_id) as motm_count
  ) actual
  where finalization.match_id = p_match_id;

  if v_result is null then
    raise exception 'Final attendance must be validated first' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

create or replace function public.admin_list_match_motm_votes()
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.list_admin_match_motm_votes(); $function$;

create or replace function public.admin_get_match_motm_dashboard(p_match_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $function$ select private.get_admin_match_motm_dashboard(p_match_id); $function$;

create or replace function public.admin_close_match_motm_vote_early(
  p_match_id uuid,
  p_reason text
)
returns jsonb language sql security invoker set search_path = ''
as $function$ select private.admin_close_match_motm_vote_early(p_match_id, p_reason); $function$;

create or replace function public.admin_get_match_sport_statistics_integrity(p_match_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.get_match_sport_statistics_integrity(p_match_id); $function$;

revoke all on function private.list_admin_match_motm_votes() from public, anon, authenticated;
revoke all on function private.get_admin_match_motm_dashboard(uuid) from public, anon, authenticated;
revoke all on function private.admin_close_match_motm_vote_early(uuid, text) from public, anon, authenticated;
revoke all on function private.get_match_sport_statistics_integrity(uuid) from public, anon, authenticated;

grant execute on function private.list_admin_match_motm_votes() to authenticated, service_role;
grant execute on function private.get_admin_match_motm_dashboard(uuid) to authenticated, service_role;
grant execute on function private.admin_close_match_motm_vote_early(uuid, text) to authenticated, service_role;
grant execute on function private.get_match_sport_statistics_integrity(uuid) to authenticated, service_role;

revoke all on function public.admin_list_match_motm_votes() from public, anon;
revoke all on function public.admin_get_match_motm_dashboard(uuid) from public, anon;
revoke all on function public.admin_close_match_motm_vote_early(uuid, text) from public, anon;
revoke all on function public.admin_get_match_sport_statistics_integrity(uuid) from public, anon;

grant execute on function public.admin_list_match_motm_votes() to authenticated, service_role;
grant execute on function public.admin_get_match_motm_dashboard(uuid) to authenticated, service_role;
grant execute on function public.admin_close_match_motm_vote_early(uuid, text) to authenticated, service_role;
grant execute on function public.admin_get_match_sport_statistics_integrity(uuid) to authenticated, service_role;
