begin;

-- A season archive is a competition finalization boundary. Serialize it with
-- match mutations, reject unfinished/correctable matches, then capture the
-- definitive prediction roster before any title is awarded.

create or replace function private.assert_season_can_archive(
  p_season_id uuid
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if p_season_id is null then
    raise exception 'Season id is required' using errcode = '22023';
  end if;

  -- A concurrent finalization/correction must finish before the archive reads
  -- match state and awards titles. The season row is already locked by the
  -- caller; these row locks close the opposite race on existing matches.
  perform 1
  from public.matches match
  where match.season_id = p_season_id
  for update;

  if exists (
    select 1
    from public.matches match
    where match.season_id = p_season_id
      and match.status not in ('termine', 'archive', 'annule')
  ) then
    raise exception
      'Une saison avec des matchs non terminés ne peut pas être archivée.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.matches match
    where match.season_id = p_season_id
      and match.status = 'termine'
      and private.match_postgame_correction_closes_at(match.id) > now()
  ) then
    raise exception
      'Une saison ne peut pas être archivée pendant une fenêtre de correction de match.'
      using errcode = '22023';
  end if;
end;
$function$;

revoke all on function private.assert_season_can_archive(uuid)
  from public, anon, authenticated;

-- Match creation is the one mutation that an archive cannot discover by
-- locking the season's existing match rows. A SHARE lock on the parent season
-- serializes INSERT / moves into a season with its status update. Existing
-- match UPDATE / DELETE statements are already serialized by the match-row
-- locks taken by assert_season_can_archive(); after waiting, this trigger sees
-- the committed archived status and rejects any late mutation.
create or replace function private.guard_match_season_finality()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_source_status text;
  v_target_status text;
  v_archive_only boolean := false;
begin
  if tg_op = 'INSERT' then
    select season.status
    into v_target_status
    from public.seasons season
    where season.id = new.season_id
    for share;

    if not found or v_target_status <> 'open' then
      raise exception 'Un match ne peut être ajouté qu''à une saison ouverte.'
        using errcode = '22023';
    end if;

    return new;
  end if;

  select season.status
  into v_source_status
  from public.seasons season
  where season.id = old.season_id;

  if tg_op = 'DELETE' then
    if v_source_status = 'archived' then
      raise exception 'Les matchs d''une saison archivée sont immuables.'
        using errcode = '22023';
    end if;

    return old;
  end if;

  if new.season_id is distinct from old.season_id then
    if v_source_status = 'archived' then
      raise exception 'Les matchs d''une saison archivée sont immuables.'
        using errcode = '22023';
    end if;

    select season.status
    into v_target_status
    from public.seasons season
    where season.id = new.season_id
    for share;

    if not found or v_target_status <> 'open' then
      raise exception 'Un match ne peut être déplacé que vers une saison ouverte.'
        using errcode = '22023';
    end if;

    return new;
  end if;

  if v_source_status = 'archived' then
    -- Keep the harmless housekeeping transition supported when a season was
    -- archived with a finished match after its correction window had closed.
    v_archive_only := old.status = 'termine'
      and new.status = 'archive'
      and (
        to_jsonb(new) - array['status', 'updated_at']::text[]
      ) = (
        to_jsonb(old) - array['status', 'updated_at']::text[]
      );

    if not v_archive_only then
      raise exception 'Les matchs d''une saison archivée sont immuables.'
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function private.guard_match_season_finality()
  from public, anon, authenticated;

create or replace function private.guard_season_competition_finality()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.status = 'archived'
     and old.status is distinct from 'archived' then
    perform private.assert_season_can_archive(new.id);
  end if;

  if old.status = 'archived'
     and new.status is distinct from old.status
     and private.season_has_historical_competition(old.id) then
    raise exception
      'Une saison archivée avec des données de compétition ne peut pas être rouverte.'
      using errcode = '22023';
  end if;

  if old.season_predictions_locked_at is not null then
    if new.season_predictions_locked_at is null
       and private.season_prediction_lock_is_committed(old.id) then
      raise exception 'Les pronostics de saison révélés sont définitivement figés.'
        using errcode = '22023';
    end if;

    if new.season_predictions_locked_at is not null
       and new.season_predictions_locked_at
         is distinct from old.season_predictions_locked_at then
      raise exception 'La date de révélation des pronostics de saison est immuable.'
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function private.finalize_season_competition_transition()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_archiving boolean := false;
  v_locking boolean := false;
  v_unlocking boolean := false;
  v_reopening boolean := false;
  v_capture_reason text;
  v_captured_at timestamptz;
