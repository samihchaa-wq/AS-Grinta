-- Défense en profondeur : ces fonctions SECURITY DEFINER n'ont aucune raison
-- d'être appelées sans être connecté (l'app ne les utilise qu'authentifiée).
-- Les deux fonctions staff_* revérifient déjà les droits en interne
-- (is_match_staff()), mais on retire l'accès anon pour vider l'alerte du linter
-- et fermer la surface d'attaque. authenticated et service_role conservent tout.
revoke execute on function public.featured_badges() from anon;
revoke execute on function public.profile_badge_stars(uuid) from anon;
revoke execute on function public.staff_list_historical_players() from anon;
revoke execute on function public.staff_set_historical_profile(uuid, bigint) from anon;
