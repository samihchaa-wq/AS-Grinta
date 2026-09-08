-- Prévenir les administrateurs lorsqu'un joueur corrige sa disponibilité :
-- Présent -> Absent ou Absent -> Présent.
--
-- L'envoi est déclenché côté base après un vrai changement de statut. Ainsi,
-- un double clic, une relecture après timeout ou une nouvelle soumission de la
-- même valeur ne peut pas générer une notification supplémentaire.

create or replace function private.admin_availability_change_message(
  p_display_name text,
  p_old_status text,
  p_new_status text,
  p_changed_at timestamptz
)
returns text
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_old_label text;
  v_new_label text;
  v_name text := coalesce(nullif(btrim(p_display_name), ''), 'Un joueur');
begin
  if p_old_status not in ('available', 'absent')
     or p_new_status not in ('available', 'absent')
     or p_old_status = p_new_status then
    return null;
  end if;

  v_old_label := case p_old_status
    when 'available' then 'présent'
    else 'absent'
  end;
  v_new_label := case p_new_status
    when 'available' then 'présent'
    else 'absent'
  end;

  return format(
    '%s est passé de %s à %s à %s.',
    v_name,
    v_old_label,
    v_new_label,
    to_char(coalesce(p_changed_at, now()) at time zone 'Europe/Paris', 'HH24"h"MI')
  );
end;
$function$;

comment on function private.admin_availability_change_message(text, text, text, timestamptz) is
  'Formate l''alerte admin lors d''un changement joueur Présent <-> Absent.';

create or replace function private.notify_admin_player_availability_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_player_profile_id uuid;
  v_display_name text;
  v_admin_profile_ids uuid[];
  v_message text;
  v_token text;
  v_request_id bigint;
begin
  -- Seules les corrections entre les deux réponses explicites intéressent le
  -- staff. La première réponse no_response -> présent/absent reste silencieuse.
  if old.availability_status is not distinct from new.availability_status
     or old.availability_status::text not in ('available', 'absent')
     or new.availability_status::text not in ('available', 'absent') then
    return new;
  end if;

  if new.season_player_id is null or new.availability_updated_by is null then
    return new;
  end if;

  -- Une correction faite par un admin ne doit pas renvoyer une alerte aux
  -- admins. On ne notifie que lorsqu'il s'agit bien de la réponse du joueur
  -- lui-même : availability_updated_by = profil lié au season_player.
  select
    player.profile_id,
    coalesce(
      nullif(btrim(profile.surnom), ''),
      nullif(btrim(profile.first_name), ''),
      nullif(btrim(player.first_name), ''),
      'Un joueur'
    )
  into v_player_profile_id, v_display_name
  from public.season_players player
  left join public.profiles profile on profile.id = player.profile_id
  where player.id = new.season_player_id;

  if v_player_profile_id is null
     or v_player_profile_id is distinct from new.availability_updated_by
     or not exists (
       select 1
       from public.profiles actor
       where actor.id = v_player_profile_id
         and actor.status = 'active'
     ) then
    return new;
  end if;

  select array_agg(profile.id order by profile.id)
  into v_admin_profile_ids
  from public.profiles profile
  where profile.role = 'admin'
    and profile.status = 'active';

  if v_admin_profile_ids is null or cardinality(v_admin_profile_ids) = 0 then
    return new;
  end if;

  v_message := private.admin_availability_change_message(
    v_display_name,
    old.availability_status::text,
    new.availability_status::text,
    coalesce(new.availability_updated_at, now())
  );
  if v_message is null then
    return new;
  end if;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return new;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', to_jsonb(v_admin_profile_ids),
      'title', 'Changement de disponibilité',
      'message', v_message
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return new;
exception when others then
  -- Une panne du canal push ne doit jamais empêcher le joueur d'enregistrer
  -- sa disponibilité.
  return new;
end;
$function$;

comment on function private.notify_admin_player_availability_change() is
  'Trigger interne : notifie les admins actifs après un changement joueur Présent <-> Absent.';

revoke all on function private.admin_availability_change_message(text, text, text, timestamptz)
  from public, anon, authenticated;
revoke all on function private.notify_admin_player_availability_change()
  from public, anon, authenticated;

drop trigger if exists notify_admin_player_availability_change
  on public.match_sport_participants;

create trigger notify_admin_player_availability_change
after update of availability_status on public.match_sport_participants
for each row
when (old.availability_status is distinct from new.availability_status)
execute function private.notify_admin_player_availability_change();
