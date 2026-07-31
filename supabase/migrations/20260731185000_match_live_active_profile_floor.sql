begin;

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

-- Les tables des compositions "entre nous" (20260729170000_internal_matches.sql)
-- ont été créées après le plancher générique du 20260727 et n'en ont jamais
-- hérité non plus ; on comble le même trou ici, à l'identique. Ce fichier de
-- migration n'existe pas dans le rejeu ciblé de la CI (supabase_business_tests
-- .yml n'inclut pas 20260729170000), donc on protège l'exécution avec une
-- vérification d'existence plutôt que de supposer que les tables sont là.
do $block$
begin
  if to_regclass('public.match_internal_compositions') is not null then
    execute 'drop policy if exists active_authenticated_profile_only '
      'on public.match_internal_compositions';
    execute 'create policy active_authenticated_profile_only '
      'on public.match_internal_compositions '
      'as restrictive for all to authenticated '
      'using ((select private.is_active_profile())) '
      'with check ((select private.is_active_profile()))';
  end if;

  if to_regclass('public.match_internal_composition_entries') is not null then
    execute 'drop policy if exists active_authenticated_profile_only '
      'on public.match_internal_composition_entries';
    execute 'create policy active_authenticated_profile_only '
      'on public.match_internal_composition_entries '
      'as restrictive for all to authenticated '
      'using ((select private.is_active_profile())) '
      'with check ((select private.is_active_profile()))';
  end if;
end;
$block$;

commit;
