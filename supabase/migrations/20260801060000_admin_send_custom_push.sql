-- Notification libre : l'admin écrit son message et choisit ses
-- destinataires.
--
-- Jusqu'ici l'admin ne pouvait déclencher que des notifications
-- prédéfinies (convocations, homme du match…) ou un simple test à
-- lui-même. Cette RPC lui permet d'écrire un titre et un texte, et de
-- les envoyer aux profils qu'il désigne.
--
-- Les droits et la validation restent côté serveur : seul un admin peut
-- appeler la fonction, les destinataires doivent être des profils actifs,
-- et les longueurs sont bornées pour éviter une notification illisible.

create or replace function public.admin_send_custom_push(
  p_title text,
  p_body text,
  p_profile_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
  v_title text := nullif(btrim(p_title), '');
  v_body text := nullif(btrim(p_body), '');
  v_recipients uuid[];
  v_count integer;
begin
  if not public.is_admin() then
    raise exception 'Admin required' using errcode = '42501';
  end if;
  if v_title is null or v_body is null then
    raise exception 'Un titre et un message sont requis' using errcode = '22023';
  end if;
  if char_length(v_title) > 80 then
    raise exception 'Le titre ne peut pas dépasser 80 caractères'
      using errcode = '22023';
  end if;
  if char_length(v_body) > 300 then
    raise exception 'Le message ne peut pas dépasser 300 caractères'
      using errcode = '22023';
  end if;
  if p_profile_ids is null or array_length(p_profile_ids, 1) is null then
    raise exception 'Choisis au moins un destinataire' using errcode = '22023';
  end if;

  -- On ne garde que des profils actifs réellement existants.
  select coalesce(array_agg(profile.id), '{}'::uuid[])
  into v_recipients
  from public.profiles profile
  where profile.id = any(p_profile_ids)
    and profile.status = 'active';

  v_count := coalesce(array_length(v_recipients, 1), 0);
  if v_count = 0 then
    raise exception 'Aucun destinataire valide' using errcode = '22023';
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
      'kind', 'custom',
      'title', v_title,
      'message', v_body,
      'profile_ids', to_jsonb(v_recipients)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  );

  return v_count;
end;
$$;

revoke all on function public.admin_send_custom_push(text, text, uuid[])
  from public, anon;
grant execute on function public.admin_send_custom_push(text, text, uuid[])
  to authenticated;
