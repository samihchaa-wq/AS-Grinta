-- Lock all pre-match mutations for "entre_nous" matches when Live opens (T-15).
-- Deletion keeps its separate T+24h lifecycle and is intentionally untouched.

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
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
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

  select
    m.status,
    coalesce(
      m.kickoff_at,
      ((m.match_date + m.match_time) at time zone 'Europe/Paris')
    ),
    m.updated_at
  into v_status, v_kickoff_at, v_updated_at
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
  if v_status <> 'a_venir' then
    raise exception 'Un match passé ou annulé ne se modifie plus depuis la fiche match.'
      using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Horaire du match introuvable : modification refusée.' using errcode = '22023';
  end if;
  if now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'Le match est verrouillé depuis l’ouverture du Live.'
      using errcode = '22023';
  end if;
  if ((p_match_date + p_match_time) at time zone 'Europe/Paris') <= now() then
    raise exception 'La date et l’heure doivent être à venir.' using errcode = '22023';
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

  perform private.configure_match_sport_workflow(p_match_id, 30);

  return true;
end;
$function$;

create or replace function public.admin_save_internal_composition(
  p_match_id uuid,
  p_team1_name text,
  p_team2_name text,
  p_entries jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_type text;
  v_status text;
  v_kickoff_at timestamptz;
  v_team1_name text := coalesce(nullif(btrim(p_team1_name), ''), 'Équipe 1');
  v_team2_name text := coalesce(nullif(btrim(p_team2_name), ''), 'Équipe 2');
  v_entry jsonb;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if char_length(v_team1_name) > 40 or char_length(v_team2_name) > 40 then
    raise exception 'Nom d''équipe trop long (40 caractères max).' using errcode = '22023';
  end if;

  select
    m.match_type,
    m.status,
    coalesce(
      m.kickoff_at,
      ((m.match_date + m.match_time) at time zone 'Europe/Paris')
    )
  into v_match_type, v_status, v_kickoff_at
  from public.matches m
  where m.id = p_match_id
  for update;

  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'La composition d’un match terminé ou annulé est verrouillée.'
      using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Horaire du match introuvable : composition refusée.' using errcode = '22023';
  end if;
  if now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'La composition est figée depuis l’ouverture du Live.'
      using errcode = '22023';
  end if;

  insert into public.match_internal_compositions (match_id, team1_name, team2_name, updated_by)
  values (p_match_id, v_team1_name, v_team2_name, (select auth.uid()))
  on conflict (match_id) do update
  set team1_name = excluded.team1_name,
      team2_name = excluded.team2_name,
      updated_by = excluded.updated_by,
      updated_at = now();

  delete from public.match_internal_composition_entries
  where match_id = p_match_id;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb))
  loop
    insert into public.match_internal_composition_entries (
      match_id, participant_id, team_no, sort_order
    ) values (
      p_match_id,
      (v_entry ->> 'participant_id')::uuid,
      nullif(v_entry ->> 'team_no', '')::smallint,
      coalesce((v_entry ->> 'sort_order')::integer, 0)
    );
  end loop;

  return public.admin_get_internal_composition(p_match_id);
end;
$function$;

