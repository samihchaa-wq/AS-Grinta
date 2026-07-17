-- CI-only compatibility shim applied before RLS policies are created.
-- Later historical migrations replace the match status constraint using text
-- values, so reproduce the hosted pre-migration text column in the disposable
-- local database before any policy depends on it.

alter table public.matches
  alter column status drop default,
  alter column status type text using status::text,
  alter column status set default 'a_venir';
