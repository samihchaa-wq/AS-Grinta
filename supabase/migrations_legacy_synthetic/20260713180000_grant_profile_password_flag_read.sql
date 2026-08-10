grant select (must_change_password) on table public.profiles to authenticated;

comment on column public.profiles.must_change_password is
  'Read by the signed-in user to force the temporary-password replacement screen; writes are performed through secured RPCs.';
