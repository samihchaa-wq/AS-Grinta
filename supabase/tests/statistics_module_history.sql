begin;

do $$
declare
  previous_count integer;
  all_time_count integer;
  current_count integer;
  milan_goals integer;
  samih_clean_sheets integer;
begin
  select count(*) into previous_count
  from public.v_statistics_players
  where period_key = 'previous';

  select count(*) into all_time_count
  from public.v_statistics_players
  where period_key = 'all_time';

  select count(*) into current_count
  from public.v_statistics_players
  where period_key = 'current';

  select goals into milan_goals
  from public.v_statistics_players
  where period_key = 'previous'
    and player_name = 'Milan Couzin';

  select clean_sheets into samih_clean_sheets
  from public.v_statistics_players
  where period_key = 'all_time'
    and player_name = 'Samih Châa';

  if previous_count <> 19 then
    raise exception 'Expected 19 previous-season rows, got %', previous_count;
  end if;

  if all_time_count <> 19 then
    raise exception 'Expected 19 all-time rows, got %', all_time_count;
  end if;

  if current_count <> 19 then
    raise exception 'Expected 19 current-season rows, got %', current_count;
  end if;

  if milan_goals <> 30 then
    raise exception 'Expected Milan to have 30 goals in 2025-2026, got %',
      milan_goals;
  end if;

  if samih_clean_sheets <> 21 then
    raise exception 'Expected Samih to have 21 all-time clean sheets, got %',
      samih_clean_sheets;
  end if;
end
$$;

rollback;
