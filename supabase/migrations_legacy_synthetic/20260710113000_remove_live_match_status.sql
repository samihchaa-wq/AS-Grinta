begin;

drop function if exists public.finalize_match(uuid,integer,integer,uuid) cascade;

alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches
  add constraint matches_status_check
  check (status = any (array['a_venir'::text,'termine'::text,'archive'::text]));

commit;
