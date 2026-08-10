-- Ajouter la colonne surnom (surnom / alias d'affichage) aux profils
alter table public.profiles
  add column if not exists surnom text;

-- Même colonne sur la table des joueurs indépendants
alter table public.players
  add column if not exists surnom text;

-- Autoriser les modérateurs à mettre à jour le surnom d'un profil
-- (la colonne entre dans le grant existant via moderator_update_profile_admin_fields RPC)
-- On ajoute aussi le grant direct pour les mises à jour de la page profil
grant update(surnom, first_name, last_name, photo_url, updated_at)
  on public.profiles to authenticated;
