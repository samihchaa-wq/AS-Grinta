-- When a roster member's coach flag changes, immediately reflect it on the
-- participants of upcoming matches so the effectif/compo update without a
-- manual re-sync.
create or replace function private.apply_coach_flag_to_participants()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if new.is_coach is distinct from old.is_coach then
    update public.match_sport_participants participant
    set is_eligible = not new.is_coach,
        updated_at = now()
    from public.matches match
    where participant.season_player_id = new.id
      and participant.match_id = match.id
      and match.status = 'a_venir';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_season_player_coach_sync on public.season_players;
create trigger trg_season_player_coach_sync
  after update of is_coach on public.season_players
  for each row
  execute function private.apply_coach_flag_to_participants();;
