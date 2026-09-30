-- Les tâches planifiées chaque minute ne réveillent plus toutes les applications
-- ouvertes quand elles n'ont rien à faire.
--
-- Le signal `shared_data_change_signals` est incrémenté par des déclencheurs
-- FOR EACH STATEMENT : ils s'exécutent même lorsqu'un UPDATE ne touche aucune
-- ligne. Or `finish_due_internal_matches` et
-- `process_sport_availability_notifications` lançaient leurs UPDATE à chaque
-- minute sans condition préalable. Résultat : trois révisions par minute, dont
-- une non sportive, et un rechargement complet de chaque client connecté à la
-- minute ronde, tous en même temps. C'est ce qui a saturé la base le
-- 28 septembre 2026 après le match.
--
-- Chaque UPDATE n'est désormais lancé que si au moins une ligne est concernée.
-- Les conditions sont strictement identiques à celles de l'UPDATE : le
-- comportement métier et les valeurs renvoyées ne changent pas.
begin;

create or replace function private.finish_due_internal_matches(
  p_now timestamp with time zone default now()
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_finished integer := 0;
begin
  if not exists (
    select 1
    from public.matches match
    where match.match_type = 'entre_nous'
      and match.status = 'a_venir'
      and match.kickoff_at is not null
      and match.kickoff_at
          + make_interval(
              mins => coalesce(match.planned_duration_minutes, 90) + 15
            ) <= p_now
  ) then
    return 0;
  end if;

  update public.matches match
  set status = 'termine',
      updated_at = p_now
  where match.match_type = 'entre_nous'
    and match.status = 'a_venir'
    and match.kickoff_at is not null
    and match.kickoff_at
        + make_interval(
            mins => coalesce(match.planned_duration_minutes, 90) + 15
          ) <= p_now;

  get diagnostics v_finished = row_count;
  return v_finished;
end;
$function$;

create or replace function private.process_sport_availability_notifications(
  p_now timestamp with time zone default now()
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row record;
  v_event_id bigint;
  v_opened integer := 0;
  v_closed integer := 0;
  v_created integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return jsonb_build_object(
      'opened_workflows', 0,
      'closed_workflows', 0,
      'notifications_created', 0
    );
  end if;

  if exists (
    select 1
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    where match.status = 'a_venir'
      and match.kickoff_at > p_now
      and workflow.availability_state = 'pending'
      and workflow.availability_opens_at <= p_now
  ) then
    with opened as (
      update public.match_sport_workflows workflow
      set availability_state = 'open',
          availability_opened_at = coalesce(workflow.availability_opened_at, p_now),
          updated_at = p_now
      from public.matches match
      where match.id = workflow.match_id
        and match.status = 'a_venir'
        and match.kickoff_at > p_now
        and workflow.availability_state = 'pending'
        and workflow.availability_opens_at <= p_now
      returning workflow.match_id
    )
    select count(*)::integer into v_opened from opened;
  end if;

  if exists (
    select 1
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    where workflow.availability_state <> 'closed'
      and (match.status <> 'a_venir' or match.kickoff_at <= p_now)
  ) then
    with closed as (
      update public.match_sport_workflows workflow
      set availability_state = 'closed', updated_at = p_now
      from public.matches match
      where match.id = workflow.match_id
        and workflow.availability_state <> 'closed'
        and (match.status <> 'a_venir' or match.kickoff_at <= p_now)
      returning workflow.match_id
    )
    select count(*)::integer into v_closed from closed;
  end if;

  if private.is_feature_enabled('notifications_paused') then
    return jsonb_build_object(
      'opened_workflows', v_opened,
      'closed_workflows', v_closed,
      'notifications_created', 0
    );
  end if;

  for v_row in
    select
      workflow.match_id,
      workflow.availability_opens_at,
      workflow.availability_opened_at,
      participant.id as participant_id,
      player.profile_id
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    join public.match_sport_participants participant on participant.match_id = workflow.match_id
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where workflow.availability_state = 'open'
      and match.status = 'a_venir'
      and match.kickoff_at > p_now
      and (participant.is_eligible or player.is_coach)
      and profile.status = 'active'
      and not private.is_player_unavailable_at(player.profile_id, match.kickoff_at)
      and not exists (
        select 1
        from public.sport_availability_notification_events event
        where event.participant_id = participant.id
          and event.kind = 'availability_open'
          and event.source = 'automatic'
          and event.scheduled_for = workflow.availability_opens_at
      )
      and not exists (
        select 1
        from public.push_notification_log log
        where log.match_id = workflow.match_id
          and log.kind = 'match_rescheduled_date'
          and workflow.availability_opened_at is not null
          and log.sent_at >= workflow.availability_opened_at
      )
    order by match.kickoff_at, participant.id
  loop
    v_event_id := private.create_sport_availability_notification(
      v_row.match_id,
      v_row.participant_id,
      v_row.profile_id,
      'availability_open',
      'automatic',
      v_row.availability_opens_at,
      null,
      null
    );
    if v_event_id is not null then
      v_created := v_created + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'opened_workflows', v_opened,
    'closed_workflows', v_closed,
    'notifications_created', v_created
  );
end;
$function$;

commit;
