begin;

-- Les notifications de disponibilité ouvrent le calendrier sur le match.
--
-- « Disponibilité » (ouverture), la relance « Tu n'as pas répondu » et
-- « Match reporté… » ouvraient l'onglet Effectif de la fiche du match. Cet
-- onglet montre qui vient, mais le choix Présent / Absent se fait sur la carte
-- du match, dans le calendrier. Elles ouvrent désormais le calendrier
-- directement sur cette carte (`matches?match=<id>`).
--
-- La convocation garde l'onglet Effectif : il n'y a rien à répondre.
--
-- Chaque corps est la définition en service en production (relevée avec
-- pg_get_functiondef, empreinte identique à celle de la base rejouée depuis
-- le dépôt), à la seule adresse près. create or replace conserve
-- propriétaires et droits.

-- ---------------------------------------------------------------------------
-- Ouverture des disponibilités et relance
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.internal_sport_push_dispatch(p_kind text, p_match_id uuid, p_profile_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_match record;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_date text;
  v_time text;
begin
  if p_kind not in ('availability_open', 'availability_manual', 'convocation_promoted') then
    raise exception 'Unknown sports notification kind' using errcode = '22023';
  end if;
  if p_profile_ids is null or cardinality(p_profile_ids) = 0 then
    return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
  end if;

  select m.id, m.kickoff_at, nullif(btrim(o.name), '') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  v_date := to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM');
  v_time := private.match_notification_time_label(v_match.kickoff_at);

  v_payload := case p_kind
    when 'availability_open' then jsonb_build_object(
      'title', 'Disponibilité',
      'body', case
        when v_match.opponent_name is null then format(
          'Es-tu disponible pour le match entre nous du %s à %s ?',
          v_date, v_time
        )
        else format(
          'Es-tu disponible pour le match du %s contre %s à %s ?',
          v_date, v_match.opponent_name, v_time
        )
      end,
      'url', 'matches?match=' || p_match_id,
      'tag', 'sport-' || p_match_id || '-availability-open'
    )
    when 'availability_manual' then jsonb_build_object(
      'title', 'Tu n''as pas répondu 👀',
      'body', case
        when v_match.opponent_name is null then
          'Pense à indiquer si tu es disponible pour le match entre nous !'
        else format(
          'Pense à indiquer si tu es disponible pour le match contre %s !',
          v_match.opponent_name
        )
      end,
      'url', 'matches?match=' || p_match_id,
      'tag', 'sport-' || p_match_id || '-availability-manual'
    )
    else jsonb_build_object(
      'title', 'Tu es convoqué',
      'body', case
        when v_match.opponent_name is null then format(
          'Tu es convoqué pour le match entre nous du %s.',
          v_date
        )
        else format(
          'Tu es convoqué pour le match du %s contre %s.',
          v_date, v_match.opponent_name
        )
      end,
      'url', 'matches/' || p_match_id || '/lineup?section=effectif',
      'tag', 'sport-' || p_match_id || '-convocation'
    )
  end;

  select coalesce(jsonb_agg(jsonb_build_object(
    'profile_id', subscription.profile_id,
    'endpoint', subscription.endpoint,
    'p256dh', subscription.p256dh,
    'auth', subscription.auth
  )), '[]'::jsonb)
  into v_subscriptions
  from public.push_subscriptions subscription
  join public.profiles profile on profile.id = subscription.profile_id
  where subscription.profile_id = any(p_profile_ids)
    and profile.status = 'active'
    and (
      (p_kind = 'availability_open' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and (participant.is_eligible or player.is_coach)
          and player.profile_id = subscription.profile_id
      ))
      or (p_kind = 'availability_manual' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and (participant.is_eligible or player.is_coach)
          and participant.availability_status = 'no_response'
          and player.profile_id = subscription.profile_id
      ))
      or (p_kind = 'convocation_promoted'
          and profile.notify_convocation
          and exists (
            select 1
            from public.match_sport_participants participant
            join public.season_players player on player.id = participant.season_player_id
            join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
            where participant.match_id = p_match_id
              and (participant.is_eligible or player.is_coach)
              and participant.convocation_status = 'convoked'
              and workflow.convocation_state = 'published'
              and player.profile_id = subscription.profile_id
          ))
    );

  return jsonb_build_object('payload', v_payload, 'subscriptions', v_subscriptions);
end;
$function$;

