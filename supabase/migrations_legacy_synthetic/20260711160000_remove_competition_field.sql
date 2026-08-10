-- Suppression de la notion de championnat/compétition : le champ n'est plus
-- demandé à la création d'un match ni affiché. La colonne matches.competition
-- reste en base pour l'historique mais n'est plus alimentée.
alter table public.matches alter column competition drop not null;

drop function if exists public.create_match_with_odds(
  uuid, uuid, date, time without time zone, text, text, numeric, numeric, numeric
);

create function public.create_match_with_odds(
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare new_id uuid;
begin
  if not public.is_match_staff() then raise exception 'Staff role required'; end if;
  if p_location not in ('domicile','exterieur') then raise exception 'Invalid location'; end if;
  if p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
     or p_win > 100 or p_draw > 100 or p_loss > 100 then
    raise exception 'Invalid odds';
  end if;
  insert into public.matches(
    season_id, opponent_id, match_date, match_time, location,
    planned_duration_minutes, status, created_by
  )
  values (
    p_season_id, p_opponent_id, p_match_date, p_match_time, p_location,
    90, 'a_venir', auth.uid()
  )
  returning id into new_id;
  perform public.set_match_odds(new_id, p_win, p_draw, p_loss);
  return new_id;
end;
$$;

revoke all on function public.create_match_with_odds(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric) from public, anon;
grant execute on function public.create_match_with_odds(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric) to authenticated;
