begin;

-- Permet aux gestionnaires de badges de corriger le nom et le descriptif d'un
-- badge existant depuis sa fiche. Seuls ces deux champs sont modifiés : code,
-- image, couleur, barème et attributions restent inchangés.
create or replace function public.staff_update_badge_text(
  p_badge_code text,
  p_name text,
  p_description text default ''
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.can_manage_badges() then
    raise exception 'Badge administration access required' using errcode = '42501';
  end if;

  if nullif(btrim(p_badge_code), '') is null then
    raise exception 'Badge code is required' using errcode = '22023';
  end if;

  if nullif(btrim(p_name), '') is null then
    raise exception 'Badge name is required' using errcode = '22023';
  end if;

  if char_length(btrim(p_name)) > 60 then
    raise exception 'Badge name is too long' using errcode = '22023';
  end if;

  if char_length(btrim(coalesce(p_description, ''))) > 300 then
    raise exception 'Badge description is too long' using errcode = '22023';
  end if;

  update public.badges
  set name = btrim(p_name),
      description = btrim(coalesce(p_description, ''))
  where code = btrim(p_badge_code);

  if not found then
    raise exception 'Badge not found' using errcode = 'P0002';
  end if;

  return true;
end;
$$;

revoke all on function public.staff_update_badge_text(text, text, text)
  from public, anon;
grant execute on function public.staff_update_badge_text(text, text, text)
  to authenticated, service_role;

comment on function public.staff_update_badge_text(text, text, text) is
  'Badge-manager-only edit of a badge name and description; all other badge fields stay unchanged.';

commit;
