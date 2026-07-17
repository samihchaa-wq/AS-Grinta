-- Emergency rollback for 20260719011000_statistics_view_security_invoker.sql.
-- Restores the former owner-privileged view behaviour while preserving the
-- original client-facing access contract.

alter view public.v_statistics_players
  reset (security_invoker);

revoke all on public.v_statistics_players
  from public, anon;

grant select on public.v_statistics_players
  to authenticated;

grant all privileges on public.v_statistics_players
  to service_role;
