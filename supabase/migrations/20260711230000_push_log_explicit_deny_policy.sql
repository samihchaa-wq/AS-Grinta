-- push_notification_log est un journal interne écrit uniquement par les
-- fonctions/edge functions en service_role (qui contournent la RLS). Aucun
-- utilisateur authentifié ne doit y accéder. La RLS sans policy refuse déjà
-- tout, mais on rend l'intention explicite (et on lève l'avertissement du
-- linter « RLS enabled, no policy »).
drop policy if exists push_notification_log_no_client_access
  on public.push_notification_log;

create policy push_notification_log_no_client_access
  on public.push_notification_log
  as restrictive
  for all
  to authenticated, anon
  using (false)
  with check (false);
