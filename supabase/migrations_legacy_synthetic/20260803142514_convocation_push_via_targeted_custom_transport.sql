create or replace function private.dispatch_convocation_push(
  p_match_id uuid,
  p_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_request_id bigint;
  v_title text := 'Tu es convoqué';
  v_body text;
  v_match record;
begin
  if p_profile_id is null
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  select
    m.kickoff_at,
    coalesce(o.name, 'Match entre nous') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found or v_match.kickoff_at is null then
    return false;
  end if;

  v_body := format(
    'Tu es convoqué pour le match du %s contre %s.',
    to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM'),
    v_match.opponent_name
  );

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
      'profile_ids', jsonb_build_array(p_profile_id),
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
