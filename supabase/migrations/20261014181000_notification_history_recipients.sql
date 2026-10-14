begin;

-- Historique des notifications : les destinataires ne dépendent plus du
-- téléphone.
--
-- L'historique (20261014180000_notification_history.sql) garde tout ce que
-- le club envoie à un joueur, même quand son téléphone ne l'a jamais
-- affiché : notifications coupées, téléphone désabonné, aucun appareil.
-- Jusqu'ici, la liste des destinataires n'existait qu'à travers les
-- téléphones abonnés : un joueur sans appareil n'apparaissait nulle part.
--
-- - Les fonctions qui préparent les envois (rappel de pronostic, match
--   annulé ou déplacé, ouverture du vote, disponibilités, alertes du direct)
--   renvoient en plus recipient_profile_ids : les mêmes destinataires, avec
--   les mêmes conditions, sans passer par les téléphones. Le texte, la liste
--   des téléphones et les sorties anticipées ne changent pas.
-- - Le message écrit par un admin part vers tous les profils actifs choisis.
--   Le nombre renvoyé reste celui des destinataires qui ont un téléphone
--   abonné ; zéro n'est plus une erreur, le message arrive quand même dans
--   leur historique. Seule une sélection sans aucun profil actif est
--   refusée.
-- - La relance manuelle des disponibilités crée aussi la relance des joueurs
--   sans téléphone (même délai de dix minutes entre deux relances), pour
--   qu'elle arrive dans leur historique. Ils restent comptés parmi les
--   joueurs sans notifications, pas parmi les relances envoyées.
-- - Les notifications d'essai demandent explicitement à ne pas être
--   gardées : record_history = false. L'ancien essai (send_test_push) passe
--   par la branche « test » de send-push, qui n'enregistre jamais rien.
--
-- Chaque corps repart de sa dernière définition dans le dépôt, à ces seuls
-- ajouts près. Les droits sont réappliqués à l'identique.

-- ---------------------------------------------------------------------------
-- Rappel de pronostic, match annulé ou déplacé, ouverture du vote
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
  v_recipients jsonb;
  v_date text;
  v_time text;
  v_scoreline text;
begin
  select
    m.id,
    m.kickoff_at,
    m.status,
    m.match_type,
    m.location,
    m.score_as_grinta,
    m.score_adverse,
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

    -- Mêmes destinataires, téléphone abonné ou non : l'historique les
    -- reçoit tous.
    select coalesce(jsonb_agg(profile.id order by profile.id), '[]'::jsonb)
    into v_recipients
    from public.profiles profile
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

    select coalesce(jsonb_agg(profile.id order by profile.id), '[]'::jsonb)
    into v_recipients
    from public.profiles profile
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

    if v_match.opponent_name is not null
       and v_match.score_as_grinta is not null
       and v_match.score_adverse is not null then
      v_scoreline := case
        when v_match.location = 'domicile' then format(
          'AS Grinta %s - %s %s',
          v_match.score_as_grinta, v_match.score_adverse, v_match.opponent_name
        )
        else format(
          '%s %s - %s AS Grinta',
          v_match.opponent_name, v_match.score_adverse, v_match.score_as_grinta
        )
      end;
    end if;

    v_payload := jsonb_build_object(
      'title', 'Fin du match',
      'body', concat_ws(
        E'\n',
        v_scoreline,
        'Pense à voter pour l’Homme du match.'
      ),
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

    select coalesce(jsonb_agg(profile.id order by profile.id), '[]'::jsonb)
    into v_recipients
    from public.profiles profile
    where profile.status = 'active'
      and profile.notify_motm_vote
      and private.match_motm_voter_participant(p_match_id, profile.id) is not null;

  else
    raise exception 'Unknown notification kind: %', p_kind using errcode = '22023';
  end if;

  return jsonb_build_object(
    'payload', v_payload,
    'subscriptions', coalesce(v_subscriptions, '[]'::jsonb),
    'recipient_profile_ids', coalesce(v_recipients, '[]'::jsonb)
  );
end;
$function$;

revoke all on function public.internal_push_dispatch(text, uuid)
  from public, anon, authenticated;
grant execute on function public.internal_push_dispatch(text, uuid)
  to service_role;

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
  v_recipients jsonb;
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

  -- Mêmes conditions sans les téléphones abonnés : l'historique reçoit aussi
  -- les joueurs sans appareil.
  select coalesce(jsonb_agg(profile.id order by profile.id), '[]'::jsonb)
  into v_recipients
  from public.profiles profile
  where profile.id = any(p_profile_ids)
    and profile.status = 'active'
    and (
      (p_kind = 'availability_open' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and (participant.is_eligible or player.is_coach)
          and player.profile_id = profile.id
      ))
      or (p_kind = 'availability_manual' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and (participant.is_eligible or player.is_coach)
          and participant.availability_status = 'no_response'
          and player.profile_id = profile.id
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
              and player.profile_id = profile.id
          ))
    );

  return jsonb_build_object(
    'payload', v_payload,
    'subscriptions', v_subscriptions,
    'recipient_profile_ids', v_recipients
  );
