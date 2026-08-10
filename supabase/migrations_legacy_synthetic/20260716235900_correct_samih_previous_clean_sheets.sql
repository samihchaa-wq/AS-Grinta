-- Correction validée : Samih a réalisé 6 clean sheets en 2025-2026.
-- Le cumul historique passe donc de 21 à 24 clean sheets.

update public.historical_player_statistics
set clean_sheets = 6,
    updated_at = now()
where scope = 'previous'
  and player_name = 'Samih Châa';

update public.historical_player_statistics
set clean_sheets = 24,
    updated_at = now()
where scope = 'all_time'
  and player_name = 'Samih Châa';
