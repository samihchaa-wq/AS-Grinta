begin;

-- Le réglage utilisateur `notify_motm_vote` couvre désormais tout le cycle HDM :
-- ouverture du scrutin + résultat. Le résultat est séparé en deux destinataires
-- logiques afin que l'élu ne reçoive jamais aussi le message collectif.
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

  -- Aucun gagnant (par exemple aucun vote) : aucun push de résultat.
  if v_winner_count = 0 then
    return jsonb_build_object(
      'general_profile_ids', '[]'::jsonb,
      'winner_profile_ids', '[]'::jsonb
    );
  end if;

  -- Même population que l'ouverture du vote : joueurs candidats avec compte
  -- actif et préférence HDM activée. Les élus sont retirés du groupe collectif.
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

-- Le transport ciblé réutilise le canal interne `custom` de send-push. Ce canal
-- est protégé par x-push-token ; les destinataires et textes viennent uniquement
-- de la base et ne sont jamais fournis par un client.
create or replace function private.dispatch_motm_result_notification(
  p_kind text,
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
  v_profile_ids jsonb;
  v_title text;
  v_message text;
  v_request_id bigint;
begin
  if p_kind not in ('motm_result_general', 'motm_result_winner') then
    raise exception 'Unknown MOTM result notification kind' using errcode = '22023';
  end if;

  if not private.is_feature_enabled('sports_management')
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  v_payload := private.match_motm_result_notification_payloads(p_match_id);

  if p_kind = 'motm_result_general' then
    v_profile_ids := coalesce(v_payload -> 'general_profile_ids', '[]'::jsonb);
    v_title := v_payload ->> 'general_title';
    v_message := v_payload ->> 'general_message';
  else
    v_profile_ids := coalesce(v_payload -> 'winner_profile_ids', '[]'::jsonb);
    v_title := v_payload ->> 'winner_title';
    v_message := v_payload ->> 'winner_message';
  end if;

  -- Aucun destinataire est un état valide : on marque l'événement comme traité
  -- pour ne pas le réessayer indéfiniment (invité élu, préférence désactivée…).
  if jsonb_array_length(v_profile_ids) = 0 then
    return true;
  end if;

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
      'profile_ids', v_profile_ids,
      'title', v_title,
      'message', v_message
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception
  when others then
    return false;
end;
$function$;

-- Tente un envoi de manière sérialisée et n'écrit le marqueur anti-doublon
-- qu'après mise en file réussie. En cas de panne temporaire, le cron pourra
-- donc réessayer à la minute suivante.
create or replace function private.try_motm_result_notification(
  p_kind text,
  p_match_id uuid,
  p_sent_at timestamptz default now()
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_kind not in ('motm_result_general', 'motm_result_winner') then
    raise exception 'Unknown MOTM result notification kind' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_match_id::text || ':' || p_kind, 0)
  );

  if exists (
    select 1
    from public.push_notification_log log
    where log.match_id = p_match_id
      and log.kind = p_kind
  ) then
    return false;
  end if;

  if not private.dispatch_motm_result_notification(p_kind, p_match_id) then
    return false;
  end if;

  insert into public.push_notification_log(match_id, kind, sent_at)
  values (p_match_id, p_kind, p_sent_at)
  on conflict do nothing;

  return found;
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
    perform private.try_motm_result_notification(
      'motm_result_general',
      new.match_id,
      now()
    );
    perform private.try_motm_result_notification(
      'motm_result_winner',
      new.match_id,
      now()
    );
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_push_on_motm_election_closed
  on public.match_sport_motm_elections;
create trigger trg_push_on_motm_election_closed
after update of state on public.match_sport_motm_elections
for each row execute function public.push_on_motm_election_closed();

