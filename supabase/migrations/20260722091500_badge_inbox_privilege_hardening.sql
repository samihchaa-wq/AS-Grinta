-- Les privilèges par défaut du projet accordent plus de droits que nécessaire
-- lors de la création d'une table. La boîte à badges n'expose que les trois
-- opérations utilisées par l'application ; la RLS limite ensuite chaque membre
-- à sa propre ligne.

revoke all on public.badge_inbox_state from authenticated;
revoke all on public.badge_inbox_state from anon;
grant select, insert, update on public.badge_inbox_state to authenticated;
