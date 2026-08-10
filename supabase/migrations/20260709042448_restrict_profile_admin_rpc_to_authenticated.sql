revoke execute on function public.moderator_update_profile_admin_fields(uuid,text,text,boolean) from public;
revoke execute on function public.moderator_update_profile_admin_fields(uuid,text,text,boolean) from anon;
grant execute on function public.moderator_update_profile_admin_fields(uuid,text,text,boolean) to authenticated;;
