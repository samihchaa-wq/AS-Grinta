-- Keep all administrative pre-match mutations aligned with the Flutter T-15 lock.
-- Deletion keeps its separate T+24h lifecycle and player self-availability keeps
-- its existing kickoff deadline.

create or replace function private.assert_match_admin_edit_open(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select
    m.status,
    coalesce(
      m.kickoff_at,
      case
        when m.match_time is null then null
        else ((m.match_date + m.match_time) at time zone 'Europe/Paris')
      end
    )
  into v_status, v_kickoff_at
  from public.matches m
  where m.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'Un match passé ou annulé ne se modifie plus.'
      using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Horaire du match introuvable : modification refusée.'
      using errcode = '22023';
  end if;
  if now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'Le match est verrouillé depuis l’ouverture du Live.'
      using errcode = '22023';
  end if;
end;
$function$;

revoke all on function private.assert_match_admin_edit_open(uuid)
from public, anon, authenticated;
grant execute on function private.assert_match_admin_edit_open(uuid)
to service_role;

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
  v_match_type text;
  v_updated_at timestamptz;
  v_address text := nullif(btrim(p_address), '');
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null or p_season_id is null
     or p_match_date is null or p_match_time is null then
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

  perform private.assert_match_admin_edit_open(p_match_id);

  select m.match_type, m.updated_at
  into v_match_type, v_updated_at
  from public.matches m
  where m.id = p_match_id;

  if v_match_type is distinct from 'entre_nous' then
    raise exception 'Match entre nous introuvable.' using errcode = 'P0002';
  end if;
  if v_updated_at is distinct from p_expected_updated_at then
    raise exception 'Un autre administrateur a modifié ce match. Recharge l’écran avant d’enregistrer.'
      using errcode = '40001';
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

  perform private.assert_match_admin_edit_open(p_match_id);
  select match_type into v_match_type from public.matches where id = p_match_id;
  if v_match_type is distinct from 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;

  insert into public.match_internal_compositions (
    match_id, team1_name, team2_name, updated_by
  ) values (
    p_match_id, v_team1_name, v_team2_name, (select auth.uid())
  )
  on conflict (match_id) do update
  set team1_name = excluded.team1_name,
      team2_name = excluded.team2_name,
      updated_by = excluded.updated_by,
      updated_at = now();

  delete from public.match_internal_composition_entries where match_id = p_match_id;

  for v_entry in
    select value from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb))
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

  perform private.assert_match_admin_edit_open(p_match_id);
  select match_type into v_match_type from public.matches where id = p_match_id;
  if v_match_type is distinct from 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;

  insert into public.match_internal_compositions (
    match_id, team1_name, team2_name, team1_jersey, team2_jersey, updated_by
  ) values (
    p_match_id, v_team1_name, v_team2_name,
    v_team1_jersey, v_team2_jersey, (select auth.uid())
  )
  on conflict (match_id) do update
  set team1_name = excluded.team1_name,
      team2_name = excluded.team2_name,
      team1_jersey = excluded.team1_jersey,
      team2_jersey = excluded.team2_jersey,
      updated_by = excluded.updated_by,
      updated_at = now();

  delete from public.match_internal_composition_entries where match_id = p_match_id;

  for v_entry in
    select value from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb))
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

  return public.get_internal_composition(p_match_id);
end;
$function$;

-- Remove the obsolete staging-only overload; current clients use _v2.
drop function if exists public.admin_save_internal_composition(
  uuid, text, text, jsonb, text, text
);

create or replace function public.admin_save_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.publish_match_effectif(
    p_match_id, p_squad_size_limit, p_decisions, p_reason
  );
end;
$function$;

create or replace function public.cancel_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);

  update public.matches
  set status = 'annule', updated_at = now()
  where id = p_match_id and status = 'a_venir';

  if not found then
    raise exception 'Upcoming match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$function$;

