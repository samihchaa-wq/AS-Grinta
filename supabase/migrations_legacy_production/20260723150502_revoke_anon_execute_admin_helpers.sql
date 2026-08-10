-- Les policies storage évaluent is_admin()/is_match_staff() en tant
-- qu'authenticated uniquement. Le grant à anon (ajouté par erreur lors du
-- correctif d'upload photo) est inutile et flaggé par l'advisor sécurité.
revoke execute on function public.is_admin() from anon;
revoke execute on function public.is_match_staff() from anon;;
