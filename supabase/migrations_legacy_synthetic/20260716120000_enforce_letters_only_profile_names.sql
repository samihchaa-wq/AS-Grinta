-- Les noms de personne (prénom, nom, surnom) ne doivent contenir que des
-- lettres (accents compris), espaces, tirets et apostrophes. Pas d'emoji,
-- pas de chiffre, pas de symbole.
create or replace function public.is_valid_person_name(txt text)
returns boolean
language sql
immutable
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

drop trigger if exists trg_validate_profile_names on public.profiles;
create trigger trg_validate_profile_names
  before insert or update of first_name, last_name, surnom on public.profiles
  for each row execute function public.validate_profile_names();
