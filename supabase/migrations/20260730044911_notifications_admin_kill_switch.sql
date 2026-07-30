-- Coupe-circuit admin : suspend l'envoi de TOUTES les notifications push
-- (y compris le test) le temps d'une phase de tests, sans toucher aux
-- préférences individuelles des joueurs.
insert into private.app_feature_flags (key, enabled, config, updated_at, updated_by)
values ('notifications_paused', false, '{}'::jsonb, now(), null)
on conflict (key) do nothing;

create or replace function private.set_notifications_paused(
  p_enabled boolean,
  p_justification text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_old_enabled boolean;
  v_updated_at timestamptz;
  v_justification text := nullif(btrim(p_justification), '');
begin
  if p_enabled is null then
    raise exception 'Feature flag value is required' using errcode = '22023';
  end if;

  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if v_justification is not null and char_length(v_justification) > 500 then
    raise exception 'Justification cannot exceed 500 characters'
      using errcode = '22023';
  end if;

  select f.enabled
  into v_old_enabled
  from private.app_feature_flags f
  where f.key = 'notifications_paused'
  for update;

  if not found then
    raise exception 'Notifications kill switch flag is missing'
      using errcode = 'P0002';
  end if;

  if v_old_enabled is distinct from p_enabled then
    update private.app_feature_flags f
    set enabled = p_enabled,
        updated_at = now(),
        updated_by = (select auth.uid())
    where f.key = 'notifications_paused'
    returning f.updated_at into v_updated_at;

    insert into private.app_feature_flag_audit (
      feature_key, old_enabled, new_enabled, actor_profile_id, justification
    )
    values (
      'notifications_paused', v_old_enabled, p_enabled,
      (select auth.uid()), v_justification
    );
  else
    select f.updated_at into v_updated_at
    from private.app_feature_flags f
    where f.key = 'notifications_paused';
  end if;

  return jsonb_build_object(
    'notifications_paused',
    jsonb_build_object(
      'enabled', p_enabled,
      'updated_at', v_updated_at,
      'changed', v_old_enabled is distinct from p_enabled
    )
  );
end;
$function$;

create or replace function private.get_notifications_paused()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'notifications_paused',
    jsonb_build_object('enabled', f.enabled, 'updated_at', f.updated_at)
  )
  from private.app_feature_flags f
  where f.key = 'notifications_paused';
$function$;

create or replace function public.admin_get_notifications_paused()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.get_notifications_paused();
end;
$function$;

create or replace function public.admin_set_notifications_paused(
  p_enabled boolean,
  p_justification text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.set_notifications_paused(p_enabled, p_justification);
$$;

-- Le point de passage unique de tous les envois push (canal de test compris)
-- expose désormais aussi l'état du coupe-circuit, pour que l'edge function
-- puisse tout court-circuiter en un seul aller-retour.
create or replace function public.internal_push_config()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'vapid_public', max(decrypted_secret) filter (where name = 'push_vapid_public'),
    'vapid_private', max(decrypted_secret) filter (where name = 'push_vapid_private'),
    'token', max(decrypted_secret) filter (where name = 'push_internal_token'),
    'notifications_paused', private.is_feature_enabled('notifications_paused')
  )
  from vault.decrypted_secrets
  where name in ('push_vapid_public', 'push_vapid_private', 'push_internal_token');
$function$;

revoke execute on function private.set_notifications_paused(boolean, text)
  from public, anon;
revoke execute on function private.get_notifications_paused()
  from public, anon;
revoke execute on function public.admin_get_notifications_paused()
  from public, anon;
revoke execute on function public.admin_set_notifications_paused(boolean, text)
  from public, anon;

grant execute on function private.set_notifications_paused(boolean, text)
  to authenticated, service_role;
grant execute on function private.get_notifications_paused()
  to authenticated, service_role;
grant execute on function public.admin_get_notifications_paused()
  to authenticated;
grant execute on function public.admin_set_notifications_paused(boolean, text)
  to authenticated;

comment on function public.admin_get_notifications_paused() is
  'Admin-only read of the global notifications kill switch state.';
comment on function public.admin_set_notifications_paused(boolean, text) is
  'Admin-only toggle to pause every outgoing push notification (including the test channel), with audit.';
