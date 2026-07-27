begin;

-- Aucun parcours applicatif n'est accessible avec le rôle anonyme. L'inscription
-- publique passe exclusivement par la fonction Edge register-account, qui utilise
-- le service_role après limitation de débit et validation des entrées.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;

-- PostgreSQL accorde EXECUTE à PUBLIC par défaut lors de la création d'une
-- fonction. On retire ce droit par défaut sur les schémas applicatifs, puis on
-- rétablit uniquement les appels explicitement nécessaires.
revoke execute on all functions in schema public from public;
revoke execute on all functions in schema private from public, anon;

grant execute on function private.save_match_effectif(
  uuid, integer, jsonb, text
) to authenticated, service_role;
grant execute on function public.admin_save_match_effectif(
  uuid, integer, jsonb, text
) to authenticated, service_role;

-- Un JWT Supabase valide ne suffit pas : toutes les tables applicatives imposent
-- désormais un profil actif. Les fonctions SECURITY DEFINER nécessaires au
-- chargement de l'état du compte (notamment get_my_profile) restent utilisables
-- pour qu'un compte en attente puisse être identifié puis déconnecté proprement.
do $block$
declare
  relation record;
begin
  for relation in
    select n.nspname as schema_name, c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
  loop
    execute format(
      'drop policy if exists active_authenticated_profile_only on %I.%I',
      relation.schema_name,
      relation.table_name
    );
    execute format(
      'create policy active_authenticated_profile_only on %I.%I '
      'as restrictive for all to authenticated '
      'using ((select private.is_active_profile())) '
      'with check ((select private.is_active_profile()))',
      relation.schema_name,
      relation.table_name
    );
  end loop;
end;
$block$;

-- Les photos restent publiquement lisibles par URL, mais l'écriture est limitée
-- à 5 Mo, aux formats réellement supportés et au dossier du propriétaire actif.
insert into storage.buckets(
  id, name, public, file_size_limit, allowed_mime_types
)
values
  (
    'profile-photos',
    'profile-photos',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
  ),
  (
    'badge-images',
    'badge-images',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
  )
on conflict(id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists profile_photos_owner_insert on storage.objects;
create policy profile_photos_owner_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'profile-photos'
  and (select private.is_active_profile())
  and owner_id = (select auth.uid())::text
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists profile_photos_owner_update on storage.objects;
create policy profile_photos_owner_update
on storage.objects for update to authenticated
using (
  bucket_id = 'profile-photos'
  and (select private.is_active_profile())
  and owner_id = (select auth.uid())::text
)
with check (
  bucket_id = 'profile-photos'
  and (select private.is_active_profile())
  and owner_id = (select auth.uid())::text
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists profile_photos_owner_delete on storage.objects;
create policy profile_photos_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'profile-photos'
  and (select private.is_active_profile())
  and owner_id = (select auth.uid())::text
);

drop policy if exists profile_photos_admin_write on storage.objects;
create policy profile_photos_admin_write
on storage.objects for all to authenticated
using (
  bucket_id = 'profile-photos'
  and (select private.is_admin())
)
with check (
  bucket_id = 'profile-photos'
  and (select private.is_admin())
);

drop policy if exists badge_images_admin_insert on storage.objects;
create policy badge_images_admin_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'badge-images'
  and (select private.is_match_staff())
);

drop policy if exists badge_images_admin_update on storage.objects;
create policy badge_images_admin_update
on storage.objects for update to authenticated
using (
  bucket_id = 'badge-images'
  and (select private.is_match_staff())
)
with check (
  bucket_id = 'badge-images'
  and (select private.is_match_staff())
);

drop policy if exists badge_images_admin_delete on storage.objects;
create policy badge_images_admin_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'badge-images'
  and (select private.is_match_staff())
);

-- Garde de migration : aucun droit anonyme ou implicite ne doit subsister sur
-- les fonctions applicatives après cette migration.
do $block$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(
      coalesce(p.proacl, acldefault('f', p.proowner))
    ) acl
    where n.nspname in ('public', 'private')
      and acl.privilege_type = 'EXECUTE'
      and (
        acl.grantee = 0
        or acl.grantee = (select oid from pg_roles where rolname = 'anon')
      )
  ) then
    raise exception 'Anonymous or PUBLIC function execution remains exposed';
  end if;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p', 'v', 'm', 'S')
      and (
        has_table_privilege('anon', c.oid, 'SELECT')
        or has_table_privilege('anon', c.oid, 'INSERT')
        or has_table_privilege('anon', c.oid, 'UPDATE')
        or has_table_privilege('anon', c.oid, 'DELETE')
      )
  ) then
    raise exception 'Anonymous table privileges remain exposed';
  end if;
end;
$block$;

commit;