-- Si le staff relance un scrutin fermé, le nouveau cycle doit pouvoir produire
-- un nouveau résultat. On efface donc aussi les deux marqueurs de résultat.
create or replace function public.push_on_motm_election_opened()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_is_new_window boolean := false;
begin
  if not private.is_feature_enabled('sports_management') then
    return new;
  end if;

  if new.state = 'open' then
    if tg_op = 'INSERT' then
      v_is_new_window := true;
    else
      v_is_new_window := old.state is distinct from 'open'
        or old.opens_at is distinct from new.opens_at
        or old.closes_at is distinct from new.closes_at
        or old.finalization_version is distinct from new.finalization_version;
    end if;
  end if;

  if v_is_new_window then
    delete from public.push_notification_log
    where match_id = new.match_id
      and kind in (
        'motm_open',
        'motm_result_general',
        'motm_result_winner'
      );

    if not private.is_feature_enabled('notifications_paused') then
      insert into public.push_notification_log(match_id, kind, sent_at)
      values (new.match_id, 'motm_open', now())
      on conflict do nothing;
      if found then
        perform private.dispatch_motm_push('motm_open', new.match_id);
      end if;
    end if;
  end if;

  return new;
end;
$function$;

-- Rattrapage des résultats dont le push n'a pas pu être mis en file au moment
-- exact de la clôture. La fenêtre de 30 jours évite de ressusciter l'historique.
create or replace function private.push_due_motm_result_notifications(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row record;
  v_sent integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return 0;
  end if;

  for v_row in
    select election.match_id
    from public.match_sport_motm_elections election
    where election.state = 'closed'
      and election.closed_at is not null
      and election.closed_at >= p_now - interval '30 days'
      and (
        not exists (
          select 1 from public.push_notification_log log
          where log.match_id = election.match_id
            and log.kind = 'motm_result_general'
        )
        or not exists (
          select 1 from public.push_notification_log log
          where log.match_id = election.match_id
            and log.kind = 'motm_result_winner'
        )
      )
    order by election.closed_at, election.match_id
  loop
    if private.try_motm_result_notification(
      'motm_result_general',
      v_row.match_id,
      p_now
    ) then
      v_sent := v_sent + 1;
    end if;
    if private.try_motm_result_notification(
      'motm_result_winner',
      v_row.match_id,
      p_now
    ) then
      v_sent := v_sent + 1;
    end if;
  end loop;

  return v_sent;
end;
$function$;

-- Le cron HDM existant gère désormais aussi le rattrapage du résultat.
create or replace function private.process_match_motm_jobs(
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_transitions integer;
  v_open_notifications integer;
  v_result_notifications integer;
begin
  v_transitions := private.close_due_match_motm_elections();
  v_open_notifications := private.push_due_motm_open_notifications(p_now);
  v_result_notifications := private.push_due_motm_result_notifications(p_now);

  return jsonb_build_object(
    'transitions', v_transitions,
    'open_notifications', v_open_notifications,
    'result_notifications', v_result_notifications
  );
end;
$function$;

-- Deux nouveaux marqueurs internes ; les anciens `motm_results` et
-- `motm_reminder` restent retirés du produit et de ce contrat.
alter table public.push_notification_log
  drop constraint if exists push_notification_log_kind_check;
alter table public.push_notification_log
  add constraint push_notification_log_kind_check check (kind = any(array[
    'motm_open'::text,
    'motm_result_general'::text,
    'motm_result_winner'::text,
    'prediction_j5'::text,
    'match_cancelled'::text,
    'match_rescheduled_date'::text,
    'match_rescheduled_time'::text
  ])) not valid;

revoke all on function private.match_motm_result_notification_payloads(uuid)
  from public, anon, authenticated;
revoke all on function private.dispatch_motm_result_notification(text, uuid)
  from public, anon, authenticated;
revoke all on function private.try_motm_result_notification(text, uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function private.push_due_motm_result_notifications(timestamptz)
  from public, anon, authenticated;
revoke all on function public.push_on_motm_election_closed()
  from public, anon, authenticated;
revoke all on function public.push_on_motm_election_opened()
  from public, anon, authenticated;

comment on function private.match_motm_result_notification_payloads(uuid) is
  'Prépare les notifications de résultat HDM selon notify_motm_vote, en séparant élus et autres destinataires.';
comment on function private.dispatch_motm_result_notification(text, uuid) is
  'Met en file un push ciblé de résultat HDM via le transport interne sécurisé.';
comment on function private.push_due_motm_result_notifications(timestamptz) is
  'Réessaie les notifications de résultat HDM non mises en file à la clôture.';

commit;
