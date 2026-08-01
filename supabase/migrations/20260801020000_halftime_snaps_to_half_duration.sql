-- « Mi-temps » cale le chrono sur la moitié du temps de jeu.
--
-- Le coach saisit le temps de jeu avant le coup d'envoi. Jusqu'ici, la
-- mi-temps figeait le chronomètre sur le temps réellement écoulé, qui ne
-- tombe jamais juste. Elle positionne désormais le chrono exactement sur
-- « temps de jeu / 2 » et met en pause : la reprise repart donc de la
-- bonne minute pour la seconde période.

create or replace function private.set_match_live_clock_state(
  p_match_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_elapsed integer;
  v_running_since timestamptz;
  v_half smallint;
  v_planned integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  if p_action not in ('pause', 'resume', 'halftime', 'resume_second_half') then
    raise exception 'Invalid clock action' using errcode = '22023';
  end if;

  select session.state, session.elapsed_seconds, session.running_since,
         session.half, session.planned_duration_minutes
  into v_state, v_elapsed, v_running_since, v_half, v_planned
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    raise exception 'No live session for this match' using errcode = 'P0002';
  end if;

  if p_action = 'pause' then
    if v_state <> 'running' then
      raise exception 'The clock is not running' using errcode = '22023';
    end if;
    update public.match_live_sessions
    set state = 'paused',
        elapsed_seconds = v_elapsed + greatest(0, extract(epoch from now() - v_running_since))::integer,
        running_since = null,
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_action = 'resume' then
    if v_state <> 'paused' then
      raise exception 'The clock is not paused' using errcode = '22023';
    end if;
    update public.match_live_sessions
    set state = 'running',
        running_since = now(),
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_action = 'halftime' then
    if v_state not in ('running', 'paused') or v_half <> 1 then
      raise exception 'Half-time is only available during the first half' using errcode = '22023';
    end if;
    -- La mi-temps cale le chrono sur la moitié du temps de jeu saisi par
    -- le coach, quel que soit le temps réellement écoulé, et met en pause.
    update public.match_live_sessions
    set state = 'halftime',
        elapsed_seconds = greatest(0, coalesce(v_planned, 0)) * 30,
        running_since = null,
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_action = 'resume_second_half' then
    if v_state <> 'halftime' then
      raise exception 'The match is not at half-time' using errcode = '22023';
    end if;
    update public.match_live_sessions
    set state = 'running',
        half = 2,
        running_since = now(),
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  end if;

  return private.match_live_snapshot(p_match_id);
end;
$function$;
