begin;

-- Legacy compatibility RPC used to edit the match card and odds. Lifecycle
-- transitions are no longer part of this generic edit path: finishing a match
-- must go through the dedicated post-game/finalization workflow, and archiving
-- must go through archive_match after finalization.
create or replace function public.update_match_with_odds(
  p_match_id uuid,
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_status text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null or p_season_id is null or p_opponent_id is null
     or p_match_date is null or p_match_time is null then
    raise exception 'Match, saison, adversaire, date et heure requis.'
      using errcode = '22023';
  end if;
  if p_location not in ('domicile', 'exterieur') then
    raise exception 'Lieu invalide.' using errcode = '22023';
  end if;
  if p_status is distinct from 'a_venir' then
    raise exception 'Le statut se modifie via le workflow dédié du match.'
      using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Date de match hors limites.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.seasons s where s.id = p_season_id) then
    raise exception 'Saison introuvable.' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.opponents o where o.id = p_opponent_id) then
    raise exception 'Adversaire introuvable.' using errcode = 'P0002';
  end if;
  if p_win is null or p_draw is null or p_loss is null
     or p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
     or p_win > 100 or p_draw > 100 or p_loss > 100 then
    raise exception 'Cotes invalides.' using errcode = '22023';
  end if;

  select m.id into v_match_id
  from public.matches m
  where m.id = p_match_id
  for update;

  if v_match_id is null then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  update public.matches
  set season_id = p_season_id,
      opponent_id = p_opponent_id,
      match_date = p_match_date,
      match_time = p_match_time,
      location = p_location,
      status = 'a_venir',
      updated_at = now()
  where id = p_match_id;

  insert into public.match_odds (
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
$function$;

revoke execute on function public.update_match_with_odds(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric
) from public, anon;
grant execute on function public.update_match_with_odds(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric
) to authenticated, service_role;

comment on function public.update_match_with_odds(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric
) is 'Legacy edit RPC: edits upcoming match identity and odds only; lifecycle status transitions use dedicated workflows.';

commit;
