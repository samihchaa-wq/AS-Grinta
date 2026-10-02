-- Relecture des textes affichés aux joueurs et aux responsables.
--
-- Corrige des informations fausses (durée du vote Homme du match, titre de la
-- notification des compositions entre nous), des fautes, des abréviations et
-- du jargon dans les notifications, les messages d'erreur et les badges.
--
-- Chaque fonction est reprise à l'identique de sa définition en production
-- (empreinte vérifiée avant écriture) : seuls les textes changent. CREATE OR
-- REPLACE conserve les droits d'exécution existants.

begin;

-- Notification de composition : même titre que celui annoncé dans l’appli, sans abréviation.
create or replace function private.dispatch_composition_published_push(
  p_match_id uuid,
  p_profile_ids uuid[]
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_request_id bigint;
  v_title text;
  v_body text;
  v_match record;
begin
  if p_profile_ids is null
     or cardinality(p_profile_ids) = 0
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  select
    m.kickoff_at,
    m.match_type,
    nullif(btrim(o.name), '') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found or v_match.kickoff_at is null then
    return false;
  end if;

  v_title := case
    when v_match.match_type = 'entre_nous'
      then 'Les compositions sont en ligne'
    else 'La composition est en ligne'
  end;

  v_body := case
    when v_match.match_type = 'entre_nous' then format(
      'Les compositions du match entre nous du %s sont prêtes.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM')
    )
    else format(
      'La composition du match du %s contre %s est en ligne.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM'),
      v_match.opponent_name
    )
  end;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';
  if v_token is null then
    return false;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', to_jsonb(p_profile_ids),
      'title', v_title,
      'message', v_body
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception when others then
  return false;
end;
$function$;

-- Notification de but en direct : « But de l’AS Grinta ! ».
create or replace function public.internal_claim_match_live_notification(
  p_notification_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event private.match_live_notification_events%rowtype;
  v_match record;
  v_home_name text;
  v_away_name text;
  v_home_score integer;
  v_away_score integer;
  v_scoreline text;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_log_kind text;
begin
  update private.match_live_notification_events event
  set state = 'dispatching', claimed_at = now()
  where event.id = p_notification_id
    and event.state = 'pending'
    and event.due_at <= now()
  returning event.* into v_event;

  if not found then
    return jsonb_build_object('claimed', false);
  end if;

  select
    match.location,
    coalesce(nullif(btrim(opponent.name), ''), 'Adversaire') as opponent_name
  into v_match
  from public.matches match
  left join public.opponents opponent on opponent.id = match.opponent_id
  where match.id = v_event.match_id;

  if not found then
    update private.match_live_notification_events event
    set state = 'cancelled', completed_at = now()
    where event.id = v_event.id;
    return jsonb_build_object('claimed', false);
  end if;

  if v_match.location = 'domicile' then
    v_home_name := 'AS Grinta';
    v_away_name := v_match.opponent_name;
    v_home_score := v_event.score_as_grinta;
    v_away_score := v_event.score_adverse;
  else
    v_home_name := v_match.opponent_name;
    v_away_name := 'AS Grinta';
    v_home_score := v_event.score_adverse;
    v_away_score := v_event.score_as_grinta;
  end if;

  v_scoreline := format('%s %s–%s %s', v_home_name, v_home_score, v_away_score, v_away_name);

  if v_event.kind = 'kickoff' then
    v_log_kind := 'live_kickoff';
    v_payload := jsonb_build_object(
      'title', '⚽ Le match commence',
      'body', format('%s – %s', v_home_name, v_away_name),
      'url', 'matches/' || v_event.match_id || '/lineup?section=live',
      'tag', 'live-' || v_event.match_id || '-kickoff'
    );
  elsif v_event.kind = 'goal_us' then
    v_log_kind := 'live_goal_us';
    v_payload := jsonb_build_object(
      'title', '⚽ But !',
      'body', case
        when nullif(btrim(v_event.scorer_name), '') is not null
          then format('But de %s ! %s', v_event.scorer_name, v_scoreline)
        else format('But de l’AS Grinta ! %s', v_scoreline)
      end,
      'url', 'matches/' || v_event.match_id || '/lineup?section=live',
      'tag', 'live-' || v_event.match_id || '-goal-' || v_event.id
    );
  elsif v_event.kind = 'goal_them' then
    v_log_kind := 'live_goal_them';
    v_payload := jsonb_build_object(
      'title', format('⚽ But pour %s', v_match.opponent_name),
      'body', v_scoreline,
      'url', 'matches/' || v_event.match_id || '/lineup?section=live',
      'tag', 'live-' || v_event.match_id || '-goal-' || v_event.id
    );
  else
    v_log_kind := 'live_full_time';
    v_payload := jsonb_build_object(
      'title', '🏁 Fin du match',
      'body', v_scoreline,
      'url', 'matches/' || v_event.match_id || '/lineup?section=live',
      'tag', 'live-' || v_event.match_id || '-full-time'
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', push.profile_id,
        'endpoint', push.endpoint,
        'p256dh', push.p256dh,
        'auth', push.auth
      ) order by push.profile_id, push.endpoint
    ),
    '[]'::jsonb
  )
  into v_subscriptions
  from private.match_live_notification_event_targets target
  join public.match_live_notification_subscriptions subscription
    on subscription.match_id = v_event.match_id
   and subscription.profile_id = target.profile_id
   and subscription.completed_at is null
  join public.profiles profile
    on profile.id = target.profile_id
   and profile.status = 'active'
  join public.push_subscriptions push
    on push.profile_id = target.profile_id
  where target.notification_id = v_event.id;

  return jsonb_build_object(
    'claimed', true,
    'notification_id', v_event.id,
    'match_id', v_event.match_id,
    'kind', v_log_kind,
    'payload', v_payload,
    'subscriptions', v_subscriptions
  );
