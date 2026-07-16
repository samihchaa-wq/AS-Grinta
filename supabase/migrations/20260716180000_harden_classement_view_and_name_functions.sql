-- Rétablit security_invoker sur la vue du classement (perdu lors du
-- CREATE OR REPLACE), pour qu'elle applique la RLS de l'utilisateur comme
-- les autres vues du projet.
alter view public.v_classement_general set (security_invoker = true);

-- Fige le search_path des deux fonctions de validation des noms.
create or replace function public.is_valid_person_name(txt text)
returns boolean
language sql
immutable
set search_path to 'public'
as $$
  select case
    when txt is null then true
    when btrim(txt) = '' then true
    else btrim(txt) ~ '^[[:alpha:] ''’-]+$' and btrim(txt) ~ '[[:alpha:]]'
  end;
$$;

create or replace function public.validate_profile_names()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if not public.is_valid_person_name(new.first_name) then
    raise exception 'Le prénom ne doit contenir que des lettres (ni emoji, ni chiffre, ni symbole).'
      using errcode = '23514';
  end if;
  if not public.is_valid_person_name(new.last_name) then
    raise exception 'Le nom ne doit contenir que des lettres (ni emoji, ni chiffre, ni symbole).'
      using errcode = '23514';
  end if;
  if not public.is_valid_person_name(new.surnom) then
    raise exception 'Le surnom ne doit contenir que des lettres (ni emoji, ni chiffre, ni symbole).'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
