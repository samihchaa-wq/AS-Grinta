-- Preserve the naming invariants already enforced by the application RPCs.

alter table public.opponents
  drop constraint if exists opponents_name_check;

alter table public.opponents
  add constraint opponents_name_check
  check (
    name = btrim(name)
    and length(name) between 2 and 100
  );

create unique index if not exists opponents_normalized_name_uidx
  on public.opponents (lower(btrim(name)));

alter table public.seasons
  add constraint seasons_name_format_check
  check (
    case
      when name ~ '^[0-9]{4}-[0-9]{4}$'
        then substring(name from 6 for 4)::integer
             = substring(name from 1 for 4)::integer + 1
      else false
    end
  );
