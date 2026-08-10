alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

comment on column public.profiles.must_change_password is
  'True after an admin password reset. The user must choose a new password after signing in with the temporary password.';
