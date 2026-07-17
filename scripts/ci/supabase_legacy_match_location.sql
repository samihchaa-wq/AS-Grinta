-- CI-only compatibility shim before temporal odds migrations.
-- Historical RPCs and triggers reference public.matches.location, but the
-- tracked migration chain never creates that column on a database rebuilt from
-- zero. Add it only to the disposable local runner with a synthetic default.

alter table public.matches
  add column if not exists location text not null default 'domicile';

alter table public.matches
  drop constraint if exists matches_location_check;

alter table public.matches
  add constraint matches_location_check
  check (location in ('domicile', 'exterieur'));
