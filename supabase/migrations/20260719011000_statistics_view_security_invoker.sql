-- Make the statistics view evaluate the underlying RLS policies with the
-- caller's privileges instead of the view owner's privileges.
-- PostgreSQL 15+ supports security_invoker views.

alter view public.v_statistics_players
  set (security_invoker = true);

revoke all on public.v_statistics_players
  from public, anon;

-- Existing direct privileges are preserved; these grants make the intended
-- read contract explicit.
grant select on public.v_statistics_players
  to authenticated, service_role;
