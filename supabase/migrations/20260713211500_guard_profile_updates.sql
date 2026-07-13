-- P0 defense in depth for profile updates.
-- A normal authenticated user may only change explicitly allow-listed fields.
-- Staff operations continue through the existing checked RPCs, while trusted
-- server/database operations (no end-user JWT) remain possible.

create or replace function public.guard_sensitive_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  old_protected jsonb;
  new_protected jsonb;
begin
  -- Trusted database and service-role workflows do not carry an end-user UID.
  if actor_id is null then
    return new;
  end if;

  -- Staff changes are already constrained by the dedicated administration RPCs.
  if public.is_match_staff() then
    return new;
  end if;

  -- A standard user must never update another profile, even if a policy or
  -- future grant is accidentally loosened.
  if actor_id is distinct from old.id then
    raise exception 'Un utilisateur ne peut modifier que son propre profil.'
      using errcode = '42501';
  end if;

  -- Remove the fields a normal user is legitimately allowed to change. Any
  -- difference left in the JSON objects is a sensitive or unknown column.
  old_protected := to_jsonb(old) - array[
    'first_name',
    'last_name',
    'updated_at',
    'notify_prediction_open',
    'notify_prediction_reminders',
    'notify_match_reminders',
    'password_set',
    'must_change_password'
  ];

  new_protected := to_jsonb(new) - array[
    'first_name',
    'last_name',
    'updated_at',
    'notify_prediction_open',
    'notify_prediction_reminders',
    'notify_match_reminders',
    'password_set',
    'must_change_password'
  ];

  if new_protected is distinct from old_protected then
    raise exception 'Les champs sensibles du profil ne peuvent pas être modifiés.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke execute on function public.guard_sensitive_profile_fields()
  from public, anon, authenticated;

grant execute on function public.guard_sensitive_profile_fields()
  to service_role;