end;
$function$;

-- Notification d’ouverture du vote : « Homme du match » avec majuscule.
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
        'url', 'matches/' || p_match_id || '/lineup?section=effectif',
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

-- Notifications de disponibilité : « disponible » au lieu de « dispo ».
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
      'url', 'matches/' || p_match_id || '/lineup?section=effectif',
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
      'url', 'matches/' || p_match_id || '/lineup?section=effectif',
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

-- Notification aux admins : l’heure du changement passe en tête de phrase.
create or replace function private.admin_availability_change_message(
  p_display_name text,
  p_old_status text,
  p_new_status text,
  p_changed_at timestamptz
)
returns text
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_from_label text;
  v_new_label text;
  v_name text := coalesce(nullif(btrim(p_display_name), ''), 'Un joueur');
begin
  if p_old_status not in ('available', 'absent')
     or p_new_status not in ('available', 'absent')
     or p_old_status = p_new_status then
    return null;
  end if;

  v_from_label := case p_old_status
    when 'available' then 'de présent'
    else 'd''absent'
  end;
  v_new_label := case p_new_status
    when 'available' then 'présent'
    else 'absent'
  end;

  return format(
    'À %s, %s est passé %s à %s.',
    to_char(coalesce(p_changed_at, now()) at time zone 'Europe/Paris', 'HH24"h"MI'),
    v_name,
    v_from_label,
    v_new_label
  );
end;
$function$;

