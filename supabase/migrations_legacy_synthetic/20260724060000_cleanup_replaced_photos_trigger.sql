-- Suppression fiable de l'ancienne photo au changement. Le trigger de
-- protection du stockage bloque les suppressions directes ; on les autorise
-- explicitement (flag local) dans un trigger serveur qui, dès que photo_url
-- change, supprime tous les autres fichiers du dossier du joueur/invité.

create or replace function public.cleanup_replaced_photo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_prefix text;
  v_keep text;
begin
  if new.photo_url is not distinct from old.photo_url then
    return new;
  end if;

  v_prefix := case tg_table_name
    when 'profiles' then new.id::text
    when 'season_players' then 'season/' || new.id::text
    when 'guest_players' then 'guest/' || new.id::text
  end;
  if v_prefix is null then
    return new;
  end if;

  v_keep := substring(coalesce(new.photo_url, '') from '/profile-photos/(.*)$');

  begin
    perform set_config('storage.allow_delete_query', 'true', true);
    delete from storage.objects
    where bucket_id = 'profile-photos'
      and name like v_prefix || '/%'
      and name is distinct from v_keep;
  exception when others then
    -- Le nettoyage ne doit jamais empêcher la mise à jour de la photo.
    null;
  end;

  return new;
end;
$function$;

drop trigger if exists trg_cleanup_replaced_photo on public.profiles;
create trigger trg_cleanup_replaced_photo
  after update of photo_url on public.profiles
  for each row execute function public.cleanup_replaced_photo();

drop trigger if exists trg_cleanup_replaced_photo on public.season_players;
create trigger trg_cleanup_replaced_photo
  after update of photo_url on public.season_players
  for each row execute function public.cleanup_replaced_photo();

drop trigger if exists trg_cleanup_replaced_photo on public.guest_players;
create trigger trg_cleanup_replaced_photo
  after update of photo_url on public.guest_players
  for each row execute function public.cleanup_replaced_photo();

-- Nettoyage unique des photos orphelines déjà présentes (non référencées).
do $$
begin
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects o
  where o.bucket_id = 'profile-photos'
    and o.name not in (
      select substring(photo_url from '/profile-photos/(.*)$')
        from public.profiles where photo_url is not null
      union
      select substring(photo_url from '/profile-photos/(.*)$')
        from public.season_players where photo_url is not null
      union
      select substring(photo_url from '/profile-photos/(.*)$')
        from public.guest_players where photo_url is not null
    );
exception when others then
  null;
end $$;
