update public.historical_player_statistics
  set clean_sheets = 21, updated_at = now()
  where scope = 'all_time'
    and profile_id = '89f24276-dac0-4046-87a3-6c28e48fef3a';

select public.recalculate_profile_badges('89f24276-dac0-4046-87a3-6c28e48fef3a');;
