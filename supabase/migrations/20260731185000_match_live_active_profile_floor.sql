-- Le Tableau Blanc (match_live_sessions / match_live_events) manquait le
-- plancher de sécurité appliqué à toutes les autres tables applicatives
-- publiques : une politique RESTRICTIVE distincte imposant un profil actif
-- sur toute commande, en plus des politiques permissives dédiées.
-- Voir 20260727040000_lock_down_business_security_surface.sql pour le motif
-- d'origine, répliqué ici à l'identique.
drop policy if exists active_authenticated_profile_only
  on public.match_live_sessions;
create policy active_authenticated_profile_only
  on public.match_live_sessions
  as restrictive for all to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));

drop policy if exists active_authenticated_profile_only
  on public.match_live_events;
create policy active_authenticated_profile_only
  on public.match_live_events
  as restrictive for all to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));
;
