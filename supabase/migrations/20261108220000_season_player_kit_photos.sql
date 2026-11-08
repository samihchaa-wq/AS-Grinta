-- Photos alternatives pour les compositions : France = photo actuelle du joueur.
-- Les deux autres photos sont facultatives et ne modifient jamais le portrait
-- du compte (profiles.photo_url), ni celui de l'effectif.
begin;

create table if not exists public.season_player_kit_photos (
  season_player_id uuid primary key references public.season_players(id) on delete cascade,
  brazil_url text,
  netherlands_url text,
  updated_at timestamptz not null default now(),
  constraint kit_photo_paths_are_private check (
    (brazil_url is null or brazil_url like 'kits/%')
    and (netherlands_url is null or netherlands_url like 'kits/%')
  )
);

alter table public.season_player_kit_photos enable row level security;
-- Contrat de securite commun a toutes les tables applicatives.
create policy active_authenticated_profile_only
  on public.season_player_kit_photos
  as restrictive for all to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));
revoke all on public.season_player_kit_photos from public, anon;
grant select, insert, update, delete
  on public.season_player_kit_photos to authenticated;

create policy "active_members_read_kit_photos"
  on public.season_player_kit_photos
  for select to authenticated
  using ((select private.is_active_profile()));

create policy "admin_insert_kit_photos"
  on public.season_player_kit_photos
  for insert to authenticated
  with check ((select private.is_admin()));
create policy "admin_update_kit_photos"
  on public.season_player_kit_photos
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));
create policy "admin_delete_kit_photos"
  on public.season_player_kit_photos
  for delete to authenticated
  using ((select private.is_admin()));

-- Les variantes vivent dans profile-photos (bucket prive existant), sous
-- kits/<season_player_id>/. Les regles de televersement admin restent celles
-- du bucket. On evite ainsi le nettoyage du portrait France, qui gere
-- exclusivement profiles/season/.../avatar.
create or replace function private.cleanup_player_kit_photos()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  old_paths text[];
  keep_paths text[];
begin
  old_paths := array[old.brazil_url, old.netherlands_url];
  if tg_op = 'DELETE' then
    keep_paths := array[]::text[];
  else
    keep_paths := array[new.brazil_url, new.netherlands_url];
  end if;

  begin
    perform set_config('storage.allow_delete_query', 'true', true);
    delete from storage.objects
      where bucket_id = 'profile-photos'
      and name like 'kits/' || old.season_player_id::text || '/%'
      and name = any(old_paths)
      and not (name = any(array_remove(keep_paths, null)));
  exception when others then
    raise warning 'cleanup_player_kit_photos a echoue : %', sqlerrm;
  end;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

revoke all on function private.cleanup_player_kit_photos()
  from public, anon, authenticated;
create trigger cleanup_player_kit_photo_files
  after update of brazil_url, netherlands_url or delete
  on public.season_player_kit_photos
  for each row execute function private.cleanup_player_kit_photos();

commit;
