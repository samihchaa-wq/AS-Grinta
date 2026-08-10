create or replace function public.set_match_odds(
  p_match_id uuid,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns boolean
language plpgsql
security definer
set search_path='public'
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;

  if p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
     or p_win > 100 or p_draw > 100 or p_loss > 100 then
    raise exception 'Invalid odds';
  end if;

  if not exists (
    select 1 from public.matches
    where id = p_match_id and status = 'a_venir'
  ) then
    raise exception 'Only upcoming matches can be updated';
  end if;

  insert into public.match_odds(
    match_id,
    odds_victoire_as_grinta,
    odds_nul,
    odds_victoire_adverse,
    computed_at
  ) values (
    p_match_id,
    round(p_win, 2),
    round(p_draw, 2),
    round(p_loss, 2),
    now()
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      computed_at = now();

  return true;
end;
$$;

revoke all on function public.set_match_odds(uuid,numeric,numeric,numeric) from public, anon;
grant execute on function public.set_match_odds(uuid,numeric,numeric,numeric) to authenticated;
