begin;

-- Le retour arrière retire les politiques actives globales et restaure les
-- politiques Storage précédentes. Les retraits de droits anonymes et PUBLIC ne
-- sont volontairement pas annulés : réexposer ces privilèges constituerait une
-- régression de sécurité. Les droits applicatifs explicites restent inchangés.
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
  end loop;
end;
$block$;

drop policy if exists profile_photos_owner_insert on storage.objects;
create policy profile_photos_owner_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'profile-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists profile_photos_owner_update on storage.objects;
create policy profile_photos_owner_update
on storage.objects for update to authenticated
using (
  bucket_id = 'profile-photos'
  and owner_id = (select auth.uid())::text
)
with check (
  bucket_id = 'profile-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists profile_photos_owner_delete on storage.objects;
create policy profile_photos_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'profile-photos'
  and owner_id = (select auth.uid())::text
);

drop policy if exists profile_photos_admin_write on storage.objects;
create policy profile_photos_admin_write
on storage.objects for all to authenticated
using (bucket_id = 'profile-photos' and public.is_admin())
with check (bucket_id = 'profile-photos' and public.is_admin());

drop policy if exists badge_images_admin_insert on storage.objects;
create policy badge_images_admin_insert
on storage.objects for insert to authenticated
with check (bucket_id = 'badge-images' and public.is_match_staff());

drop policy if exists badge_images_admin_update on storage.objects;
create policy badge_images_admin_update
on storage.objects for update to authenticated
using (bucket_id = 'badge-images' and public.is_match_staff())
with check (bucket_id = 'badge-images' and public.is_match_staff());

drop policy if exists badge_images_admin_delete on storage.objects;
create policy badge_images_admin_delete
on storage.objects for delete to authenticated
using (bucket_id = 'badge-images' and public.is_match_staff());

commit;
