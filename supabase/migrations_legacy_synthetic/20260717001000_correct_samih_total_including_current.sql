-- Samih a réalisé 6 clean sheets en 2025-2026.
-- Le cumul historique hors saison actuelle est de 13.
-- La vue Toutes saisons ajoute les 3 clean sheets de la saison actuelle,
-- soit 16 au total.

update public.historical_player_statistics
set clean_sheets = 6,
    updated_at = now()
where scope = 'previous'
  and player_name = 'Samih Châa';

update public.historical_player_statistics
set clean_sheets = 13,
    updated_at = now()
where scope = 'all_time'
  and player_name = 'Samih Châa';
