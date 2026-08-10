-- Les policies storage n'évaluent is_admin()/is_match_staff() qu'en tant
-- qu'authenticated. Le grant à anon (ajouté par erreur lors du correctif
-- d'upload photo) est inutile et signalé par l'advisor sécurité Supabase.
revoke execute on function public.is_admin() from anon;
revoke execute on function public.is_match_staff() from anon;
