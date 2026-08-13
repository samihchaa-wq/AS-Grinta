-- Bug 6 : le bucket profile-photos est prive, mais les photo_url ecrites en
--         base etaient des URL publiques, qui repondent toutes
--         « Bucket not found ». L'application enregistre desormais le chemin
--         relatif et signe a l'affichage ; les lignes existantes sont
--         normalisees ici.
--
-- Bug 19 : le stockage fuit. Aucun nettoyage n'existe pour les visuels de
--          badges (22 orphelins, 11 Mo), et celui des photos ne couvre ni la
--          suppression ni l'archivage d'un compte.

begin;

-- ---------------------------------------------------------------------------
-- Bug 6 — normalisation des photo_url en chemin relatif
-- ---------------------------------------------------------------------------

-- Le trigger de nettoyage extrait le chemin a conserver du nouveau
-- photo_url. Avec un chemin relatif, l'ancien motif '/profile-photos/(.*)$'
-- ne correspondait plus et renvoyait NULL : le garde-fou
-- « name is distinct from v_keep » aurait alors supprime la photo qui vient
-- d'etre televersee. La normalisation ci-dessous doit donc etre precedee de la
-- mise a jour du trigger.
create or replace function private.profile_photo_storage_path(p_value text)
returns text
language sql
immutable
set search_path to ''
as $function$
  select case
    when nullif(btrim(p_value), '') is null then null
    -- URL complete, publique ou signee : on isole la partie apres le bucket.
    when position('/profile-photos/' in p_value) > 0
      then split_part(
             substring(p_value from position('/profile-photos/' in p_value) + 16),
             '?',
             1
           )
    -- Deja un chemin relatif.
    else ltrim(btrim(p_value), '/')
  end;
$function$;

comment on function private.profile_photo_storage_path(text) is
  'Chemin d objet dans le bucket profile-photos, que la valeur stockee soit une URL complete (heritage) ou un chemin relatif.';

-- Une fonction fraichement creee est executable par PUBLIC par defaut, ce que
-- le contrat security_surface_contract interdit pour toute fonction
-- applicative. Ce helper ne sert qu'aux declencheurs internes.
revoke all on function private.profile_photo_storage_path(text)
  from public, anon, authenticated;

create or replace function public.cleanup_replaced_photo()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_prefix text;
  v_keep text;
  v_archived boolean := false;
begin
  -- plpgsql planifie chaque expression a sa premiere execution : toute
  -- reference a `new.status` doit rester dans une branche qui ne s'execute que
  -- pour `profiles`, sinon le plan echoue sur season_players / guest_players
  -- qui n'ont pas cette colonne. De meme, `new` n'est pas affecte sur DELETE.
  if tg_table_name = 'profiles' and tg_op = 'UPDATE' then
    v_archived := new.status = 'archived' and old.status is distinct from 'archived';
  end if;

  if tg_op = 'UPDATE' and not v_archived then
    if new.photo_url is not distinct from old.photo_url then
      return new;
    end if;
  end if;

  v_prefix := case tg_table_name
    when 'profiles' then old.id::text
    when 'season_players' then 'season/' || old.id::text
    when 'guest_players' then 'guest/' || old.id::text
  end;
  if v_prefix is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  -- Sur suppression, ou sur archivage d'un profil, plus rien n'est a garder :
  -- une photo de visage ne doit pas survivre au retrait du compte (RGPD).
  if tg_op = 'DELETE' or v_archived then
    v_keep := null;
  else
    v_keep := private.profile_photo_storage_path(new.photo_url);
  end if;

  begin
    perform set_config('storage.allow_delete_query', 'true', true);
    delete from storage.objects
    where bucket_id = 'profile-photos'
      and name like v_prefix || '/%'
      and (v_keep is null or name <> v_keep);
  exception when others then
    -- Un echec de nettoyage ne doit jamais faire echouer l'ecriture metier,
    -- mais il ne doit plus disparaitre en silence non plus.
    raise warning 'cleanup_replaced_photo a echoue pour %/% : %',
      tg_table_name, v_prefix, sqlerrm;
  end;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

comment on function public.cleanup_replaced_photo() is
  'Fonction de trigger interne : supprime les anciennes photos remplacees, ainsi que toutes les photos d un profil supprime ou archive (RGPD).';

-- Le trigger ne couvrait que AFTER UPDATE OF photo_url : ni la suppression ni
-- l'archivage n'effacaient les fichiers, et une photo de visage restait donc
-- accessible apres retrait du compte.
drop trigger if exists trg_cleanup_replaced_photo on public.profiles;
create trigger trg_cleanup_replaced_photo
  after update of photo_url, status or delete on public.profiles
  for each row
  execute function public.cleanup_replaced_photo();

drop trigger if exists trg_cleanup_replaced_photo on public.season_players;
create trigger trg_cleanup_replaced_photo
  after update of photo_url or delete on public.season_players
  for each row
  execute function public.cleanup_replaced_photo();

drop trigger if exists trg_cleanup_replaced_photo on public.guest_players;
create trigger trg_cleanup_replaced_photo
  after update of photo_url or delete on public.guest_players
  for each row
  execute function public.cleanup_replaced_photo();

-- Normalisation des valeurs existantes, une fois le trigger capable de lire
-- les deux formes. `photo_url` n'a pas de trigger BEFORE, et le trigger AFTER
-- conserve exactement le meme objet : aucun fichier n'est supprime ici.
update public.profiles
set photo_url = private.profile_photo_storage_path(photo_url)
where photo_url is not null
  and photo_url like 'http%';

