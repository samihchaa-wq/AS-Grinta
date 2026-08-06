-- club_events (20260805132747_club_events.sql) a été créée après le plancher
-- de sécurité générique (20260727040000_lock_down_business_security_surface.sql)
-- et ne l'a jamais reçu, contrairement aux autres tables applicatives
-- publiques : il lui manquait la politique RESTRICTIVE distincte imposant un
-- profil actif sur toute commande, en plus des politiques permissives dédiées.
-- Voir 20260731185000_match_live_active_profile_floor.sql pour le même trou
-- comblé à l'identique sur d'autres tables ajoutées après le plancher.
drop policy if exists active_authenticated_profile_only
  on public.club_events;
create policy active_authenticated_profile_only
  on public.club_events
  as restrictive for all to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));