create or replace function public.admin_save_internal_composition_v2(
  p_match_id uuid,
  p_team1_name text,
  p_team2_name text,
  p_team1_jersey text,
  p_team2_jersey text,
  p_entries jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_type text;
  v_status text;
  v_kickoff_at timestamptz;
  v_team1_name text := coalesce(nullif(btrim(p_team1_name), ''), 'Équipe 1');
  v_team2_name text := coalesce(nullif(btrim(p_team2_name), ''), 'Équipe 2');
  v_team1_jersey text := lower(btrim(coalesce(p_team1_jersey, '')));
  v_team2_jersey text := lower(btrim(coalesce(p_team2_jersey, '')));
  v_entry jsonb;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if char_length(v_team1_name) > 40 or char_length(v_team2_name) > 40 then
    raise exception 'Nom d''équipe trop long (40 caractères max).' using errcode = '22023';
  end if;
  if v_team1_jersey not in ('france', 'orange', 'blue')
      or v_team2_jersey not in ('france', 'orange', 'blue') then
    raise exception 'Maillot invalide.' using errcode = '22023';
  end if;
  if v_team1_jersey = v_team2_jersey then
    raise exception 'Les deux équipes doivent avoir des maillots différents.'
      using errcode = '22023';
  end if;

  select
    m.match_type,
    m.status,
    coalesce(
      m.kickoff_at,
      ((m.match_date + m.match_time) at time zone 'Europe/Paris')
    )
  into v_match_type, v_status, v_kickoff_at
  from public.matches m
  where m.id = p_match_id
  for update;

  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'La composition d’un match terminé ou annulé est verrouillée.'
      using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Horaire du match introuvable : composition refusée.' using errcode = '22023';
  end if;
  if now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'La composition est figée depuis l’ouverture du Live.'
      using errcode = '22023';
  end if;

  insert into public.match_internal_compositions (
    match_id,
    team1_name,
    team2_name,
    team1_jersey,
    team2_jersey,
    updated_by
  ) values (
    p_match_id,
    v_team1_name,
    v_team2_name,
    v_team1_jersey,
    v_team2_jersey,
    (select auth.uid())
  )
  on conflict (match_id) do update
  set team1_name = excluded.team1_name,
      team2_name = excluded.team2_name,
      team1_jersey = excluded.team1_jersey,
      team2_jersey = excluded.team2_jersey,
      updated_by = excluded.updated_by,
      updated_at = now();

  delete from public.match_internal_composition_entries
  where match_id = p_match_id;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb))
  loop
    insert into public.match_internal_composition_entries (
      match_id,
      participant_id,
      team_no,
      sort_order
    ) values (
      p_match_id,
      (v_entry ->> 'participant_id')::uuid,
      nullif(v_entry ->> 'team_no', '')::smallint,
      coalesce((v_entry ->> 'sort_order')::integer, 0)
    );
  end loop;

  return public.get_internal_composition(p_match_id);
end;
$function$;

create or replace function public.cancel_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select
    m.status,
    coalesce(
      m.kickoff_at,
      ((m.match_date + m.match_time) at time zone 'Europe/Paris')
    )
  into v_status, v_kickoff_at
  from public.matches m
  where m.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'Seul un match à venir peut être annulé.' using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Horaire du match introuvable : annulation refusée.' using errcode = '22023';
  end if;
  if now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'Le match est verrouillé depuis l’ouverture du Live.'
      using errcode = '22023';
  end if;

  update public.matches
  set status = 'annule',
      updated_at = now()
  where id = p_match_id
    and status = 'a_venir';

  return true;
end;
$function$;

revoke all on function public.update_internal_match(uuid, uuid, date, time without time zone, text, timestamptz) from public, anon;
grant execute on function public.update_internal_match(uuid, uuid, date, time without time zone, text, timestamptz) to authenticated, service_role;

revoke all on function public.admin_save_internal_composition(uuid, text, text, jsonb) from public, anon;
grant execute on function public.admin_save_internal_composition(uuid, text, text, jsonb) to authenticated, service_role;

revoke all on function public.admin_save_internal_composition_v2(uuid, text, text, text, text, jsonb) from public, anon;
grant execute on function public.admin_save_internal_composition_v2(uuid, text, text, text, text, jsonb) to authenticated, service_role;

revoke all on function public.cancel_match(uuid) from public, anon;
grant execute on function public.cancel_match(uuid) to authenticated, service_role;

revoke all on function public.admin_save_match_effectif(uuid, integer, jsonb, text) from public, anon;
grant execute on function public.admin_save_match_effectif(uuid, integer, jsonb, text) to authenticated, service_role;