begin
  if tg_op = 'INSERT' then
    v_archiving := new.status = 'archived';
    v_locking := new.season_predictions_locked_at is not null;

    -- INSERT does not pass through the UPDATE guard.
    if v_archiving then
      perform private.assert_season_can_archive(new.id);
    end if;
  else
    v_archiving := old.status is distinct from 'archived'
      and new.status = 'archived';
    v_locking := old.season_predictions_locked_at is null
      and new.season_predictions_locked_at is not null;
    v_unlocking := old.season_predictions_locked_at is not null
      and new.season_predictions_locked_at is null;
    v_reopening := old.status = 'archived'
      and new.status is distinct from 'archived';
  end if;

  if v_unlocking then
    if private.season_prediction_lock_is_committed(new.id) then
      raise exception 'Les pronostics de saison révélés sont définitivement figés.'
        using errcode = '22023';
    end if;

    delete from public.season_prediction_roster_captures
    where season_id = new.id;
  end if;

  -- Safe empty-season recovery must not retain the archive snapshot. A later
  -- lock has to capture the then-current roster, not the previously reopened
  -- one.
  if v_reopening then
    delete from public.season_prediction_roster_captures
    where season_id = new.id;
  end if;

  -- An archive without a committed lock always captures the final live roster.
  -- This also repairs a stale empty-season capture left by an older reopen.
  if v_archiving and new.season_predictions_locked_at is null then
    delete from public.season_prediction_roster_captures
    where season_id = new.id;
  end if;

  if (v_locking or v_archiving)
     and not exists (
       select 1
       from public.season_prediction_roster_captures capture
       where capture.season_id = new.id
     ) then
    v_capture_reason := case when v_locking then 'lock' else 'archive' end;
    v_captured_at := case
      when v_locking then new.season_predictions_locked_at
      else now()
    end;

    insert into public.season_prediction_roster_captures(
      season_id,
      captured_at,
      capture_reason
    ) values (
      new.id,
      v_captured_at,
      v_capture_reason
    );

    insert into public.season_prediction_roster_members(
      season_id,
      season_player_id,
      category
    )
    select
      player.season_id,
      player.id,
      case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
    from public.season_players player
    where player.season_id = new.id
      and player.is_active
      and not player.is_coach;
  end if;

  if v_archiving then
    if not exists (
      select 1
      from public.season_prediction_roster_captures capture
      where capture.season_id = new.id
    ) then
      raise exception 'Le snapshot final de la saison n''a pas pu être figé.'
        using errcode = '23514';
    end if;

    -- This is deliberately in the same trigger, after the snapshot. Any title
    -- or badge failure rolls the status change and the snapshot back together.
    perform public.award_season_titles(new.id);
  end if;

  return new;
end;
$function$;

revoke all on function private.finalize_season_competition_transition()
  from public, anon, authenticated;

drop trigger if exists trg_award_titles on public.seasons;
drop trigger if exists trg_sync_season_prediction_roster_snapshot
  on public.seasons;
drop trigger if exists trg_finalize_season_competition on public.seasons;

create trigger trg_finalize_season_competition
after insert or update of status, season_predictions_locked_at
on public.seasons
for each row
execute function private.finalize_season_competition_transition();

drop trigger if exists trg_guard_match_season_finality on public.matches;

create trigger trg_guard_match_season_finality
before insert or update or delete
on public.matches
for each row
execute function private.guard_match_season_finality();

comment on function private.assert_season_can_archive(uuid) is
  'Serializes season archival with match mutations and rejects unfinished matches or an open post-match correction window.';

comment on function private.finalize_season_competition_transition() is
  'Atomically maintains the season-prediction roster snapshot and awards titles only after the final snapshot exists.';

comment on function private.guard_match_season_finality() is
  'Serializes match additions with season archival and rejects mutations that would alter an archived season.';

commit;
