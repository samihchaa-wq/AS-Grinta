-- Canal de test sûr : l'admin peut s'envoyer à lui-même une notification de
-- test pour vérifier que les notifications fonctionnent, sans déranger l'équipe.
create or replace function public.admin_send_test_push()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
  v_actor uuid := (select auth.uid());
begin
  if not public.is_admin() then
    raise exception 'Admin required' using errcode = '42501';
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

revoke all on function public.admin_send_test_push() from public, anon;
grant execute on function public.admin_send_test_push() to authenticated;
