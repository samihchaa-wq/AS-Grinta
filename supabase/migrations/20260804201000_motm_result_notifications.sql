begin;

-- Le réglage utilisateur `notify_motm_vote` couvre désormais tout le cycle HDM :
-- ouverture du scrutin + résultat. Le résultat est envoyé en deux groupes afin
-- que l'élu reçoive une félicitation personnalisée sans recevoir aussi le
-- message collectif.
create or replace function private.match_motm_result_notification_payloads(
  p_match_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_election_state public.sport_vote_state;
  v_winner_names text;
  v_winner_count integer := 0;
  v_winner_profile_ids uuid[] := array[]::uuid[];
  v_general_profile_ids uuid[] := array[]::uuid[];
  v_general_title text;
  v_general_message text;
  v_winner_title text;
  v_winner_message text;
begin
  if not private.is_feature_enabled('sports_management') then
    return jsonb_build_object(
      'general_profile_ids', '[]'::jsonb,
      'winner_profile_ids', '[]'::jsonb
    );
  end if;

  select election.state
  into v_election_state
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;

  if v_election_state is distinct from 'closed'::public.sport_vote_state then
    return jsonb_build_object(
      'general_profile_ids', '[]'::jsonb,
      'winner_profile_ids', '[]'::jsonb
    );
  end if;

  select
    string_agg(winner.display_name, ', ' order by lower(winner.display_name)),
    count(*)::integer,
    coalesce(
      array_agg(distinct winner.profile_id)
        filter (where winner.profile_id is not null),
      array[]::uuid[]
    )
  into v_winner_names, v_winner_count, v_winner_profile_ids
  from (
    select
      case
        when guest.id is not null then
          btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
        else coalesce(
          nullif(btrim(profile.surnom), ''),
          nullif(btrim(profile.first_name), ''),
          nullif(btrim(player.first_name), ''),
          btrim(concat_ws(' ', player.first_name, player.last_name)),
          'Joueur'
        )
      end as display_name,
      profile.id as profile_id
    from public.match_sport_motm_results result
    join public.match_sport_participants participant
      on participant.id = result.participant_id
     and participant.match_id = result.match_id
    left join public.season_players player
      on player.id = participant.season_player_id
    left join public.profiles profile
      on profile.id = player.profile_id
     and profile.status = 'active'
     and profile.notify_motm_vote
    left join public.guest_players guest
      on guest.id = participant.guest_player_id
    where result.match_id = p_match_id
      and result.is_winner
  ) winner;

  -- Aucun vote gagnant : personne n'est annoncé comme élu.
  if v_winner_count = 0 then
    return jsonb_build_object(
      'general_profile_ids', '[]'::jsonb,
      'winner_profile_ids', '[]'::jsonb
    );
  end if;

  select coalesce(array_agg(distinct profile.id), array[]::uuid[])
  into v_general_profile_ids
  from private.match_motm_candidate_participants(p_match_id) candidate
  join public.match_sport_participants participant
    on participant.id = candidate.participant_id
  join public.season_players player
    on player.id = participant.season_player_id
  join public.profiles profile
    on profile.id = player.profile_id
  where profile.status = 'active'
    and profile.notify_motm_vote
    and not (profile.id = any(v_winner_profile_ids));

  if v_winner_count = 1 then
    v_general_title := 'Homme du match';
    v_general_message := format('%s a été élu Homme du match !', v_winner_names);
    v_winner_title := 'Homme du match';
    v_winner_message := 'Bravo, tu as été élu Homme du match !';
  else
    v_general_title := 'Co-Hommes du match';
    v_general_message := format(
      '%s ont été élus co-Hommes du match !',
      v_winner_names
    );
    v_winner_title := 'Co-Homme du match';
    v_winner_message := 'Bravo, tu as été élu co-Homme du match !';
  end if;

  return jsonb_build_object(
    'general_profile_ids', to_jsonb(v_general_profile_ids),
    'winner_profile_ids', to_jsonb(v_winner_profile_ids),
    'general_title', v_general_title,
    'general_message', v_general_message,
    'winner_title', v_winner_title,
    'winner_message', v_winner_message
  );
end;
$function$;

create or replace function private.dispatch_motm_result_notifications(
  p_match_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payload jsonb;
  v_token text;
  v_general_ids jsonb;
  v_winner_ids jsonb;
  v_request_id bigint;
  v_sent boolean := false;
begin
  if not private.is_feature_enabled('sports_management')
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  v_payload := private.match_motm_result_notification_payloads(p_match_id);
  v_general_ids := coalesce(v_payload -> 'general_profile_ids', '[]'::jsonb);
  v_winner_ids := coalesce(v_payload -> 'winner_profile_ids', '[]'::jsonb);

  if jsonb_array_length(v_general_ids) = 0
     and jsonb_array_length(v_winner_ids) = 0 then
    return false;
  end if;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return false;
  end if;

  -- Le canal `custom` de l'Edge Function est un transport interne protégé par
  -- x-push-token. Les textes et destinataires sont ici entièrement calculés par
  -- la base ; aucun utilisateur ne peut injecter ce contenu.
  if jsonb_array_length(v_general_ids) > 0 then
    select net.http_post(
      url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
      body := jsonb_build_object(
        'kind', 'custom',
        'profile_ids', v_general_ids,
        'title', v_payload ->> 'general_title',
        'message', v_payload ->> 'general_message'
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-token', v_token
      ),
      timeout_milliseconds := 10000
    ) into v_request_id;
    v_sent := v_sent or v_request_id is not null;
  end if;

  if jsonb_array_length(v_winner_ids) > 0 then
    select net.http_post(
      url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
      body := jsonb_build_object(
        'kind', 'custom',
        'profile_ids', v_winner_ids,
        'title', v_payload ->> 'winner_title',
        'message', v_payload ->> 'winner_message'
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-token', v_token
      ),
      timeout_milliseconds := 10000
    ) into v_request_id;
    v_sent := v_sent or v_request_id is not null;
  end if;

  return v_sent;
exception
  when others then
    return false;
end;
$function$;

create or replace function public.push_on_motm_election_closed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if private.is_feature_enabled('sports_management')
     and new.state = 'closed'
     and old.state is distinct from 'closed' then
    perform private.dispatch_motm_result_notifications(new.match_id);
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_push_on_motm_election_closed
  on public.match_sport_motm_elections;
create trigger trg_push_on_motm_election_closed
after update of state on public.match_sport_motm_elections
for each row execute function public.push_on_motm_election_closed();

revoke all on function private.match_motm_result_notification_payloads(uuid)
  from public, anon, authenticated;
revoke all on function private.dispatch_motm_result_notifications(uuid)
  from public, anon, authenticated;
revoke all on function public.push_on_motm_election_closed()
  from public, anon, authenticated;

grant execute on function private.match_motm_result_notification_payloads(uuid)
  to service_role;
grant execute on function private.dispatch_motm_result_notifications(uuid)
  to service_role;

comment on function private.match_motm_result_notification_payloads(uuid) is
  'Prépare les notifications de résultat HDM selon notify_motm_vote, en séparant élus et autres destinataires.';
comment on function private.dispatch_motm_result_notifications(uuid) is
  'Envoie le résultat HDM : annonce collective aux non-élus et félicitation personnalisée aux élus.';

commit;
