-- Le texte de la relance manuelle de disponibilité ("Le staff attend ta
-- réponse") était froid. On le rend plus léger, dans le ton du reste des
-- notifications de l'appli.
begin;

create or replace function public.internal_sport_push_dispatch(p_kind text, p_match_id uuid, p_profile_ids uuid[])
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
      'title', 'Tu n''as pas répondu 👀',
      'body', format(
        'Pense à indiquer si tu es dispo pour le match contre %s !',
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

commit;
