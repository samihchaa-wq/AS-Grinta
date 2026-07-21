-- Les privilèges par défaut Supabase peuvent accorder plus que SELECT aux vues.
-- La vue des statistiques équipe doit rester strictement en lecture seule.
revoke all on public.v_statistics_team from authenticated;
grant select on public.v_statistics_team to authenticated;
