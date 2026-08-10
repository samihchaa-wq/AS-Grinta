-- Refonte des notifications : on ne garde que 4 notifications utiles, on
-- retire les rappels superflus et le filtrage par préférences (tout le monde
-- reçoit tout, seul l'abonnement de l'appareil compte).
--
--   1. Dispo + prono  (à l'ouverture des disponibilités)
--   2. Relance manuelle de disponibilité (bouton admin — inchangé)
--   3. Score final     (à la validation du résultat ; les présents reçoivent
--                       en plus l'invitation à voter via la notif « vote HDM »)
--   4. Bravo à l'élu HDM (à la clôture du vote, uniquement aux votants)
--
-- Retirés : rappel prono H-5, rappel de vote HDM, doublon « nouveau match ».

-- 1) Disponibilités : le message d'ouverture invite aussi à pronostiquer.
--    Suppression du filtrage par préférence.
create or replace function public.internal_sport_push_dispatch(
  p_kind text,
  p_match_id uuid,
  p_profile_ids uuid[]
)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_match record;
  v_payload jsonb;
  v_subscriptions jsonb;
begin
  if p_kind not in (
    'availability_open', 'availability_j3', 'availability_j1', 'availability_manual'
  ) then
    raise exception 'Unknown sports notification kind' using errcode = '22023';
  end if;

  if p_profile_ids is null or cardinality(p_profile_ids) = 0 then
    return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
  end if;

  select m.id, m.kickoff_at, o.name as opponent_name
  into v_match
  from public.matches m
  join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  v_payload := case p_kind
    when 'availability_open' then jsonb_build_object(
      'title', 'Dispo & pronostic',
      'body', format(
        'Dispo pour le match du %s contre %s ? Pense à pronostiquer !',
        to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM à HH24hMI'),
        v_match.opponent_name
      ),
      'url', '.',
      'tag', 'sport-' || p_match_id || '-availability-open'
    )
    when 'availability_j3' then jsonb_build_object(
      'title', 'Réponds pour le prochain match',
      'body', format(
        'AS Grinta – %s : tu n''as pas encore indiqué ta disponibilité.',
        v_match.opponent_name
      ),
      'url', '.',
      'tag', 'sport-' || p_match_id || '-availability-j3'
    )
    when 'availability_j1' then jsonb_build_object(
      'title', 'Dernier rappel disponibilité',
      'body', format(
        'AS Grinta – %s joue demain. Disponible ou absent ?',
        v_match.opponent_name
      ),
      'url', '.',
      'tag', 'sport-' || p_match_id || '-availability-j1'
    )
    else jsonb_build_object(
      'title', 'Le staff attend ta réponse',
      'body', format(
        'AS Grinta – %s : indique maintenant si tu es disponible ou absent.',
        v_match.opponent_name
      ),
      'url', '.',
      'tag', 'sport-' || p_match_id || '-availability-manual'
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
    and exists (
      select 1
      from public.match_sport_participants participant
      join public.season_players player on player.id = participant.season_player_id
      where participant.match_id = p_match_id
        and participant.is_eligible
        and player.profile_id = subscription.profile_id
        and (
          p_kind = 'availability_open'
          or participant.availability_status = 'no_response'
        )
    );

  return jsonb_build_object('payload', v_payload, 'subscriptions', v_subscriptions);
end;
$function$;

-- 2) Score final + vote HDM + résultat HDM. Retrait de new_match, closing_soon,
--    motm_reminder et de tout filtrage par préférence.
create or replace function public.internal_push_dispatch(p_kind text, p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_match record;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_winner_names text;
  v_winner_count integer := 0;
  v_home_name text;
  v_away_name text;
  v_home_score text;
  v_away_score text;
begin
  select
    match.id, match.season_id, match.kickoff_at,
    match.score_as_grinta, match.score_adverse, match.location,
    opponent.name as opponent_name
  into v_match
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if p_kind in ('motm_open', 'motm_results')
     and not private.is_feature_enabled('sports_management') then
    return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
  end if;

  if p_kind = 'result_validated' then
    if v_match.location = 'exterieur' then
      v_home_name := v_match.opponent_name;
      v_away_name := 'AS Grinta';
      v_home_score := coalesce(v_match.score_adverse::text, '?');
      v_away_score := coalesce(v_match.score_as_grinta::text, '?');
    else
      v_home_name := 'AS Grinta';
      v_away_name := v_match.opponent_name;
      v_home_score := coalesce(v_match.score_as_grinta::text, '?');
      v_away_score := coalesce(v_match.score_adverse::text, '?');
    end if;

    v_payload := jsonb_build_object(
      'title', 'Score final',
      'body', format(
        'Score final : %s %s-%s %s.',
        v_home_name, v_home_score, v_away_score, v_away_name
      ),
      'url', '.',
      'tag', 'match-' || v_match.id || '-result'
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
    where profile.status = 'active';

  elsif p_kind = 'motm_open' then
    if not exists (
      select 1 from public.match_sport_motm_elections election
      where election.match_id = p_match_id
        and election.state = 'open'
        and now() >= election.opens_at
        and now() < election.closes_at
    ) then
      return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
    end if;

    v_payload := jsonb_build_object(
      'title', 'Vote Homme du match',
      'body', format(
        'Vote pour l''Homme du Match — AS Grinta contre %s.',
        v_match.opponent_name
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
      and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and participant.final_presence_status = 'present'
          and player.profile_id = profile.id
      );

  elsif p_kind = 'motm_results' then
    select
      string_agg(w.display_name, ', ' order by lower(w.display_name)),
      count(*)::integer
    into v_winner_names, v_winner_count
    from (
      select case
        when guest.id is not null then
          btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
        else coalesce(
          nullif(btrim(profile.surnom), ''),
          nullif(btrim(player.first_name), ''),
          btrim(concat_ws(' ', player.first_name, player.last_name))
        )
      end as display_name
      from public.match_sport_motm_results result
      join public.match_sport_participants participant
        on participant.id = result.participant_id
       and participant.match_id = result.match_id
      left join public.season_players player on player.id = participant.season_player_id
      left join public.profiles profile on profile.id = player.profile_id
      left join public.guest_players guest on guest.id = participant.guest_player_id
      where result.match_id = p_match_id
        and result.is_winner
    ) w;

    v_payload := jsonb_build_object(
      'title', case when v_winner_count > 1 then 'Co-Hommes du match'
                    else 'Homme du match' end,
      'body', case
        when v_winner_count = 0 then
          format('AS Grinta – %s : aucun Homme du match n''a été élu.', v_match.opponent_name)
        when v_winner_count = 1 then
          format('Bravo à %s, élu Homme du Match !', v_winner_names)
        else
          format('Bravo à %s, élus Hommes du Match !', v_winner_names)
      end,
      'url', 'matches/' || p_match_id || '/vote',
      'tag', 'sport-' || p_match_id || '-motm-results'
    );

    -- Uniquement les joueurs qui ont voté.
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
        select 1 from public.match_sport_motm_votes vote
        where vote.match_id = p_match_id
          and vote.voter_profile_id = profile.id
      );

  else
    raise exception 'Unknown notification kind: %', p_kind using errcode = '22023';
  end if;

  return jsonb_build_object(
    'payload', v_payload,
    'subscriptions', coalesce(v_subscriptions, '[]'::jsonb)
  );
end;
$function$;

-- 3) Retirer les déclencheurs des notifications supprimées.
do $$ begin perform cron.unschedule('push-closing-reminders'); exception when others then null; end $$;
do $$ begin perform cron.unschedule('sports-motm-push-reminders'); exception when others then null; end $$;
drop trigger if exists trg_push_on_match_insert on public.matches;
