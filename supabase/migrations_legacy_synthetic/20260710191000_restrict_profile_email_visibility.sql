-- L'email n'est jamais lu depuis profiles par l'application : l'utilisateur
-- obtient le sien via Auth et le staff passe par staff_list_profiles
-- (SECURITY DEFINER). On retire donc la colonne email de la lecture directe.
revoke select on public.profiles from authenticated, anon;
grant select (id, first_name, last_name, surnom, photo_url, role, is_goalkeeper, status, notify_match_reminders, notify_prediction_reminders, created_at, updated_at)
on public.profiles to authenticated;
