-- Simplification des droits applicatifs : deux niveaux uniquement.
--
-- - pronostiqueur : utilisateur standard ;
-- - admin          : tous les droits d'administration.
--
-- Les anciennes migrations restent immuables. Les fonctions `is_moderator`
-- sont conservées temporairement comme alias de compatibilité pour les anciens
-- clients, mais il n'existe plus de valeur de rôle `moderateur` en production.

-- 1. Convertir les anciens modérateurs avant de resserrer la contrainte.
update public.profiles
set role = 'admin',
    updated_at = now()
where role = 'moderateur';

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('pronostiqueur', 'admin'));

-- 2. Source de vérité des droits : seul un profil admin actif est privilégié.
create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.status = 'active'
  );
$function$;

revoke execute on function private.is_admin() from public, anon;
grant execute on function private.is_admin() to authenticated, service_role;

-- Alias de compatibilité : les anciens clients qui interrogent encore ce RPC
-- voient les admins comme privilégiés. Aucun rôle « moderateur » n'est recréé.
create or replace function public.is_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.status = 'active'
  );
$function$;

create or replace function private.is_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$ select private.is_admin(); $function$;

revoke execute on function public.is_moderator() from public, anon;
grant execute on function public.is_moderator() to authenticated, service_role;
revoke execute on function private.is_moderator() from public, anon;
grant execute on function private.is_moderator() to authenticated, service_role;

comment on function public.is_moderator() is
  'Deprecated compatibility alias. Returns true for an active admin.';

-- 3. Tous les admins peuvent gérer les comptes et attribuer les deux rôles.
-- L'auto-modification du rôle/statut reste interdite pour éviter de se retirer
-- accidentellement ses propres droits en cours de session.
create or replace function public.admin_update_profile_fields(
  p_profile_id uuid,
  p_role text,
  p_status text,
  p_is_goalkeeper boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id uuid := (select auth.uid());
  current_row public.profiles%rowtype;
  resulting_role text;
  resulting_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_profile_id is null then
    raise exception 'Profile id is required' using errcode = '22023';
  end if;
  if p_profile_id = '00000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'Protected technical account' using errcode = '42501';
  end if;

  select *
  into current_row
  from public.profiles
  where id = p_profile_id
  for update;

  if not found then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;
  if p_role is not null and p_role not in ('pronostiqueur', 'admin') then
    raise exception 'Invalid role' using errcode = '22023';
  end if;
  if p_status is not null and p_status not in ('pending', 'active', 'archived') then
    raise exception 'Invalid status' using errcode = '22023';
  end if;
  if p_profile_id = actor_id and (p_role is not null or p_status is not null) then
    raise exception 'An administrator cannot change their own role or status here' using errcode = '42501';
  end if;

  resulting_role := coalesce(p_role, current_row.role::text);
  resulting_status := coalesce(p_status, current_row.status::text);

  update public.profiles
  set role = resulting_role,
      status = resulting_status,
      is_goalkeeper = coalesce(p_is_goalkeeper, is_goalkeeper),
      updated_at = now()
  where id = p_profile_id;

  return true;
end;
$function$;

revoke all on function public.admin_update_profile_fields(uuid,text,text,boolean)
  from public, anon;
grant execute on function public.admin_update_profile_fields(uuid,text,text,boolean)
  to authenticated, service_role;

-- 4. La liste d'attente choisit désormais uniquement un admin actif comme
-- acteur de repli. On patch la fonction existante sans la réécrire en entier.
do $patch$
declare
  v_def text := pg_get_functiondef(
    'private.ensure_sport_waitlist(uuid, uuid)'::regprocedure
  );
  v_old constant text := 'profile.role in (''admin'', ''moderateur'')';
  v_new constant text := 'profile.role = ''admin''';
begin
  if position(v_old in v_def) > 0 then
    execute replace(v_def, v_old, v_new);
  elsif position(v_new in v_def) = 0 then
    raise exception 'ensure_sport_waitlist: condition de rôle introuvable';
  end if;
end
$patch$;

-- 5. Les nouvelles inscriptions préviennent tous les admins actifs.
create or replace function private.notify_admins_of_pending_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token text;
  v_admin_ids uuid[];
  v_display_name text;
begin
  begin
    select array_agg(p.id)
    into v_admin_ids
    from public.profiles p
    where p.role = 'admin' and p.status = 'active';

    if v_admin_ids is null or array_length(v_admin_ids, 1) = 0 then
      return new;
    end if;

    select decrypted_secret into v_token
    from vault.decrypted_secrets
    where name = 'push_internal_token';

    if v_token is null then
      return new;
    end if;

    v_display_name := nullif(
      btrim(concat_ws(' ', new.first_name, new.last_name)),
      ''
    );

    perform net.http_post(
      url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
      body := jsonb_build_object(
        'kind', 'admin_pending_signup',
        'profile_ids', to_jsonb(v_admin_ids),
        'display_name', coalesce(v_display_name, 'Un joueur')
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-token', v_token
      ),
      timeout_milliseconds := 10000
    );
  exception when others then
    raise warning 'notify_admins_of_pending_signup failed: %', sqlerrm;
  end;

  return new;
end;
$function$;
