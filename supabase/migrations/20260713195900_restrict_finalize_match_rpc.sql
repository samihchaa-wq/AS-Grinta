-- Mirrors the emergency production hardening applied through Supabase.
-- Keep both finalize_match_postgame overloads inaccessible to anon and expose
-- only the current five-argument contract to authenticated clients.

revoke execute on function public.finalize_match_postgame(
  uuid,
  integer,
  jsonb,
  uuid
) from public, anon, authenticated;

revoke execute on function public.finalize_match_postgame(
  uuid,
  integer,
  jsonb,
  uuid,
  integer
) from public, anon;

grant execute on function public.finalize_match_postgame(
  uuid,
  integer,
  jsonb,
  uuid,
  integer
) to authenticated;
