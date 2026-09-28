-- Retire l'exception ponctuelle du 28/09/2026 et restaure la frontière
-- standard T-15 pour Live, pronostics et verrou pré-match.
begin;

create or replace function private.match_prediction_closes_at(
  p_kickoff_at timestamptz
)
returns timestamptz
language sql
stable
strict
set search_path = ''
as $function$
  select p_kickoff_at - interval '15 minutes';
$function$;

comment on function private.match_prediction_closes_at(timestamptz) is
  'Frontière commune fermeture pronostics / ouverture Live / verrou pré-match : T-15.';

create or replace function public.admin_remove_match_guest(
  p_match_id uuid,
  p_participant_id uuid,
  p_reason text default null::text
)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  select match.status, match.kickoff_at
  into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if v_status = 'a_venir'
     and v_kickoff_at is not null
     and now() >= v_kickoff_at - interval '15 minutes' then
    raise exception 'L’effectif est figé depuis l’ouverture du Live.'
      using errcode = '22023';
  end if;

  return private.remove_match_guest(p_match_id, p_participant_id, p_reason);
end;
$function$;

commit;