end;
$function$;

revoke all on function public.internal_sport_push_dispatch(text, uuid, uuid[])
  from public, anon, authenticated;
grant execute on function public.internal_sport_push_dispatch(text, uuid, uuid[])
  to service_role;

-- ---------------------------------------------------------------------------
-- Alertes du match en direct
-- ---------------------------------------------------------------------------

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
  v_recipients jsonb;
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

  -- Cibles toujours inscrites, téléphone abonné ou non : l'historique les
  -- reçoit toutes, au moment de l'envoi.
  select coalesce(
    jsonb_agg(target.profile_id order by target.profile_id),
    '[]'::jsonb
  )
  into v_recipients
  from private.match_live_notification_event_targets target
  join public.match_live_notification_subscriptions subscription
    on subscription.match_id = v_event.match_id
   and subscription.profile_id = target.profile_id
   and subscription.completed_at is null
  join public.profiles profile
    on profile.id = target.profile_id
   and profile.status = 'active'
  where target.notification_id = v_event.id;

  return jsonb_build_object(
    'claimed', true,
    'notification_id', v_event.id,
    'match_id', v_event.match_id,
    'kind', v_log_kind,
    'payload', v_payload,
    'subscriptions', v_subscriptions,
    'recipient_profile_ids', v_recipients
  );
end;
$function$;

revoke all on function public.internal_claim_match_live_notification(uuid)
  from public, anon, authenticated;
