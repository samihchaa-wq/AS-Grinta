-- Effectif : nombre de relances manuelles par joueur.
--
-- La cloche de relance de la colonne « Sans réponse » affiche combien de fois
-- un admin a relancé chaque joueur pour ce match. Le résumé ne donnait que la
-- date de la dernière relance : on y ajoute `manual_reminder_count`.
--
-- Changement additif : même signature, mêmes droits, mêmes champs existants.
-- Le corps reprend à l'identique la définition en production (dernière
-- version : 20260915093000_coach_is_a_regular_member.sql).

CREATE OR REPLACE FUNCTION private.get_sport_availability_reminder_summary(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', workflow.match_id,
    'availability_state', workflow.availability_state,
    'no_response_count', (
      select count(*)
      from public.match_sport_participants participant
      where participant.match_id = workflow.match_id
        and (
          participant.is_eligible
          or private.participant_is_coach(participant.season_player_id)
        )
        and participant.availability_status = 'no_response'
    ),
    'open_sent_count', (
      select count(*)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_open'
    ),
    'j3_sent_count', (
      select count(*)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_j3'
    ),
    'j1_sent_count', (
      select count(*)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_j1'
    ),
    'last_manual_at', (
      select max(event.requested_at)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_manual'
    ),
    'can_remind', workflow.availability_state = 'open'
      and match.status = 'a_venir'
      and match.kickoff_at > now(),
    'players', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'season_player_id', participant.season_player_id,
          'last_reminder_at', reminder.last_reminder_at,
          'manual_cooldown_until', reminder.last_manual_at + interval '10 minutes',
          'manual_reminder_count', reminder.manual_count
        ) order by participant.season_player_id
      )
      from public.match_sport_participants participant
      left join lateral (
        select
          max(event.requested_at) as last_reminder_at,
          max(event.requested_at) filter (
            where event.kind = 'availability_manual'
          ) as last_manual_at,
          count(*) filter (
            where event.kind = 'availability_manual'
          ) as manual_count
        from public.sport_availability_notification_events event
        where event.participant_id = participant.id
      ) reminder on true
      where participant.match_id = workflow.match_id
        and (
          participant.is_eligible
          or private.participant_is_coach(participant.season_player_id)
        )
    ), '[]'::jsonb)
  )
  into v_result
  from public.match_sport_workflows workflow
  join public.matches match on match.id = workflow.match_id
  where workflow.match_id = p_match_id;

  if v_result is null then
    raise exception 'Sports workflow not found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$function$;
