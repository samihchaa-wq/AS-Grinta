begin;

create or replace function private.request_match_weather_refresh(
  p_match_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_request_id bigint;
begin
  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return null;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := case
      when p_match_id is null then jsonb_build_object('kind', 'refresh_match_weather')
      else jsonb_build_object(
        'kind', 'refresh_match_weather',
        'match_id', p_match_id
      )
    end,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 30000
  ) into v_request_id;

  return v_request_id;
exception
  when others then
    return null;
end;
$function$;

revoke all on function private.request_match_weather_refresh(uuid)
  from public, anon, authenticated;
grant execute on function private.request_match_weather_refresh(uuid)
  to service_role;

commit;
