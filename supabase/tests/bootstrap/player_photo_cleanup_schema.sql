-- Pré-requis structurels minimaux pour tester le trigger de nettoyage des photos.
-- Le comportement complet d'affichage des photos est couvert par les migrations
-- de production ; le bootstrap local n'a besoin ici que des colonnes ciblées.

alter table public.season_players
  add column if not exists photo_url text;

alter table public.guest_players
  add column if not exists photo_url text;
