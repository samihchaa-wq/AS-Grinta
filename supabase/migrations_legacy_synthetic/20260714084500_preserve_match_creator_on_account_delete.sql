alter table public.matches
  alter column created_by
  set default '00000000-0000-0000-0000-000000000001'::uuid;

alter table public.matches
  drop constraint if exists matches_created_by_fkey;

alter table public.matches
  add constraint matches_created_by_fkey
  foreign key (created_by)
  references public.profiles(id)
  on delete set default;
