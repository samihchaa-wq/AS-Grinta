-- Permet au modérateur de remplacer uniquement l'image centrale d'un badge
-- existant. Le fond/couleur, le titre, la description, le barème et les autres
-- métadonnées ne sont jamais modifiés par cette RPC.

create or replace function public.staff_update_badge_image(
  p_badge_code text,
  p_image_url text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required' using errcode = '42501';
  end if;

  if nullif(btrim(p_badge_code), '') is null then
    raise exception 'Badge code is required' using errcode = '22023';
  end if;

  if nullif(btrim(p_image_url), '') is null then
    raise exception 'Badge image URL is required' using errcode = '22023';
  end if;

  -- L'application téléverse d'abord le PNG dans le bucket public dédié. On
  -- refuse une URL externe afin que le catalogue ne puisse pas devenir un
  -- vecteur de contenu tiers ou de tracking distant.
  if position('/storage/v1/object/public/badge-images/' in p_image_url) = 0 then
    raise exception 'Badge image must come from badge-images storage' using errcode = '22023';
  end if;

  update public.badges
  set image_url = btrim(p_image_url)
  where code = btrim(p_badge_code);

  if not found then
    raise exception 'Badge not found' using errcode = 'P0002';
  end if;

  return true;
end;
$function$;

revoke all on function public.staff_update_badge_image(text, text)
  from public, anon;
grant execute on function public.staff_update_badge_image(text, text)
  to authenticated, service_role;

comment on function public.staff_update_badge_image(text, text) is
  'Moderator-only replacement of a badge image_url; all other badge fields stay unchanged.';
