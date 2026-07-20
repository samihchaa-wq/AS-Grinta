-- Notifications for the collective Man of the Match ballot.
-- Reuses the existing Web Push Edge Function and remains inert while the
-- sports-management feature flag is disabled.

alter table public.push_notification_log
  drop constraint if exists push_notification_log_kind_check;

alter table public.push_notification_log
  add constraint push_notification_log_kind_check check (
    kind in (
      'new_match',
      'closing_soon',
      'result_validated',
      'motm_open',
      'motm_reminder',
      'motm_results'
    )
  );

alter table public.push_delivery_log
  drop constraint if exists push_delivery_log_kind_check;

alter table public.push_delivery_log
  add constraint push_delivery_log_kind_check check (
    kind in (
      'new_match',
      'closing_soon',
      'result_validated',
      'availability_open',
      'availability_j3',
      'availability_j1',
      'availability_manual',
      'motm_open',
      'motm_reminder',
      'motm_results'
    )
  );

create or replace function public.internal_push_dispatch(
  p_kind text,
  p_match_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_match record;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_winner_names text;
  v_winner_count integer := 0;
  v_max_votes integer := 0;
begin
  select
    match.id,
    match.season_id,
    match.kickoff_at,
    match.score_as_grinta,
    match.score_adverse,
    opponent.name as opponent_name
  into v_match
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if p_kind in ('motm_open', 'motm_reminder', 'motm_results')
     and not private.is_feature_enabled('sports_management') then
    return jsonb_build_object(
      'payload', '{}'::jsonb,
      'subscriptions', '[]'::jsonb
    );
  end if;

  if p_kind = 'new_match' then
    v_payload := jsonb_build_object(
      'title', 'Nouveau match à pronostiquer',
      'body', format(
        'AS Grinta – %s le %s. Les pronostics sont ouverts !',
        v_match.opponent_name,
        to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM à HH24hMI')
      ),
      'url', '.',
      'tag', 'match-' || v_match.id || '-new'
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
      and profile.notify_prediction_reminders;

  elsif p_kind = 'closing_soon' then
    v_payload := jsonb_build_object(
      'title', 'Dernière chance de pronostiquer',
      'body', format(
        'AS Grinta – %s : les pronostics ferment à %s.',
        v_match.opponent_name,
        to_char((v_match.kickoff_at - interval '5 minutes') at time zone 'Europe/Paris', 'HH24hMI')
      ),
      'url', '.',
      'tag', 'match-' || v_match.id || '-closing'
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

  elsif p_kind = 'result_validated' then
    v_payload := jsonb_build_object(
      'title', 'Résultat validé',
      'body', format(
        'AS Grinta %s-%s %s. Découvre tes points et le classement !',
        coalesce(v_match.score_as_grinta::text, '?'),
        coalesce(v_match.score_adverse::text, '?'),
        v_match.opponent_name
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
    where profile.status = 'active'
      and profile.notify_match_reminders;

  elsif p_kind in ('motm_open', 'motm_reminder') then
    if not exists (
      select 1
      from public.match_sport_motm_elections election
      where election.match_id = p_match_id
        and election.state = 'open'
        and now() >= election.opens_at
        and now() < election.closes_at
    ) then
      return jsonb_build_object(
        'payload', '{}'::jsonb,
        'subscriptions', '[]'::jsonb
      );
    end if;

    v_payload := case p_kind
      when 'motm_open' then jsonb_build_object(
        'title', 'Vote Homme du match ouvert',
        'body', format(
          'AS Grinta – %s : vote avant le %s.',
          v_match.opponent_name,
          to_char(
            (select election.closes_at
             from public.match_sport_motm_elections election
             where election.match_id = p_match_id) at time zone 'Europe/Paris',
            'DD/MM à HH24hMI'
          )
        ),
        'url', 'matches/' || p_match_id || '/vote',
        'tag', 'sport-' || p_match_id || '-motm-open'
      )
      else jsonb_build_object(
        'title', 'Dernières heures pour voter',
        'body', format(
          'AS Grinta – %s : ton vote Homme du match n’est pas encore enregistré.',
          v_match.opponent_name
        ),
        'url', 'matches/' || p_match_id || '/vote',
        'tag', 'sport-' || p_match_id || '-motm-reminder'
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
      and profile.notify_match_reminders
      and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        join public.match_sport_motm_elections election
          on election.match_id = participant.match_id
        where participant.match_id = p_match_id
          and participant.final_presence_status = 'present'
          and player.profile_id = profile.id
          and election.state = 'open'
          and (
            p_kind = 'motm_open'
            or not exists (
              select 1
              from public.match_sport_motm_votes vote
              where vote.match_id = election.match_id
                and vote.voter_profile_id = profile.id
                and vote.finalization_version = election.finalization_version
            )
          )
      );

  elsif p_kind = 'motm_results' then
    select
      string_agg(winner.display_name, ', ' order by lower(winner.display_name)),
      count(*)::integer,
      coalesce(max(winner.votes_count), 0)::integer
    into v_winner_names, v_winner_count, v_max_votes
    from (
      select
        case
          when guest.id is not null then
            btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
          else btrim(concat_ws(' ', player.first_name, player.last_name))
        end as display_name,
        result.votes_count
      from public.match_sport_motm_results result
      join public.match_sport_participants participant
        on participant.id = result.participant_id
       and participant.match_id = result.match_id
      left join public.season_players player on player.id = participant.season_player_id
      left join public.guest_players guest on guest.id = participant.guest_player_id
      where result.match_id = p_match_id
        and result.is_winner
    ) winner;

    v_payload := jsonb_build_object(
      'title', case when v_winner_count > 1
        then 'Co-Hommes du match'
        else 'Homme du match'
      end,
      'body', case
        when v_winner_count = 0 then
          format('AS Grinta – %s : aucun Homme du match n’a été élu.', v_match.opponent_name)
        when v_winner_count = 1 then
          format('%s est élu Homme du match avec %s vote%s.',
            v_winner_names,
            v_max_votes,
            case when v_max_votes > 1 then 's' else '' end
          )
        else
          format('%s sont co-Hommes du match avec %s vote%s chacun.',
            v_winner_names,
            v_max_votes,
            case when v_max_votes > 1 then 's' else '' end
          )
      end,
      'url', 'matches/' || p_match_id || '/vote',
      'tag', 'sport-' || p_match_id || '-motm-results'
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
      and profile.notify_match_reminders
      and exists (
        select 1
        from public.season_players player
        where player.season_id = v_match.season_id
          and player.profile_id = profile.id
          and player.is_active
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

revoke all on function public.internal_push_dispatch(text, uuid)
  from public, anon, authenticated;
grant execute on function public.internal_push_dispatch(text, uuid)
  to service_role;

create or replace function private.dispatch_motm_push(
  p_kind text,
  p_match_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token text;
  v_request_id bigint;
begin
  if p_kind not in ('motm_open', 'motm_reminder', 'motm_results') then
    raise exception 'Unknown MOTM notification kind' using errcode = '22023';
  end if;

  if not private.is_feature_enabled('sports_management') then
    return false;
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
      'kind', p_kind,
      'match_id', p_match_id
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

revoke all on function private.dispatch_motm_push(text, uuid)
  from public, anon, authenticated;

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
      and kind in ('motm_open', 'motm_reminder', 'motm_results');

    insert into public.push_notification_log(match_id, kind)
    values (new.match_id, 'motm_open')
    on conflict do nothing;

    if found then
      perform private.dispatch_motm_push('motm_open', new.match_id);
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function public.push_on_motm_election_opened()
  from public, anon, authenticated;

drop trigger if exists trg_push_on_motm_election_opened
  on public.match_sport_motm_elections;
create trigger trg_push_on_motm_election_opened
after insert or update of state, opens_at, closes_at, finalization_version
on public.match_sport_motm_elections
for each row execute function public.push_on_motm_election_opened();

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
    insert into public.push_notification_log(match_id, kind)
    values (new.match_id, 'motm_results')
    on conflict do nothing;

    if found then
      perform private.dispatch_motm_push('motm_results', new.match_id);
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function public.push_on_motm_election_closed()
  from public, anon, authenticated;

drop trigger if exists trg_push_on_motm_election_closed
  on public.match_sport_motm_elections;
create trigger trg_push_on_motm_election_closed
after update of state on public.match_sport_motm_elections
for each row execute function public.push_on_motm_election_closed();

create or replace function private.push_due_motm_reminders(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_election record;
  v_sent integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return 0;
  end if;

  for v_election in
    select election.match_id, election.finalization_version
    from public.match_sport_motm_elections election
    where election.state = 'open'
      and election.closes_at > p_now
      and election.closes_at - interval '6 hours' <= p_now
      and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        join public.profiles profile on profile.id = player.profile_id
        where participant.match_id = election.match_id
          and participant.final_presence_status = 'present'
          and profile.status = 'active'
          and not exists (
            select 1
            from public.match_sport_motm_votes vote
            where vote.match_id = election.match_id
              and vote.voter_profile_id = profile.id
              and vote.finalization_version = election.finalization_version
          )
      )
    order by election.closes_at, election.match_id
    for update skip locked
  loop
    insert into public.push_notification_log(match_id, kind)
    values (v_election.match_id, 'motm_reminder')
    on conflict do nothing;

    if found then
      perform private.dispatch_motm_push('motm_reminder', v_election.match_id);
      v_sent := v_sent + 1;
    end if;
  end loop;

  return v_sent;
end;
$function$;

revoke all on function private.push_due_motm_reminders(timestamptz)
  from public, anon, authenticated;
grant execute on function private.push_due_motm_reminders(timestamptz)
  to service_role;

select cron.schedule(
  'sports-motm-push-reminders',
  '* * * * *',
  $$select private.push_due_motm_reminders();$$
);
