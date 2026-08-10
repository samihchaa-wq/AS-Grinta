revoke update on public.profiles from authenticated;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'photo_url'
  ) then
    grant update (first_name, last_name, photo_url)
      on public.profiles to authenticated;
  else
    grant update (first_name, last_name)
      on public.profiles to authenticated;
  end if;
end;
$$;
