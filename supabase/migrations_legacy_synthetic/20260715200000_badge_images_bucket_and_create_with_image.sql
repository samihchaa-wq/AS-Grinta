-- Bucket public pour les images des badges custom (lecture publique, écriture
-- réservée aux administrateurs).
insert into storage.buckets (id, name, public)
values ('badge-images', 'badge-images', true)
on conflict (id) do nothing;

drop policy if exists badge_images_admin_insert on storage.objects;
drop policy if exists badge_images_admin_update on storage.objects;
drop policy if exists badge_images_admin_delete on storage.objects;

create policy badge_images_admin_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'badge-images' and public.is_match_staff());

create policy badge_images_admin_update on storage.objects
  for update to authenticated
  using (bucket_id = 'badge-images' and public.is_match_staff())
  with check (bucket_id = 'badge-images' and public.is_match_staff());

create policy badge_images_admin_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'badge-images' and public.is_match_staff());

-- Création d'un badge custom par l'admin, avec image optionnelle.
drop function if exists public.staff_create_badge(text, text, text, text);

create function public.staff_create_badge(
  p_code text,
  p_name text,
  p_emoji text default '🏅',
  p_description text default '',
  p_image_url text default null
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_code is null or p_code = '' or p_name is null or p_name = '' then
    raise exception 'code and name are required' using errcode = '22023';
  end if;
  insert into public.badges(code, name, description, emoji, image_url, family, auto, kind, category, metric, threshold, sort_order)
  values (p_code, p_name, coalesce(p_description, ''),
          coalesce(nullif(p_emoji, ''), '🏅'), p_image_url,
          'joueur', false, 'custom', 'faits_de_jeu', null, null, 900)
  on conflict (code) do update
    set name = excluded.name,
        emoji = excluded.emoji,
        description = excluded.description,
        image_url = excluded.image_url;
  return true;
end;
$function$;

revoke all on function public.staff_create_badge(text, text, text, text, text) from public, anon;
grant execute on function public.staff_create_badge(text, text, text, text, text) to authenticated;
