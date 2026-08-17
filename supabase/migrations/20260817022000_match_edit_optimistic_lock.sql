create or replace function public.admin_update_match_complete(
  p_match_id uuid,
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_status text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_expected_updated_at timestamptz,
  p_squad_size_limit integer default null,
  p_address text default null,
  p_remember_address_as_default boolean default false,
  p_match_type text default 'championnat',
  p_jersey_note text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
  v_updated_at timestamptz;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_expected_updated_at is null then
    raise exception 'Recharge le match avant de l’enregistrer.' using errcode = '40001';
  end if;

  select match.status, match.kickoff_at, match.updated_at
  into v_status, v_kickoff_at, v_updated_at
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_updated_at is distinct from p_expected_updated_at then
    raise exception 'Un autre administrateur a modifié ce match. Recharge l’écran avant d’enregistrer.'
      using errcode = '40001';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'Un match passé ou annulé ne se modifie plus depuis la fiche match.' using errcode = '22023';
  end if;
  if v_kickoff_at is not null and now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'Le match est verrouillé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  if p_squad_size_limit is not null then
    perform private.update_match_with_sport_limit(
      p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_status, p_win, p_draw, p_loss, p_squad_size_limit
    );
  else
    perform public.update_match_with_odds(
      p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_status, p_win, p_draw, p_loss
    );
  end if;

  perform public.admin_set_match_address(p_match_id, p_address, p_remember_address_as_default);
  perform public.admin_set_match_type(p_match_id, p_match_type);
  perform public.admin_set_match_jersey(p_match_id, p_jersey_note);

  return true;
end;
$function$;

revoke all on function public.admin_update_match_complete(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric, timestamptz, integer, text, boolean, text, text
) from public, anon;
grant execute on function public.admin_update_match_complete(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric, timestamptz, integer, text, boolean, text, text
) to authenticated, service_role;

create or replace function public.update_internal_match(
  p_match_id uuid,
  p_season_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_address text,
  p_expected_updated_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_status text;
  v_updated_at timestamptz;
  v_address text := nullif(btrim(p_address), '');
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null or p_season_id is null or p_match_date is null or p_match_time is null then
    raise exception 'Match, saison, date et heure requis.' using errcode = '22023';
  end if;
  if p_expected_updated_at is null then
    raise exception 'Recharge le match avant de l’enregistrer.' using errcode = '40001';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Date de match hors limites.' using errcode = '22023';
  end if;
  if v_address is not null and char_length(v_address) > 300 then
    raise exception 'Address cannot exceed 300 characters' using errcode = '22023';
  end if;

  select m.status, m.updated_at
  into v_status, v_updated_at
  from public.matches m
  where m.id = p_match_id
    and m.match_type = 'entre_nous'
  for update;

  if v_status is null then
    raise exception 'Match entre nous introuvable.' using errcode = 'P0002';
  end if;
  if v_updated_at is distinct from p_expected_updated_at then
    raise exception 'Un autre administrateur a modifié ce match. Recharge l’écran avant d’enregistrer.'
      using errcode = '40001';
  end if;
  if not exists (select 1 from public.seasons s where s.id = p_season_id) then
    raise exception 'Saison introuvable.' using errcode = 'P0002';
  end if;

  update public.matches
  set season_id = p_season_id,
      match_date = p_match_date,
      match_time = p_match_time,
      address = v_address,
      updated_at = now()
  where id = p_match_id;

  if v_status = 'a_venir' then
    perform private.configure_match_sport_workflow(p_match_id, 30);
  end if;

  return true;
end;
$function$;

revoke all on function public.update_internal_match(
  uuid, uuid, date, time without time zone, text, timestamptz
) from public, anon;
grant execute on function public.update_internal_match(
  uuid, uuid, date, time without time zone, text, timestamptz
) to authenticated, service_role;
