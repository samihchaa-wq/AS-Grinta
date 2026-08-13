-- Correctif urgent : « Collection indisponible » sur l'Armoire a badges, et
-- plus generalement toute page affichant des badges arbores.
--
-- La migration 20260813210100 a deplace l'implementation des metriques dans
-- `private` et repointe les appelants internes. Elle a revoque
-- private.profile_badge_metrics a `authenticated` en supposant que
-- private.profile_badge_stars, passee SECURITY DEFINER, suffirait a franchir
-- la barriere pour ses appelants.
--
-- C'est faux en pratique : profile_badge_stars est une fonction LANGUAGE SQL
-- appelee en `cross join lateral` par featured_badges(), qui est SECURITY
-- INVOKER. Le controle de droit sur la fonction imbriquee retombe sur le role
-- appelant, et `authenticated` se voit refuser
-- « permission denied for function profile_badge_metrics ».
--
-- Le droit est donc accorde a `authenticated` sur l'implementation privee,
-- exactement comme il l'est deja pour private.profile_badge_stars.
--
-- Cela ne rouvre pas la fuite corrigee au bug 5 : le schema `private` n'est
-- pas expose par PostgREST, donc aucun client de l'API ne peut appeler cette
-- fonction. La protection reelle reste le garde-fou de
-- public.profile_badge_metrics(), qui limite la lecture au profil appelant ou
-- au staff — et qui est verifie par audit_2026_08_13_fixes.test.sql.
--
-- Le contrat security_surface_contract n'est pas affecte : il interdit les
-- droits accordes a PUBLIC ou anon, pas a authenticated.

begin;

grant execute on function private.profile_badge_metrics(uuid)
  to authenticated, service_role;

comment on function private.profile_badge_metrics(uuid) is
  'Implementation reelle des metriques de badges. Le schema private n est pas expose par PostgREST : l acces client passe obligatoirement par public.profile_badge_metrics(), qui controle l identite.';

commit;
