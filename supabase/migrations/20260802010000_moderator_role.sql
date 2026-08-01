-- Deux rôles privilégiés : « admin » et « modérateur ».
--
-- Jusqu'ici il n'existait qu'un seul rôle privilégié. Pour pouvoir confier
-- l'application à quelqu'un sans lui ouvrir la gestion des comptes et des
-- saisons, on sépare :
--
--   * admin       : tous les droits de gestion sportive d'avant, mais le
--                   module « Modérateur » des paramètres lui est masqué ;
--   * modérateur  : exactement les mêmes droits, plus ce module.
--
-- Côté base, les deux rôles sont donc équivalents : private.is_admin() répond
-- vrai pour les deux, et toutes les RPC existantes continuent de fonctionner à
-- l'identique. La seule règle propre au modérateur vit dans
-- admin_update_profile_fields : distribuer ou retirer le rôle de modérateur
-- est réservé à un modérateur, sinon un admin pourrait se hisser au niveau
-- au-dessus en passant par un complice.
--
-- Les administrateurs actuels deviennent modérateurs : ils gardent l'accès
-- qu'ils avaient avant cette migration.

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('pronostiqueur', 'admin', 'moderateur'));

-- Seuls les comptes actifs sont promus : le compte technique d'import est
-- archivé et protégé, le promouvoir n'aurait aucun effet utile.
update public.profiles
set role = 'moderateur'
where role = 'admin' and status = 'active';

-- Le garde historique : « admin » couvre désormais les deux rôles privilégiés,
-- ce qui laisse toutes les autorisations existantes inchangées.
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
      and p.role in ('admin', 'moderateur')
      and p.status = 'active'
  );
$function$;

-- Écrit sans passer par un wrapper privé : le test de sécurité du dépôt exige
-- qu'une fonction SECURITY DEFINER exposée aux comptes connectés porte
-- elle-même un garde reconnu, ici l'appel à auth.uid().
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
      and p.role = 'moderateur'
      and p.status = 'active'
  );
$function$;

create or replace function private.is_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$ select public.is_moderator(); $function$;

revoke execute on function public.is_moderator() from public, anon;
grant execute on function public.is_moderator() to authenticated, service_role;
revoke execute on function private.is_moderator() from public, anon;
grant execute on function private.is_moderator() to authenticated, service_role;

comment on function public.is_moderator() is
  'True when the caller is an active moderator (admin plus the settings module).';

-- Le rôle de modérateur ne se distribue qu'entre modérateurs, et le dernier
-- d'entre eux ne peut pas disparaître : sans modérateur actif, plus personne
-- ne pourrait redistribuer les rôles.
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
as $$
declare
  actor_id uuid := (select auth.uid());
  current_row public.profiles%rowtype;
  resulting_role text;
  resulting_status text;
  active_moderators integer;
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
  if p_role is not null and p_role not in ('pronostiqueur', 'admin', 'moderateur') then
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

  if (resulting_role = 'moderateur') is distinct from (current_row.role::text = 'moderateur')
     and not public.is_moderator() then
    raise exception 'Only a moderator can grant or revoke the moderator role' using errcode = '42501';
  end if;

  if current_row.role::text = 'moderateur' and current_row.status::text = 'active'
     and (resulting_role <> 'moderateur' or resulting_status <> 'active') then
    select count(*)
    into active_moderators
    from public.profiles
    where role = 'moderateur' and status = 'active';

    if active_moderators <= 1 then
      raise exception 'The last active moderator cannot be removed or archived' using errcode = '23514';
    end if;
  end if;

  update public.profiles
  set role = resulting_role,
      status = resulting_status,
      is_goalkeeper = coalesce(p_is_goalkeeper, is_goalkeeper),
      updated_at = now()
  where id = p_profile_id;

  return true;
end;
$$;

revoke all on function public.admin_update_profile_fields(uuid,text,text,boolean)
  from public, anon;
grant execute on function public.admin_update_profile_fields(uuid,text,text,boolean)
  to authenticated, service_role;

-- ensure_sport_waitlist cherche un acteur de repli par sa colonne role. Elle
-- est longue et a déjà divergé du dépôt par le passé : on la corrige donc par
-- remplacement ciblé de la condition, sans réécrire le reste du corps. Le
-- bloc est idempotent et échoue bruyamment si le motif attendu a disparu.
do $patch$
declare
  v_def text := pg_get_functiondef('private.ensure_sport_waitlist(uuid, uuid)'::regprocedure);
  -- Le motif couvre les deux occurrences (test de l'acteur passé, puis
  -- recherche du plus ancien privilégié comme repli).
  v_old constant text := 'profile.role = ''admin''';
  v_new constant text := 'profile.role in (''admin'', ''moderateur'')';
begin
  if position(v_new in v_def) > 0 then
    return; -- déjà corrigée
  end if;
  if position(v_old in v_def) = 0 then
    raise exception 'ensure_sport_waitlist: condition de rôle introuvable, correction manuelle requise';
  end if;
  execute replace(v_def, v_old, v_new);
end
$patch$;

-- L'alerte d'inscription doit atteindre les deux rôles privilégiés, sans quoi
-- une base dont tous les privilégiés sont modérateurs n'aurait plus aucun
-- destinataire.
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
  -- Une notification ratée ne doit jamais faire échouer une inscription
  -- réelle : toute erreur ici est avalée silencieusement.
  begin
    select array_agg(p.id)
    into v_admin_ids
    from public.profiles p
    where p.role in ('admin', 'moderateur') and p.status = 'active';

    if v_admin_ids is null or array_length(v_admin_ids, 1) = 0 then
      return new;
    end if;

    select decrypted_secret into v_token
    from vault.decrypted_secrets
    where name = 'push_internal_token';

    if v_token is null then
      return new;
    end if;

    v_display_name := nullif(btrim(concat_ws(' ', new.first_name, new.last_name)), '');

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
