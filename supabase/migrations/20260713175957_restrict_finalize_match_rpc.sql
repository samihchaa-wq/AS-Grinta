revoke execute on function public.finalize_match_postgame(uuid, integer, jsonb, uuid) from public, anon, authenticated;
revoke execute on function public.finalize_match_postgame(uuid, integer, jsonb, uuid, integer) from public, anon;
grant execute on function public.finalize_match_postgame(uuid, integer, jsonb, uuid, integer) to authenticated;;