-- ---------------------------------------------------------------------------
-- Match reporté
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.internal_push_dispatch(p_kind text, p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_match record;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_date text;
  v_time text;
begin
  select
    m.id,
    m.kickoff_at,
    m.status,
    m.match_type,
    nullif(btrim(o.name), '') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if v_match.kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;

  if p_kind = 'prediction_j5' and v_match.match_type = 'entre_nous' then
    return jsonb_build_object(
      'payload', '{}'::jsonb,
      'subscriptions', '[]'::jsonb
    );
  end if;

  v_date := to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM');
  v_time := private.match_notification_time_label(v_match.kickoff_at);

  if p_kind = 'prediction_j5' then
    v_payload := jsonb_build_object(
      'title', 'Pronostic',
      'body', case
        when v_match.opponent_name is null then format(
          'Pense à pronostiquer pour le match entre nous du %s.',
          v_date
        )
        else format(
          'Pense à pronostiquer pour le match du %s contre %s.',
          v_date,
          v_match.opponent_name
        )
      end,
      'url', 'matches/' || p_match_id || '/lineup?section=prediction',
      'tag', 'match-' || p_match_id || '-prediction-j5'
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and profile.notify_prediction_reminders
      and not exists (
        select 1
        from public.match_predictions prediction
        where prediction.match_id = p_match_id
          and prediction.profile_id = profile.id
          and prediction.is_filled
      );

  elsif p_kind in ('match_cancelled', 'match_rescheduled_date', 'match_rescheduled_time') then
    v_payload := case p_kind
      when 'match_cancelled' then jsonb_build_object(
        'title', 'Match annulé',
        'body', case
          when v_match.opponent_name is null then format(
            'Le match entre nous du %s à %s est annulé.',
            v_date, v_time
          )
          else format(
            'Le match du %s contre %s à %s est annulé.',
            v_date, v_match.opponent_name, v_time
          )
        end,
        'url', 'matches/' || p_match_id || '/lineup?section=info',
        'tag', 'match-' || p_match_id || '-cancelled'
      )
      when 'match_rescheduled_date' then jsonb_build_object(
        'title', 'Match reporté',
        'body', case
          when private.match_features_open_at(v_match.kickoff_at) <= now()
            then case
              when v_match.opponent_name is null then format(
                'Le match entre nous est reporté au %s à %s. Es-tu disponible ?',
                v_date, v_time
              )
              else format(
                'Le match contre %s est reporté au %s à %s. Es-tu disponible ?',
                v_match.opponent_name, v_date, v_time
              )
            end
          else case
            when v_match.opponent_name is null then format(
              'Le match entre nous est reporté au %s à %s.',
              v_date, v_time
            )
            else format(
              'Le match contre %s est reporté au %s à %s.',
              v_match.opponent_name, v_date, v_time
            )
          end
        end,
        'url', 'matches?match=' || p_match_id,
        'tag', 'match-' || p_match_id || '-rescheduled-date'
      )
      else jsonb_build_object(
        'title', 'Horaire du match modifié',
        'body', case
          when v_match.opponent_name is null then format(
            'Le match entre nous du %s aura finalement lieu à %s.',
            v_date, v_time
          )
          else format(
            'Le match du %s contre %s aura finalement lieu à %s.',
            v_date, v_match.opponent_name, v_time
          )
        end,
        'url', 'matches/' || p_match_id || '/lineup?section=info',
        'tag', 'match-' || p_match_id || '-rescheduled-time'
      )
    end;

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and (participant.is_eligible or player.is_coach)
          and player.profile_id = profile.id
      );

  elsif p_kind = 'motm_open' then
    if not private.is_feature_enabled('sports_management') then
      return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
    end if;
    if not exists (
      select 1
      from public.match_sport_motm_elections election
      where election.match_id = p_match_id
        and election.state = 'open'
        and now() >= election.opens_at
        and now() < election.closes_at
    ) then
      return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
    end if;

    v_payload := jsonb_build_object(
      'title', 'Homme du match',
      'body', 'Pense à voter pour l’Homme du match.',
      'url', 'matches/' || p_match_id || '/vote',
      'tag', 'sport-' || p_match_id || '-motm-open'
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and profile.notify_motm_vote
      and private.match_motm_voter_participant(p_match_id, profile.id) is not null;

  else
    raise exception 'Unknown notification kind: %', p_kind using errcode = '22023';
  end if;

  return jsonb_build_object(
    'payload', v_payload,
    'subscriptions', coalesce(v_subscriptions, '[]'::jsonb)
  );
end;
$function$;

commit;
