-- Correction validée : Samih totalise 16 clean sheets toutes saisons.
-- La saison 2025-2026 reste à 6 clean sheets.

update public.historical_player_statistics
set clean_sheets = 16,
    updated_at = now()
where scope = 'all_time'
  and player_name = 'Samih Châa';
