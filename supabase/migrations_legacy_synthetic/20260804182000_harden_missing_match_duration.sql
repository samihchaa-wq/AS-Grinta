begin;

-- Legacy matches created before sports-management duration tracking may have a
-- NULL planned_duration_minutes. Treat them as a standard 90-minute match for
-- lifecycle validation instead of letting SQL NULL semantics bypass the
-- post-game guard.
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

  if old.status = 'a_venir' and v_lock_at is not null and now() >= v_lock_at and v_identity_changed then
    raise exception 'Le match est verrouillé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  if old.status = 'a_venir' and new.status = 'annule'
     and v_lock_at is not null and now() >= v_lock_at then
    raise exception 'Un match ne peut plus être annulé après l’ouverture du Live.' using errcode = '22023';
  end if;

  if old.status in ('termine', 'archive') and new.status = 'annule' then
    raise exception 'Un match passé ne peut pas être annulé.' using errcode = '22023';
  end if;

  if old.status = 'a_venir'
     and new.status = 'termine'
     and old.match_type is distinct from 'entre_nous' then
    if old.kickoff_at is null
       or (
         now() < old.kickoff_at
           + make_interval(mins => coalesce(old.planned_duration_minutes, 90) + 15)
         and not exists (
           select 1
           from public.match_live_sessions live_session
           where live_session.match_id = old.id
             and live_session.state = 'finished'
         )
       ) then
      raise exception 'Le match ne peut pas être validé avant sa fin.' using errcode = '22023';
    end if;
  end if;

  return new;
end;
$function$;

commit;