-- Notifications de test : mêmes textes que les vraies notifications.
create or replace function public.send_test_push_kind(p_kind text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_actor uuid := (select auth.uid());
  v_subscriptions integer;
  v_recent_attempts integer;
  v_title text;
  v_body text;
  v_kind text := btrim(coalesce(p_kind, ''));
  v_badge_payload jsonb;
begin
  if v_actor is null or not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  if v_kind = 'admin_availability_change'
     and not public.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  case v_kind
    when 'test' then
      v_title := 'Test AS Grinta';
      v_body := 'Si tu vois ceci, les notifications fonctionnent 🎉';
    when 'availability_open' then
      v_title := 'Disponibilité';
      v_body := 'Es-tu disponible pour le match du 12/09 contre FC Exemple à 20h30 ?';
    when 'availability_manual' then
      v_title := 'Tu n''as pas répondu 👀';
      v_body := 'Pense à indiquer si tu es disponible pour le match contre FC Exemple !';
    when 'convocation_promoted' then
      v_title := 'Tu es convoqué';
      v_body := 'Tu es convoqué pour le match du 12/09 contre FC Exemple.';
    when 'composition_published' then
      v_title := 'La composition est en ligne';
      v_body := 'La composition du match du 12/09 contre FC Exemple est en ligne.';
    when 'prediction_j5' then
      v_title := 'Pronostic';
      v_body := 'Pense à pronostiquer pour le match du 12/09 contre FC Exemple.';
    when 'match_cancelled' then
      v_title := 'Match annulé';
      v_body := 'Le match du 12/09 contre FC Exemple à 20h30 est annulé.';
    when 'match_rescheduled_date' then
      v_title := 'Match reporté';
      v_body := 'Le match contre FC Exemple est reporté au 12/09 à 20h30. Es-tu disponible ?';
    when 'match_rescheduled_time' then
      v_title := 'Horaire du match modifié';
      v_body := 'Le match du 12/09 contre FC Exemple aura finalement lieu à 20h30.';
    when 'motm_open' then
      v_title := 'Homme du match';
      v_body := 'Pense à voter pour l’Homme du match.';
    when 'motm_result_general' then
      v_title := 'Homme du match';
      v_body := 'Joueur Test a été élu Homme du match !';
    when 'motm_result_winner' then
      v_title := 'Homme du match';
      v_body := 'Bravo, tu as été élu Homme du match !';
    when 'admin_pending_signup' then
      v_title := 'Nouveau compte en attente';
      v_body := 'Joueur Test attend ta validation.';
    when 'admin_availability_change' then
      v_title := 'Changement de disponibilité';
      v_body := 'À 20h30, Joueur Test est passé de présent à absent.';
    when 'badge_unlocked' then
      v_badge_payload := private.badge_unlock_push_message(array['Buteur']);
      v_title := v_badge_payload ->> 'title';
      v_body := v_badge_payload ->> 'message';
    when 'badges_unlocked' then
      v_badge_payload := private.badge_unlock_push_message(
        array['Buteur', 'Passeur']
      );
      v_title := v_badge_payload ->> 'title';
      v_body := v_badge_payload ->> 'message';
    else
      raise exception 'Unknown test notification kind' using errcode = '22023';
  end case;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('send_test_push:' || v_actor::text, 0)
  );

  delete from private.test_push_attempts attempt
  where attempt.profile_id = v_actor
    and attempt.attempted_at < now() - interval '1 day';

  select count(*)::integer
  into v_recent_attempts
  from private.test_push_attempts attempt
  where attempt.profile_id = v_actor
    and attempt.attempted_at >= now() - interval '10 minutes';

  if v_recent_attempts >= 3 then
    return jsonb_build_object('sent', false, 'reason', 'rate_limited');
  end if;

  select count(*)
  into v_subscriptions
  from public.push_subscriptions subscription
  where subscription.profile_id = v_actor;

  if v_subscriptions = 0 then
    return jsonb_build_object('sent', false, 'reason', 'no_subscription');
  end if;

  if coalesce(
       (private.get_notifications_paused()
          #>> '{notifications_paused,enabled}')::boolean,
       false
     ) then
    return jsonb_build_object('sent', false, 'reason', 'notifications_paused');
  end if;

  select secret.decrypted_secret into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return jsonb_build_object('sent', false, 'reason', 'not_configured');
  end if;

  insert into private.test_push_attempts (profile_id)
  values (v_actor);

  perform net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', jsonb_build_array(v_actor),
      'title', v_title,
      'message', v_body
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  );

  return jsonb_build_object(
    'sent', true,
    'subscriptions', v_subscriptions,
    'kind', v_kind
  );
