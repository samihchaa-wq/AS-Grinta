-- Le canal de test doit être accessible à tout joueur connecté, pas
-- seulement à l'admin, pour que chacun puisse vérifier ses propres
-- notifications sans dépendre de l'admin. La cible reste limitée à
-- l'appelant lui-même (aucun risque de spam vers les autres joueurs).
drop function if exists public.admin_send_test_push();

create function public.send_test_push()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name = 'push_internal_token';

  if v_token is null then
    raise exception 'Notifications push non configurées';
  end if;

  perform net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'test',
      'profile_ids', jsonb_build_array(v_actor)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  );
end;
$$;

revoke all on function public.send_test_push() from public, anon;
grant execute on function public.send_test_push() to authenticated;

comment on function public.send_test_push() is
  'Sends a test push notification to the calling user only; open to every authenticated player.';
