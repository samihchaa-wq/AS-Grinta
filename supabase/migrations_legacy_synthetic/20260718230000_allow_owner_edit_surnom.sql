-- Correctif : un utilisateur ne pouvait pas modifier son propre surnom.
-- Le garde-fou guard_sensitive_profile_fields traitait « surnom » comme un
-- champ sensible (non modifiable par le propriétaire). Or le surnom a été
-- réintroduit après la création de ce garde-fou. On l'ajoute donc à la liste
-- des champs qu'un utilisateur peut modifier sur son propre profil (au même
-- titre que first_name / last_name).
create or replace function public.guard_sensitive_profile_fields()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_id uuid := (select auth.uid());
  old_protected jsonb;
  new_protected jsonb;
begin
  if actor_id is null then
    return new;
  end if;

  if public.is_match_staff() then
    return new;
  end if;

  if actor_id is distinct from old.id then
    raise exception 'Un utilisateur ne peut modifier que son propre profil.'
      using errcode = '42501';
  end if;

  old_protected := to_jsonb(old) - array[
    'first_name',
    'last_name',
    'surnom',
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
    'surnom',
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
$function$;