update public.season_players
set photo_url = private.profile_photo_storage_path(photo_url)
where photo_url is not null
  and photo_url like 'http%';

update public.guest_players
set photo_url = private.profile_photo_storage_path(photo_url)
where photo_url is not null
  and photo_url like 'http%';

-- ---------------------------------------------------------------------------
-- Bug 6 (suite) — un membre doit pouvoir enregistrer sa propre photo
-- ---------------------------------------------------------------------------

-- guard_sensitive_profile_fields() traitait `photo_url` comme un champ
-- sensible : un compte non-staff se voyait refuser l'ecriture avec « Les
-- champs sensibles du profil ne peuvent pas etre modifies. ». L'envoi de photo
-- serait donc reste casse pour tous les membres ordinaires meme apres la
-- correction de la CSP.
--
-- L'ouverture est sure : les droits de colonne d'`authenticated` sur
-- public.profiles se limitent deja a first_name, last_name, photo_url, surnom
-- et updated_at, et la RLS restreint la ligne au profil appelant.
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
  editable constant text[] := array[
    'first_name','last_name','surnom','photo_url','updated_at',
    'notify_prediction_open','notify_prediction_reminders','notify_match_reminders',
    'notify_motm_vote','notify_convocation',
    'password_set','must_change_password'
  ];
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

  old_protected := to_jsonb(old) - editable;
  new_protected := to_jsonb(new) - editable;

  if new_protected is distinct from old_protected then
    raise exception 'Les champs sensibles du profil ne peuvent pas être modifiés.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

comment on function public.guard_sensitive_profile_fields() is
  'Fonction de trigger interne : un membre ne modifie que son identite affichee, sa photo et ses preferences de notification.';

-- ---------------------------------------------------------------------------
-- Bug 19 — nettoyage des visuels de badges
-- ---------------------------------------------------------------------------

-- staff_update_badge_image() remplacait badges.image_url sans supprimer
-- l'ancien fichier, et aucun trigger n'ecoutait la table : chaque re-upload
-- abandonnait definitivement un PNG d'environ 570 ko.
create or replace function private.badge_image_storage_path(p_value text)
returns text
language sql
immutable
set search_path to ''
as $function$
  select case
    when nullif(btrim(p_value), '') is null then null
    when position('/badge-images/' in p_value) > 0
      then split_part(
             substring(p_value from position('/badge-images/' in p_value) + 14),
             '?',
             1
           )
    else null
  end;
$function$;

comment on function private.badge_image_storage_path(text) is
  'Chemin d objet dans le bucket badge-images, extrait d une URL publique.';

revoke all on function private.badge_image_storage_path(text)
  from public, anon, authenticated;

create or replace function public.cleanup_replaced_badge_image()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_old text;
  v_new text;
begin
  if tg_op = 'UPDATE' and new.image_url is not distinct from old.image_url then
    return new;
  end if;

  v_old := private.badge_image_storage_path(old.image_url);
  if v_old is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    v_new := null;
  else
    v_new := private.badge_image_storage_path(new.image_url);
  end if;

  if v_new is not null and v_new = v_old then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  begin
    perform set_config('storage.allow_delete_query', 'true', true);
    delete from storage.objects
    where bucket_id = 'badge-images'
      and name = v_old;
  exception when others then
    raise warning 'cleanup_replaced_badge_image a echoue pour % : %',
      v_old, sqlerrm;
  end;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;


comment on function public.cleanup_replaced_badge_image() is
  'Fonction de trigger interne : supprime le visuel de badge remplace ou devenu inutile.';

-- Une fonction fraichement creee est executable par PUBLIC par defaut. Le
-- contrat security_definer_access_matrix exige qu'aucune fonction SECURITY
-- DEFINER du schema public ne soit joignable anonymement : seul le declencheur
-- doit l'appeler.
revoke all on function public.cleanup_replaced_badge_image()
  from public, anon, authenticated;

drop trigger if exists trg_cleanup_replaced_badge_image on public.badges;
create trigger trg_cleanup_replaced_badge_image
  after update of image_url or delete on public.badges
  for each row
  execute function public.cleanup_replaced_badge_image();

-- Purge des orphelins deja accumules : tout objet du bucket badge-images qui
-- n'est reference par aucun badge.
do $cleanup$
begin
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects object
  where object.bucket_id = 'badge-images'
    and not exists (
      select 1
      from public.badges badge
      where private.badge_image_storage_path(badge.image_url) = object.name
    );
exception when others then
  raise warning 'purge des visuels de badges orphelins ignoree : %', sqlerrm;
end;
$cleanup$;

-- Meme purge pour les photos : tout objet dont le prefixe ne correspond plus a
-- aucune photo referencee.
do $cleanup$
begin
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects object
  where object.bucket_id = 'profile-photos'
    and not exists (
      select 1 from public.profiles p
      where private.profile_photo_storage_path(p.photo_url) = object.name
    )
    and not exists (
      select 1 from public.season_players sp
      where private.profile_photo_storage_path(sp.photo_url) = object.name
    )
    and not exists (
      select 1 from public.guest_players gp
      where private.profile_photo_storage_path(gp.photo_url) = object.name
    );
exception when others then
  raise warning 'purge des photos orphelines ignoree : %', sqlerrm;
end;
$cleanup$;

commit;
