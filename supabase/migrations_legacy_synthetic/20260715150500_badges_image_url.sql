-- Colonne image pour les badges custom créés par l'admin (nom + image).
alter table public.badges add column if not exists image_url text;