create or replace function public.admin_add_or_reuse_match_guest(
  p_match_id uuid,
  p_guest_player_id uuid default null,
  p_first_name text default null,
  p_last_name text default null,
  p_is_goalkeeper boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);

  if p_guest_player_id is null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        lower(btrim(coalesce(p_first_name, ''))) || '|' ||
        lower(btrim(coalesce(p_last_name, ''))) || '|' ||
        coalesce(p_is_goalkeeper, false)::text,
        0
      )
    );
  end if;

  return private.add_or_reuse_match_guest(
    p_match_id, p_guest_player_id, p_first_name, p_last_name,
    p_is_goalkeeper, p_reason
  );
end;
$function$;

create or replace function public.admin_override_match_availability(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_private_comment text default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.override_match_availability(
    p_match_id, p_season_player_id, p_status, p_private_comment, p_reason
  );
end;
$function$;

create or replace function public.admin_publish_match_convocations(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.publish_match_convocations(p_match_id, p_reason);
end;
$function$;

create or replace function public.admin_recompute_match_convocations(
  p_match_id uuid,
  p_reset_overrides boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.recompute_match_convocations_internal(p_match_id, p_reset_overrides);
end;
$function$;

create or replace function public.admin_set_match_convocation(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_turn_should_consume boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.set_match_convocation(
    p_match_id, p_season_player_id, p_status, p_turn_should_consume, p_reason
  );
end;
$function$;

create or replace function public.admin_configure_match_sport_workflow(
  p_match_id uuid,
  p_squad_size_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.configure_match_sport_workflow(p_match_id, p_squad_size_limit);
end;
$function$;

create or replace function public.admin_sync_match_sport_workflow(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.sync_match_sport_workflow(p_match_id);
end;
$function$;

revoke all on function public.update_internal_match(
  uuid, uuid, date, time without time zone, text, timestamptz
) from public, anon;
grant execute on function public.update_internal_match(
  uuid, uuid, date, time without time zone, text, timestamptz
) to authenticated, service_role;

revoke all on function public.admin_save_internal_composition(
  uuid, text, text, jsonb
) from public, anon;
grant execute on function public.admin_save_internal_composition(
  uuid, text, text, jsonb
) to authenticated, service_role;

revoke all on function public.admin_save_internal_composition_v2(
  uuid, text, text, text, text, jsonb
) from public, anon;
grant execute on function public.admin_save_internal_composition_v2(
  uuid, text, text, text, text, jsonb
) to authenticated, service_role;

revoke all on function public.admin_save_match_effectif(
  uuid, integer, jsonb, text
) from public, anon;
grant execute on function public.admin_save_match_effectif(
  uuid, integer, jsonb, text
) to authenticated, service_role;

revoke all on function public.cancel_match(uuid) from public, anon;
grant execute on function public.cancel_match(uuid) to authenticated, service_role;

revoke all on function public.admin_add_or_reuse_match_guest(
  uuid, uuid, text, text, boolean, text
) from public, anon;
grant execute on function public.admin_add_or_reuse_match_guest(
  uuid, uuid, text, text, boolean, text
) to authenticated, service_role;

revoke all on function public.admin_override_match_availability(
  uuid, uuid, text, text, text
) from public, anon;
grant execute on function public.admin_override_match_availability(
  uuid, uuid, text, text, text
) to authenticated, service_role;

revoke all on function public.admin_publish_match_convocations(uuid, text)
from public, anon;
grant execute on function public.admin_publish_match_convocations(uuid, text)
to authenticated, service_role;

revoke all on function public.admin_recompute_match_convocations(uuid, boolean)
from public, anon;
grant execute on function public.admin_recompute_match_convocations(uuid, boolean)
to authenticated, service_role;

revoke all on function public.admin_set_match_convocation(
  uuid, uuid, text, boolean, text
) from public, anon;
grant execute on function public.admin_set_match_convocation(
  uuid, uuid, text, boolean, text
) to authenticated, service_role;

revoke all on function public.admin_configure_match_sport_workflow(uuid, integer)
from public, anon;
grant execute on function public.admin_configure_match_sport_workflow(uuid, integer)
to authenticated, service_role;

revoke all on function public.admin_sync_match_sport_workflow(uuid)
from public, anon;
grant execute on function public.admin_sync_match_sport_workflow(uuid)
to authenticated, service_role;
