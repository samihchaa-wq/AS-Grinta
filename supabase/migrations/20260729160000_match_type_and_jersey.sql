-- Type de match (amical / championnat) à titre informatif, et un
-- commentaire libre "Maillot" que l'admin peut renseigner puis modifier.
-- Les deux n'apparaissent que dans l'onglet Info d'un match.

alter table public.matches
  add column match_type text not null default 'championnat'
    check (match_type in ('amical', 'championnat'));

alter table public.matches
  add column jersey_note text;

create or replace function public.admin_set_match_type(
  p_match_id uuid,
  p_match_type text
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_type is null or p_match_type not in ('amical', 'championnat') then
    raise exception 'Invalid match type' using errcode = '22023';
  end if;

  update public.matches
  set match_type = p_match_type
  where id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
end;
$$;

grant execute on function public.admin_set_match_type(uuid, text) to authenticated;

create or replace function public.admin_set_match_jersey(
  p_match_id uuid,
  p_jersey_note text
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_jersey_note text := nullif(btrim(p_jersey_note), '');
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_jersey_note is not null and char_length(v_jersey_note) > 300 then
    raise exception 'Jersey note cannot exceed 300 characters' using errcode = '22023';
  end if;

  update public.matches
  set jersey_note = v_jersey_note
  where id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
end;
$$;

grant execute on function public.admin_set_match_jersey(uuid, text) to authenticated;
