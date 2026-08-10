revoke update on public.profiles from authenticated;
grant update (first_name, last_name, photo_url) on public.profiles to authenticated;;
