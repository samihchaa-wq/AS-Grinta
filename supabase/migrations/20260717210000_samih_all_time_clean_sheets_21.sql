-- Correction officielle : avant la saison 2026-2027, Samih totalise 21 clean
-- sheets en carrière (au lieu de 13). On met à jour la ligne d'historique
-- carrière (scope 'all_time'), puis on recalcule ses badges (les paliers clean
-- sheets nouvellement atteints sont ajoutés ; rien n'est jamais retiré).
update public.historical_player_statistics
  set clean_sheets = 21, updated_at = now()
  where scope = 'all_time'
    and profile_id = '89f24276-dac0-4046-87a3-6c28e48fef3a';

select public.recalculate_profile_badges('89f24276-dac0-4046-87a3-6c28e48fef3a');
