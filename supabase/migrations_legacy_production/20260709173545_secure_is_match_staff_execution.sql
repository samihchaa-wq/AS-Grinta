revoke execute on function public.is_match_staff() from public;
revoke execute on function public.is_match_staff() from anon;
grant execute on function public.is_match_staff() to authenticated;;