end;
$function$;

-- Annulation du vote : le vote ferme 24 h après le coup d’envoi, pas après la validation.
CREATE OR REPLACE FUNCTION private.admin_cancel_match_motm_vote(p_match_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_version integer;
  v_state public.sport_vote_state;
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

  select election.finalization_version, election.state
  into v_version, v_state
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
  for update;
  if not found then
    raise exception 'MOTM vote is unavailable' using errcode = 'P0002';
  end if;

  if v_state in ('draft', 'open') then
    raise exception 'Le vote Homme du match se ferme automatiquement 24 h après le coup d’envoi.'
      using errcode = '22023';
  end if;

  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;
  update public.match_sport_motm_elections
  set state = 'cancelled', closes_at = null, closed_at = null,
      total_votes = 0, max_votes = 0, updated_at = now()
  where match_id = p_match_id;
  update public.match_sport_workflows
  set vote_state = 'cancelled', updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'cancel_motm_vote', v_actor, v_reason,
    jsonb_build_object('finalization_version', v_version)
  );

  return jsonb_build_object('match_id', p_match_id, 'state', 'cancelled');
end;
$function$;

-- Notification manuelle : messages ponctués.
create or replace function public.admin_send_custom_push(
  p_title text,
  p_body text,
  p_profile_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_title text := nullif(btrim(p_title), '');
  v_body text := nullif(btrim(p_body), '');
  v_recipients uuid[];
  v_count integer;
begin
  if not public.is_admin() then
    raise exception 'Admin required' using errcode = '42501';
  end if;
  if private.is_feature_enabled('notifications_paused') then
    raise exception 'Les notifications sont désactivées.' using errcode = '55000';
  end if;
  if v_title is null or v_body is null then
    raise exception 'Un titre et un message sont requis.' using errcode = '22023';
  end if;
  if char_length(v_title) > 80 then
    raise exception 'Le titre ne peut pas dépasser 80 caractères.'
      using errcode = '22023';
  end if;
  if char_length(v_body) > 300 then
    raise exception 'Le message ne peut pas dépasser 300 caractères.'
      using errcode = '22023';
  end if;
  if p_profile_ids is null or array_length(p_profile_ids, 1) is null then
    raise exception 'Choisis au moins un destinataire.' using errcode = '22023';
  end if;

  select coalesce(array_agg(profile.id), '{}'::uuid[])
  into v_recipients
  from public.profiles profile
  where profile.id = any(p_profile_ids)
    and profile.status = 'active'
    and exists (
      select 1
      from public.push_subscriptions subscription
      where subscription.profile_id = profile.id
    );

  v_count := coalesce(array_length(v_recipients, 1), 0);
  if v_count = 0 then
    raise exception 'Aucun destinataire n’a activé les notifications.'
      using errcode = '22023';
  end if;

  select secret.decrypted_secret into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    raise exception 'Les notifications push ne sont pas configurées.';
  end if;

  perform net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'title', v_title,
      'message', v_body,
      'profile_ids', to_jsonb(v_recipients)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  );

  return v_count;
end;
$function$;

