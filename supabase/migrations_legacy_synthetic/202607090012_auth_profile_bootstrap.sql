create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(
    id,email,first_name,last_name,role,is_goalkeeper,status
  ) values (
    new.id,
    coalesce(new.email,''),
    coalesce(new.raw_user_meta_data->>'first_name',''),
    coalesce(new.raw_user_meta_data->>'last_name',''),
    'pronostiqueur',
    false,
    'active'
  )
  on conflict(id) do update
  set email=excluded.email,
      first_name=case
        when public.profiles.first_name='' then excluded.first_name
        else public.profiles.first_name
      end,
      last_name=case
        when public.profiles.last_name='' then excluded.last_name
        else public.profiles.last_name
      end,
      updated_at=now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update of email,raw_user_meta_data on auth.users
for each row execute function public.handle_new_auth_user();

revoke execute on function public.handle_new_auth_user() from public;
revoke execute on function public.handle_new_auth_user() from anon;
revoke execute on function public.handle_new_auth_user() from authenticated;
