-- Bug 45 : « Test envoyé — regarde tes notifications. » est structurellement
-- optimiste.
--
-- send_test_push() poste en asynchrone (net.http_post) sans verifier ni le
-- coupe-circuit `notifications_paused`, ni l'existence d'un abonnement push
-- pour le compte appelant. L'application annoncait donc un succes meme quand
-- rien ne pouvait partir — exactement le cas de l'audit, mene avec les
-- notifications en pause depuis le 02/08.
--
-- La fonction renvoie desormais l'etat reellement constate, ce que
-- l'application affiche a l'utilisateur.

begin;

drop function if exists public.send_test_push();

create or replace function public.send_test_push()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_actor uuid := (select auth.uid());
  v_subscriptions integer;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select count(*)
  into v_subscriptions
  from public.push_subscriptions subscription
  where subscription.profile_id = v_actor;

  if v_subscriptions = 0 then
    return jsonb_build_object(
      'sent', false,
      'reason', 'no_subscription'
    );
  end if;

  -- get_notifications_paused() renvoie un jsonb
  -- {"notifications_paused": {"enabled": …}} ; absence de drapeau = actif.
  if coalesce(
       (private.get_notifications_paused()
          #>> '{notifications_paused,enabled}')::boolean,
       false
     ) then
    return jsonb_build_object(
      'sent', false,
      'reason', 'notifications_paused'
    );
  end if;

  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name = 'push_internal_token';

  if v_token is null then
    return jsonb_build_object(
      'sent', false,
      'reason', 'not_configured'
    );
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

  -- L'envoi est asynchrone : on confirme la remise au service d'envoi, pas la
  -- reception sur l'appareil.
  return jsonb_build_object(
    'sent', true,
    'subscriptions', v_subscriptions
  );
end;
$function$;

comment on function public.send_test_push() is
  'Envoie une notification de test au compte appelant. Renvoie {sent, reason} : l abonnement et le coupe-circuit notifications_paused sont verifies avant tout envoi.';

revoke all on function public.send_test_push() from public, anon;
grant execute on function public.send_test_push() to authenticated, service_role;

commit;
