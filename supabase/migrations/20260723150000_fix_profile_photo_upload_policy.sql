-- Correctif : l'upload d'une photo de profil échouait systématiquement
-- (HTTP 400 « permission denied »), donc aucune photo ne pouvait être
-- enregistrée. Deux causes cumulées :
--
-- 1) La policy `profile_photos_admin_write` sur storage.objects lisait
--    directement la table public.profiles (EXISTS (SELECT ... FROM profiles)).
--    Évaluée à chaque insertion dans le bucket, cette lecture levait
--    « permission denied for table profiles » dans le contexte storage et
--    faisait échouer TOUTES les insertions (même celles couvertes par la
--    policy propriétaire). On la réécrit via la fonction SECURITY DEFINER
--    public.is_admin(), comme le fait déjà le bucket badge-images avec
--    is_match_staff().
--
-- 2) L'EXECUTE sur les helpers public.is_admin()/public.is_match_staff()
--    avait été révoqué pour le rôle authenticated (durcissement RPC), alors
--    que les policies storage les appellent en tant qu'authenticated. On
--    rétablit l'EXECUTE pour ces deux fonctions.
--
-- De plus, le client Flutter Web n'envoie pas toujours l'en-tête
-- Content-Type image/jpeg et n'applique pas le redimensionnement : on rend le
-- bucket profile-photos permissif (type et taille) pour fiabiliser l'upload.

grant execute on function public.is_admin() to authenticated, anon;
grant execute on function public.is_match_staff() to authenticated, anon;

drop policy if exists profile_photos_admin_write on storage.objects;
create policy profile_photos_admin_write on storage.objects
  for all to authenticated
  using (bucket_id = 'profile-photos' and public.is_admin())
  with check (bucket_id = 'profile-photos' and public.is_admin());

update storage.buckets
set allowed_mime_types = null,
    file_size_limit = null
where id = 'profile-photos';
