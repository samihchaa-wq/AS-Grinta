-- Corrige la désynchronisation entre le score exporté et la chronologie
-- « Faits du match ».
--
-- Chaque but enregistre le score cumulé au moment de sa saisie
-- (score_as_grinta_after / score_adverse_after), figé dans la ligne. Deux
-- chemins pouvaient laisser ces valeurs obsolètes :
--
--   1. Supprimer un but au milieu de la chronologie (delete_match_live_event)
--      décrémentait bien le score de la session, mais ne recalculait jamais
--      les scores déjà figés des buts suivants du même camp.
--   2. Le bouton « − » du score (adjust_match_live_score, delta -1)
--      décrémentait le compteur sans jamais supprimer ni ajuster
--      l'événement de but correspondant, laissant un but fantôme dans le
--      journal.
--
-- Les deux RPC sont réécrites pour que la chronologie reste toujours la
-- source de vérité du score.

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
  v_created_at timestamptz;
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

  select event.event_type, event.created_at into v_type, v_created_at
  from public.match_live_events event
  where event.id = p_event_id and event.match_id = p_match_id
  for update;

  if not found then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;

  delete from public.match_live_events
  where id = p_event_id and match_id = p_match_id;

  if v_type = 'goal_us' then
    -- Renuméroter les buts de notre équipe déjà saisis après celui-ci : leur
    -- score figé doit reculer d'une unité pour rester cohérent avec la
    -- suppression.
    update public.match_live_events
    set score_as_grinta_after = score_as_grinta_after - 1
    where match_id = p_match_id
      and event_type = 'goal_us'
      and created_at > v_created_at;

    update public.match_live_sessions
    set score_as_grinta = greatest(0, v_score_us - 1),
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif v_type = 'goal_them' then
    update public.match_live_events
    set score_adverse_after = score_adverse_after - 1
    where match_id = p_match_id
      and event_type = 'goal_them'
      and created_at > v_created_at;

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

create or replace function private.adjust_match_live_score(
  p_match_id uuid,
  p_team text,
  p_delta integer,
  p_scorer_participant_id uuid default null
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
  v_true_elapsed integer;
  v_minute integer;
  v_score_us integer;
  v_score_them integer;
  v_scorer_valid boolean;
  v_last_event_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  if p_team not in ('us', 'them') then
    raise exception 'Invalid team' using errcode = '22023';
  end if;
  if p_delta not in (-1, 1) then
    raise exception 'Score delta must be -1 or 1' using errcode = '22023';
  end if;

  select session.state, session.elapsed_seconds, session.running_since, session.half,
    session.score_as_grinta, session.score_adverse
  into v_state, v_elapsed, v_running_since, v_half, v_score_us, v_score_them
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state not in ('running', 'paused', 'halftime') then
    raise exception 'The match is not currently live' using errcode = '22023';
  end if;

  v_true_elapsed := v_elapsed + case
    when v_state = 'running'
    then greatest(0, extract(epoch from now() - v_running_since))::integer
    else 0
  end;
  v_minute := v_true_elapsed / 60 + 1;

  if p_team = 'us' and p_delta = 1 then
    -- Le buteur n'est plus obligatoire : le but est enregistré tout de
    -- suite et le coach l'attribue ensuite depuis la liste « Buteurs »,
    -- sans que rien ne lui saute au visage pendant le match.
    if p_scorer_participant_id is not null then
      select exists (
        select 1 from public.match_sport_participants participant
        where participant.id = p_scorer_participant_id and participant.match_id = p_match_id
      ) into v_scorer_valid;
      if not v_scorer_valid then
        raise exception 'Unknown scorer for this match' using errcode = '22023';
      end if;
    end if;

    update public.match_live_sessions
    set score_as_grinta = least(99, v_score_us + 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;

    insert into public.match_live_events (
      match_id, event_type, minute, half, scorer_participant_id,
      score_as_grinta_after, created_by
    ) values (
      p_match_id, 'goal_us', v_minute, v_half, p_scorer_participant_id,
      least(99, v_score_us + 1), v_actor
    );
  elsif p_team = 'us' and p_delta = -1 then
    -- Le « − » retire le dernier but de notre équipe déjà saisi, plutôt que
    -- de décrémenter un compteur déconnecté du journal : le buteur retiré
    -- disparaît alors correctement de « Faits du match ». Comme c'est le
    -- dernier but de ce type par construction (tri décroissant), aucun
    -- autre événement du même type n'a besoin d'être renuméroté.
    select event.id into v_last_event_id
    from public.match_live_events event
    where event.match_id = p_match_id and event.event_type = 'goal_us'
    order by event.created_at desc
    limit 1
    for update;

    if v_last_event_id is not null then
      delete from public.match_live_events where id = v_last_event_id;
    end if;

    update public.match_live_sessions
    set score_as_grinta = greatest(0, v_score_us - 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_team = 'them' and p_delta = 1 then
    update public.match_live_sessions
    set score_adverse = least(99, v_score_them + 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;

    insert into public.match_live_events (
      match_id, event_type, minute, half, score_adverse_after, created_by
    ) values (
      p_match_id, 'goal_them', v_minute, v_half, least(99, v_score_them + 1), v_actor
    );
  else
    select event.id into v_last_event_id
    from public.match_live_events event
    where event.match_id = p_match_id and event.event_type = 'goal_them'
    order by event.created_at desc
    limit 1
    for update;

    if v_last_event_id is not null then
      delete from public.match_live_events where id = v_last_event_id;
    end if;

    update public.match_live_sessions
    set score_adverse = greatest(0, v_score_them - 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  end if;

  return private.match_live_snapshot(p_match_id);
end;
$function$;
