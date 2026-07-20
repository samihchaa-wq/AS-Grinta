-- Return the current vote state after the finalization trigger has opened or
-- cancelled the collective MOTM ballot. The immutable finalization snapshot is
-- still kept exactly as validated; this only enriches the RPC response.

create or replace function public.admin_finalize_match_sport_postgame(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_participants jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_vote_state public.sport_vote_state;
begin
  v_result := private.finalize_match_sport_postgame(
    p_match_id,
    p_score_as_grinta,
    p_score_adverse,
    p_participants,
    p_reason
  );

  select workflow.vote_state into v_vote_state
  from public.match_sport_workflows workflow
  where workflow.match_id = p_match_id;

  return v_result || jsonb_build_object('vote_state', v_vote_state);
end;
$function$;

revoke all on function public.admin_finalize_match_sport_postgame(
  uuid, integer, integer, jsonb, text
) from public, anon;
grant execute on function public.admin_finalize_match_sport_postgame(
  uuid, integer, integer, jsonb, text
) to authenticated, service_role;