grant execute on function public.internal_claim_match_live_notification(uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- Message écrit par un admin
-- ---------------------------------------------------------------------------

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

  -- Tous les profils actifs choisis reçoivent le message dans leur
  -- historique, téléphone abonné ou non.
  select coalesce(array_agg(profile.id), '{}'::uuid[])
  into v_recipients
  from public.profiles profile
  where profile.id = any(p_profile_ids)
    and profile.status = 'active';

  if coalesce(array_length(v_recipients, 1), 0) = 0 then
    raise exception 'Aucun destinataire actif.'
      using errcode = '22023';
  end if;

  -- Le nombre renvoyé reste celui des destinataires qui ont un téléphone
  -- abonné : c'est ce que l'écran d'envoi annonce. Zéro n'est plus une
  -- erreur, le message arrive quand même dans leur historique.
  select count(*)::integer
  into v_count
  from public.profiles profile
  where profile.id = any(v_recipients)
    and exists (
      select 1
      from public.push_subscriptions subscription
      where subscription.profile_id = profile.id
    );

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

revoke all on function public.admin_send_custom_push(text, text, uuid[])
  from public, anon;
grant execute on function public.admin_send_custom_push(text, text, uuid[])
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Relance manuelle des disponibilités
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.send_sport_availability_reminder(p_match_id uuid, p_season_player_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_row record;
  v_event_id bigint;
  v_created integer := 0;
  v_skipped_recent integer := 0;
  v_skipped_no_subscription integer := 0;
  v_target_count integer := 0;
  v_reason text := nullif(trim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if private.is_feature_enabled('notifications_paused') then
    raise exception 'Les notifications sont désactivées.' using errcode = '55000';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason is too long' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    where workflow.match_id = p_match_id
      and workflow.availability_state = 'open'
      and match.status = 'a_venir'
      and match.kickoff_at > now()
  ) then
    raise exception 'Availability reminders are not open for this match'
      using errcode = '22023';
  end if;

  for v_row in
    select
      participant.id as participant_id,
      participant.season_player_id,
      player.profile_id
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where participant.match_id = p_match_id
      and (participant.is_eligible or player.is_coach)
      and participant.availability_status = 'no_response'
      and player.profile_id is not null
      and profile.status = 'active'
      and (
        p_season_player_id is null
        or participant.season_player_id = p_season_player_id
      )
    order by participant.id
  loop
    v_target_count := v_target_count + 1;

    -- Sans téléphone abonné, la relance est quand même créée pour arriver
    -- dans l'historique du joueur (même délai de dix minutes), mais elle
    -- reste comptée parmi les joueurs sans notifications, pas parmi les
    -- relances envoyées : le retour affiché à l'admin garde son sens.
    if not exists (
      select 1
      from public.push_subscriptions subscription
      where subscription.profile_id = v_row.profile_id
    ) then
      v_skipped_no_subscription := v_skipped_no_subscription + 1;
      if not exists (
        select 1
        from public.sport_availability_notification_events event
        where event.participant_id = v_row.participant_id
          and event.kind = 'availability_manual'
          and event.requested_at > now() - interval '10 minutes'
      ) then
        perform private.create_sport_availability_notification(
          p_match_id,
          v_row.participant_id,
          v_row.profile_id,
          'availability_manual',
          'manual',
          now(),
          v_actor,
          v_reason
        );
      end if;
      continue;
    end if;

    if exists (
      select 1
      from public.sport_availability_notification_events event
      where event.participant_id = v_row.participant_id
        and event.kind = 'availability_manual'
        and event.requested_at > now() - interval '10 minutes'
    ) then
      v_skipped_recent := v_skipped_recent + 1;
      continue;
    end if;

    v_event_id := private.create_sport_availability_notification(
      p_match_id,
      v_row.participant_id,
      v_row.profile_id,
      'availability_manual',
      'manual',
      now(),
      v_actor,
      v_reason
    );

    if v_event_id is not null then
      v_created := v_created + 1;
    end if;
  end loop;

  if p_season_player_id is not null and v_target_count = 0 then
    raise exception 'Player is not waiting for an availability response'
      using errcode = '22023';
  end if;

  insert into private.sport_admin_audit_log (
    match_id,
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    p_match_id,
    'send_availability_reminder',
    v_actor,
    v_reason,
    jsonb_build_object(
      'season_player_id', p_season_player_id,
      'target_count', v_target_count,
      'created_count', v_created,
      'skipped_recent_count', v_skipped_recent,
      'skipped_no_subscription_count', v_skipped_no_subscription
    )
  );

  return jsonb_build_object(
    'target_count', v_target_count,
    'created_count', v_created,
    'skipped_recent_count', v_skipped_recent,
    'skipped_no_subscription_count', v_skipped_no_subscription
  );
end;
$function$;

revoke all on function private.send_sport_availability_reminder(uuid, uuid, text)
  from public, anon;
grant execute on function private.send_sport_availability_reminder(uuid, uuid, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Notifications d'essai
-- ---------------------------------------------------------------------------

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
  -- Les exemples liés à un match n'ont pas de vrai match : ils ouvrent
  -- l'accueil. Les autres ouvrent le même écran que la vraie notification.
  v_url text := '.';
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
    when 'convocation_demoted' then
      v_title := 'Tu passes en liste d''attente';
      v_body := 'Tu passes en liste d''attente pour le match du 12/09 contre FC Exemple.';
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
      v_title := 'Fin du match';
      v_body := E'AS Grinta 2 - 1 FC Exemple\nPense à voter pour l’Homme du match.';
    when 'motm_result_general' then
      v_title := 'Homme du match';
      v_body := 'Joueur Test a été élu Homme du match !';
    when 'motm_result_winner' then
      v_title := 'Homme du match';
      v_body := 'Bravo, tu as été élu Homme du match !';
    when 'admin_pending_signup' then
      v_title := 'Nouveau compte en attente';
      v_body := 'Joueur Test attend ta validation.';
      v_url := 'admin/administration';
    when 'admin_availability_change' then
      v_title := 'Changement de disponibilité';
      v_body := 'À 20h30, Joueur Test est passé de présent à absent.';
    when 'badge_unlocked' then
      v_badge_payload := private.badge_unlock_push_message(array['Buteur']);
      v_title := v_badge_payload ->> 'title';
      v_body := v_badge_payload ->> 'message';
      v_url := 'armoire';
    when 'badges_unlocked' then
      v_badge_payload := private.badge_unlock_push_message(
        array['Buteur', 'Passeur']
      );
      v_title := v_badge_payload ->> 'title';
      v_body := v_badge_payload ->> 'message';
      v_url := 'armoire';
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
      'message', v_body,
      'url', v_url,
      -- Un essai n'est pas un message du club : jamais dans l'historique.
      'record_history', false
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

revoke all on function public.send_test_push_kind(text) from public, anon;
grant execute on function public.send_test_push_kind(text)
  to authenticated, service_role;

commit;
