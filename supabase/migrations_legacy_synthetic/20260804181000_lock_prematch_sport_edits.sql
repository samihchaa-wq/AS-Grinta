begin;

-- Tighten the status transition guard: even a finished Live cannot publish a
-- result before kickoff. For normal matches, a finished Live may then validate
-- before the duration fallback; without Live, duration + 15 min remains due.
create or replace function private.guard_match_lifecycle_write()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_lock_at timestamptz;
  v_identity_changed boolean := false;
begin
  v_lock_at := case
    when old.kickoff_at is null then null
    else private.match_prediction_closes_at(old.kickoff_at)
  end;

  if tg_op = 'DELETE' then
    if old.status in ('termine', 'archive') then
      raise exception 'Un match passé ne peut pas être supprimé.' using errcode = '22023';
    end if;
    if v_lock_at is not null and now() >= v_lock_at then
      raise exception 'Le match est verrouillé depuis l’ouverture du Live.' using errcode = '22023';
    end if;
    return old;
  end if;

  v_identity_changed :=
    new.season_id is distinct from old.season_id
    or new.opponent_id is distinct from old.opponent_id
    or new.match_date is distinct from old.match_date
    or new.match_time is distinct from old.match_time
    or new.kickoff_at is distinct from old.kickoff_at
    or new.location is distinct from old.location
    or new.planned_duration_minutes is distinct from old.planned_duration_minutes
    or new.address is distinct from old.address
    or new.match_type is distinct from old.match_type
    or new.jersey_note is distinct from old.jersey_note;

  if old.status in ('termine', 'archive') and v_identity_changed then
    raise exception 'Un match passé se corrige via le compte rendu, pas via la fiche match.' using errcode = '22023';
  end if;

  if old.status = 'a_venir'
     and v_lock_at is not null
     and now() >= v_lock_at
     and v_identity_changed then
    raise exception 'Le match est verrouillé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  if old.status = 'a_venir'
     and new.status = 'annule'
     and v_lock_at is not null
     and now() >= v_lock_at then
    raise exception 'Un match ne peut plus être annulé après l’ouverture du Live.' using errcode = '22023';
  end if;

  if old.status in ('termine', 'archive') and new.status = 'annule' then
    raise exception 'Un match passé ne peut pas être annulé.' using errcode = '22023';
  end if;

  if old.status = 'a_venir' and new.status = 'termine' then
    if old.kickoff_at is null or now() < old.kickoff_at then
      raise exception 'Le match ne peut pas être terminé avant le coup d’envoi.' using errcode = '22023';
    end if;

    if old.match_type <> 'entre_nous'
       and now() < old.kickoff_at + make_interval(mins => old.planned_duration_minutes + 15)
       and not exists (
         select 1
         from public.match_live_sessions live_session
         where live_session.match_id = old.id
           and live_session.state = 'finished'
       ) then
      raise exception 'Le match ne peut pas être validé avant sa fin.' using errcode = '22023';
    end if;
  end if;

  return new;
end;
$function$;

-- Admin effectif/composition screens remain readable after T-15, but their
-- generic prematch mutation RPCs become read-only. Live-specific RPCs remain
-- untouched and are the only way to evolve the on-field state during a match.
create or replace function public.admin_publish_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  select match.status, match.kickoff_at
  into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status = 'a_venir'
     and v_kickoff_at is not null
     and now() >= v_kickoff_at - interval '15 minutes' then
    raise exception 'L’effectif est figé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  return private.publish_match_effectif(
    p_match_id,
    p_squad_size_limit,
    p_decisions,
    p_reason
  );
end;
$function$;

create or replace function public.admin_save_match_composition(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_allow_squad_size_exception boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  select match.status, match.kickoff_at
  into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status = 'a_venir'
     and v_kickoff_at is not null
     and now() >= v_kickoff_at - interval '15 minutes' then
    raise exception 'La composition est figée depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  perform private.save_match_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    p_allow_squad_size_exception,
    p_reason
  );
  return private.publish_match_composition(
    p_match_id,
    p_allow_squad_size_exception,
    p_reason
  );
end;
$function$;

create or replace function public.admin_publish_match_composition(
  p_match_id uuid,
  p_allow_squad_size_exception boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  select match.status, match.kickoff_at
  into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status = 'a_venir'
     and v_kickoff_at is not null
     and now() >= v_kickoff_at - interval '15 minutes' then
    raise exception 'La composition est figée depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  return private.publish_match_composition(
    p_match_id,
    p_allow_squad_size_exception,
    p_reason
  );
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
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  select match.status, match.kickoff_at
  into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status = 'a_venir'
     and v_kickoff_at is not null
     and now() >= v_kickoff_at - interval '15 minutes' then
    raise exception 'L’effectif est figé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  return private.add_or_reuse_match_guest(
    p_match_id,
    p_guest_player_id,
    p_first_name,
    p_last_name,
    p_is_goalkeeper,
    p_reason
  );
end;
$function$;

create or replace function public.admin_remove_match_guest(
  p_match_id uuid,
  p_participant_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  select match.status, match.kickoff_at
  into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status = 'a_venir'
     and v_kickoff_at is not null
     and now() >= v_kickoff_at - interval '15 minutes' then
    raise exception 'L’effectif est figé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  return private.remove_match_guest(p_match_id, p_participant_id, p_reason);
end;
$function$;

commit;
