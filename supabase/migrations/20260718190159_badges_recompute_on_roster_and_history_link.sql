create or replace function public.trg_badges_on_roster_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.profile_id is not null then
    perform public.recalculate_profile_badges(new.profile_id);
  end if;
  if tg_op = 'UPDATE'
     and old.profile_id is not null
     and old.profile_id is distinct from new.profile_id then
    perform public.recalculate_profile_badges(old.profile_id);
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_badges_roster on public.season_players;
create trigger trg_badges_roster
  after insert or update of profile_id, first_name, last_name, season_id
  on public.season_players
  for each row execute function public.trg_badges_on_roster_change();

create or replace function public.trg_badges_on_historical_link()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.profile_id is not null then
    perform public.recalculate_profile_badges(new.profile_id);
  end if;
  if tg_op = 'UPDATE'
     and old.profile_id is not null
     and old.profile_id is distinct from new.profile_id then
    perform public.recalculate_profile_badges(old.profile_id);
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_badges_historical_link on public.historical_player_statistics;
create trigger trg_badges_historical_link
  after insert or update of profile_id
  on public.historical_player_statistics
  for each row execute function public.trg_badges_on_historical_link();

select public.recalculate_all_badges();;