-- Création de saison : messages ponctués et compréhensibles.
create or replace function public.open_or_create_season(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  season_name text := btrim(coalesce(p_name, ''));
  start_year integer;
  end_year integer;
  season_id uuid;
  season_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if season_name !~ '^[0-9]{4}-[0-9]{4}$' then
    raise exception 'Le nom doit respecter le format 2026-2027.' using errcode = '22023';
  end if;

  start_year := substring(season_name from 1 for 4)::integer;
  end_year := substring(season_name from 6 for 4)::integer;
  if end_year <> start_year + 1 then
    raise exception 'La saison doit couvrir deux années consécutives.' using errcode = '22023';
  end if;
  if start_year < 2000 or start_year > 2100 then
    raise exception 'Cette année de saison n’est pas acceptée.' using errcode = '22023';
  end if;

  select season.id, season.status
  into season_id, season_status
  from public.seasons season
  where season.name = season_name
  for update;

  if found then
    if season_status <> 'open'
       and private.season_has_historical_competition(season_id) then
      raise exception 'Une saison avec des données de compétition ne peut pas être rouverte.'
        using errcode = '22023';
    end if;

    update public.seasons
    set status = 'archived'
    where status = 'open'
      and id <> season_id;

    update public.seasons
    set status = 'open'
    where id = season_id;

    return season_id;
  end if;

  update public.seasons
  set status = 'archived'
  where status = 'open';

  insert into public.seasons(name, status)
  values (season_name, 'open')
  returning id into season_id;

  return season_id;
end;
$function$;

-- Pronostic fermé : phrase complète.
CREATE OR REPLACE FUNCTION public.guard_match_prediction_window()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_kickoff timestamptz; v_match_status text; v_closed_at timestamptz; v_match_type text; begin if (select auth.uid()) is not null and pg_trigger_depth() <= 1 then if tg_op='UPDATE' and new.match_id is distinct from old.match_id then raise exception 'Le match d’un pronostic ne peut pas être modifié.' using errcode='22023'; end if; new.profile_id := (select auth.uid()); end if; if new.is_filled then select match.kickoff_at,match.status,match.predictions_closed_at,match.match_type into v_kickoff,v_match_status,v_closed_at,v_match_type from public.matches match where match.id=new.match_id; if not found then raise exception 'Match introuvable.' using errcode='P0002'; end if; if v_match_type='entre_nous' then raise exception 'Les matchs entre nous ne sont pas ouverts aux pronostics.' using errcode='22023'; end if; if v_kickoff is null or v_match_status<>'a_venir' or now()<private.match_features_open_at(v_kickoff) or now()>=private.match_prediction_closes_at(v_kickoff) or (v_closed_at is not null and now()>=v_closed_at) then raise exception 'Les pronostics de ce match sont fermés.' using errcode='22023'; end if; end if; return new; end; $function$;

-- Saison archivée : « immuables » remplacé par une formulation simple.
create or replace function private.guard_match_season_finality()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_source_status text;
  v_target_status text;
  v_archive_only boolean := false;
begin
  if tg_op = 'INSERT' then
    select season.status
    into v_target_status
    from public.seasons season
    where season.id = new.season_id
    for share;

    if not found or v_target_status <> 'open' then
      raise exception 'Un match ne peut être ajouté qu''à une saison ouverte.'
        using errcode = '22023';
    end if;

    return new;
  end if;

  select season.status
  into v_source_status
  from public.seasons season
  where season.id = old.season_id;

  if tg_op = 'DELETE' then
    if v_source_status = 'archived' then
      raise exception 'Les matchs d’une saison archivée ne peuvent plus être modifiés.'
        using errcode = '22023';
    end if;

    return old;
  end if;

  if new.season_id is distinct from old.season_id then
    if v_source_status = 'archived' then
      raise exception 'Les matchs d’une saison archivée ne peuvent plus être modifiés.'
        using errcode = '22023';
    end if;

    select season.status
    into v_target_status
    from public.seasons season
    where season.id = new.season_id
    for share;

    if not found or v_target_status <> 'open' then
      raise exception 'Un match ne peut être déplacé que vers une saison ouverte.'
        using errcode = '22023';
    end if;

    return new;
  end if;

  if v_source_status = 'archived' then
    -- Keep the harmless housekeeping transition supported when a season was
    -- archived with a finished match after its correction window had closed.
    v_archive_only := old.status = 'termine'
      and new.status = 'archive'
      and (
        to_jsonb(new) - array['status', 'updated_at']::text[]
      ) = (
        to_jsonb(old) - array['status', 'updated_at']::text[]
      );

    if not v_archive_only then
      raise exception 'Les matchs d’une saison archivée ne peuvent plus être modifiés.'
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$function$;

-- Profil : « champs sensibles » remplacé par une formulation simple.
create or replace function public.guard_sensitive_profile_fields()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_id uuid := (select auth.uid());
  old_protected jsonb;
  new_protected jsonb;
  editable constant text[] := array[
    'first_name','last_name','surnom','photo_url','updated_at',
    'notify_prediction_open','notify_prediction_reminders','notify_match_reminders',
    'notify_motm_vote','notify_convocation','notify_composition','notify_badges',
    'password_set','must_change_password'
  ];
begin
  if actor_id is null then
    return new;
  end if;
  if public.is_match_staff() then
    return new;
  end if;
  if actor_id is distinct from old.id then
    raise exception 'Un utilisateur ne peut modifier que son propre profil.'
      using errcode = '42501';
  end if;

  old_protected := to_jsonb(old) - editable;
  new_protected := to_jsonb(new) - editable;

  if new_protected is distinct from old_protected then
    raise exception 'Certaines informations du profil ne peuvent être changées que par un administrateur.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

-- Pronostic sans session : message compréhensible.
create or replace function public.save_match_prediction(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_match public.matches%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Ta session a expiré. Reconnecte-toi.' using errcode = '42501';
  end if;
  if not private.is_active_profile() then
    raise exception 'Compte inactif.' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match requis.' using errcode = '22023';
  end if;
  if p_score_as_grinta is null or p_score_adverse is null
     or p_score_as_grinta not between 0 and 99
     or p_score_adverse not between 0 and 99 then
    raise exception 'Les scores doivent être compris entre 0 et 99.' using errcode = '22023';
  end if;

  select *
  into v_match
  from public.matches
  where id = p_match_id
  for share;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  if v_match.match_type = 'entre_nous' then
    raise exception 'Les matchs entre nous ne sont pas ouverts aux pronostics.'
      using errcode = '22023';
  end if;

  if v_match.kickoff_at is null
     or v_match.status <> 'a_venir'
     or now() < private.match_features_open_at(v_match.kickoff_at)
     or now() >= private.match_prediction_closes_at(v_match.kickoff_at)
     or (
       v_match.predictions_closed_at is not null
       and now() >= v_match.predictions_closed_at
     ) then
    raise exception 'Ce match n’est pas ouvert aux pronostics.'
      using errcode = '22023';
  end if;

  insert into public.match_predictions as existing (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled,
    updated_at
  ) values (
    p_match_id,
    v_actor_id,
    p_score_as_grinta,
    p_score_adverse,
    true,
    now()
  )
  on conflict (match_id, profile_id) do update
  set predicted_score_as_grinta = excluded.predicted_score_as_grinta,
      predicted_score_adverse = excluded.predicted_score_adverse,
      is_filled = true,
      updated_at = now()
  where (
    existing.predicted_score_as_grinta,
    existing.predicted_score_adverse,
    existing.is_filled
  ) is distinct from (
    excluded.predicted_score_as_grinta,
    excluded.predicted_score_adverse,
    true
  );

  return true;
end;
$function$;

-- Live : conflit d’enregistrement formulé sans jargon.
CREATE OR REPLACE FUNCTION private.save_match_live_lineup_versioned(p_match_id uuid, p_entries jsonb, p_substitution jsonb, p_expected_lineup_revision integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_current_revision integer;
begin
  perform private.require_sports_management_enabled();

  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  if p_expected_lineup_revision is null or p_expected_lineup_revision < 0 then
    raise exception 'Expected lineup revision is required' using errcode = '22023';
  end if;

  select session.lineup_revision
  into v_current_revision
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    raise exception 'Live session not found' using errcode = 'P0002';
  end if;

  if v_current_revision is distinct from p_expected_lineup_revision then
    raise exception
      'La composition Live a été modifiée entre-temps. Recharge l’écran avant d’enregistrer.'
      using errcode = '40001';
  end if;

  return private.save_match_live_lineup(
    p_match_id,
    p_entries,
    p_substitution
  );
end;
$function$;

-- Apostrophes droites restantes (badges créés depuis l'appli) : même règle
-- que la migration 20260813210700, limitée aux apostrophes entre deux lettres.
update public.badges
set name = regexp_replace(name, '([[:alpha:]])''([[:alpha:]])', '\1’\2', 'g')
where name ~ '[[:alpha:]]''[[:alpha:]]';

update public.badges
set description = regexp_replace(
      description, '([[:alpha:]])''([[:alpha:]])', '\1’\2', 'g'
    )
where description ~ '[[:alpha:]]''[[:alpha:]]';

-- « clean sheets » en deux mots, comme dans le reste de l'appli.
update public.badges
set description = replace(description, 'cleansheets', 'clean sheets')
where description like '%cleansheets%';

-- Le premier palier demande 5 passes : le nom ne doit plus suggérer une seule.
update public.badges set name = 'Passeur en herbe'
where code = 'assists_season__3';

update public.badges set name = 'Passe d’or',
  description = 'Terminer une saison en étant le joueur ayant délivré le plus grand nombre de passes décisives.'
where code = 'title_top_assists__1';

update public.badges
set description = 'Terminer une saison en étant le joueur ayant obtenu le plus de distinctions d’Homme du match.'
where code = 'title_mvp_king__1';

update public.badges
set description = 'Terminer une saison avec le meilleur total de points sur les pronostics.'
where code = 'title_best_pred_match__1';

update public.badges
set description = 'Pronostiquer contre l’AS Grinta… et avoir raison. Honte à toi.'
where code = 'bet_against_grinta__1';

-- Badges créés depuis l'appli : ils n'existent qu'en production, les mises à
-- jour ci-dessous ne touchent aucune ligne sur une base de test.
update public.badges set description = 'Glisser et perdre le ballon.'
where code = 'custom_la_glissade_1790198393809';
update public.badges set description = 'Marquer sur un retourné acrobatique.'
where code = 'custom_r_galade_1790198505439';
update public.badges set description = 'Marquer lors de 3 matchs consécutifs.'
where code = 'custom_jamais_2_sans_3_1790777301116';
update public.badges set description = 'Marquer l’unique but du match et gagner.'
where code = 'custom_minimum_syndical_1790777345623';
update public.badges set name = '« La línea amarilla ! »',
  description = 'Parler la langue d’un adversaire étranger.'
where code = 'custom_la_ligna_amarilla_1790198849385';
update public.badges set description = 'Sortir sur blessure en première mi-temps.'
where code = 'custom_mal_chauff_1790198442991';
update public.badges set name = '« C’est dans l’élan »',
  description = 'Commettre une grosse faute.'
where code = 'custom_c_est_dans_l_lan_1790726366134';
update public.badges set name = '« Voy a marcar »'
where code = 'custom_voy_a_marcar_1790725466122';
update public.badges set description = 'Être élu Homme du match deux matchs de suite.'
where code = 'custom_doubl_hdm_1790772063214';
update public.badges set description = 'Être défenseur, monter sur corner et marquer de la tête.'
where code = 'custom_t_te_de_boli_1790694926988';
update public.badges
set description = 'Prendre la place du gardien quand ce n’est pas son poste de prédilection.'
where code = 'custom_gardien_d_un_soir_1790198294777';
update public.badges set description = 'Marquer un triplé en une mi-temps.'
where code = 'custom_tripl_chrono_1790937793669';
update public.badges set name = 'Sauvetage in extremis'
where code = 'custom_sauvetage_in_extremis_1790725531858';
update public.badges set name = 'Le Malchanceux', description = 'Marquer contre son camp.'
where code = 'custom_le_malchanceux_1790198253832';
update public.badges set name = 'Le Boucher',
  description = 'Commettre une faute qui donne un penalty à l’adversaire.'
where code = 'custom_le_boucher_1790198376585';
update public.badges set name = 'Le Plongeur'
where code = 'custom_le_plongeur_1790198344854';

commit;
