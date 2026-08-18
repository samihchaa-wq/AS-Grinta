-- A season must not become immutable while one of its matches is unfinished
-- or while a finalized match is still inside the post-match correction window.
-- Otherwise score/stat corrections can change prediction leaderboards after
-- season_awards have already been persisted.
--
-- Archive takes row locks on every non-cancelled match that can still affect
-- competition finality. This serializes season archive with a correction in
-- flight: either the correction commits first and its result is awarded, or
-- season archive commits first and any resumed finalization/correction is
-- rejected at the matches table boundary.

create or replace function private.assert_match_postgame_correction_open(p_match_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_status text;
  v_season_status text;
  v_closes_at timestamptz;
begin
  select
    match.status::text,
    season.status::text,
    private.match_postgame_correction_closes_at(match.id)
  into v_status, v_season_status, v_closes_at
  from public.matches match
  join public.seasons season on season.id = match.season_id
  where match.id = p_match_id;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  if v_status = 'archive' or v_season_status = 'archived' then
    raise exception 'La fenêtre de correction du match est fermée.'
      using errcode = '22023';
  end if;

  if v_status = 'termine'
     and (v_closes_at is null or now() >= v_closes_at) then
    raise exception 'La fenêtre de correction de 24 h est fermée.'
      using errcode = '22023';
  end if;
end;
$function$;

comment on function private.assert_match_postgame_correction_open(uuid) is
  'Refuse les corrections post-match après leur échéance ou après archivage de la saison.';

-- Defense in depth for the current and future server RPCs. The latest
-- finalize_match_postgame replacement no longer called the historical helper,
-- so enforce the contract where the authoritative score/status row changes.
create or replace function private.guard_match_postgame_finality_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.status = 'a_venir' and new.status = 'termine' then
    perform private.assert_match_postgame_correction_open(old.id);
  elsif old.status = 'termine'
        and new.status = 'termine'
        and (
          new.score_as_grinta is distinct from old.score_as_grinta
          or new.score_adverse is distinct from old.score_adverse
          or new.result_validated_at is distinct from old.result_validated_at
        )
  then
    perform private.assert_match_postgame_correction_open(old.id);
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_guard_match_postgame_finality_update
  on public.matches;
create trigger trg_guard_match_postgame_finality_update
before update of status, score_as_grinta, score_adverse, result_validated_at
on public.matches
for each row
execute function private.guard_match_postgame_finality_update();

create or replace function private.assert_season_archive_ready(p_season_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_match_id uuid;
  v_match_status text;
  v_closes_at timestamptz;
begin
  -- Lock every non-cancelled match that may still influence the season. Include
  -- already archived matches too: match archive must not be a way to bypass
  -- the 24 h season-award finality window.
  for v_match_id, v_match_status in
    select match.id, match.status::text
    from public.matches match
    where match.season_id = p_season_id
      and match.status in ('a_venir', 'termine', 'archive')
    order by match.id
    for update
  loop
    if v_match_status = 'a_venir' then
      raise exception
        'Impossible d’archiver la saison : un match n’est pas encore finalisé.'
        using errcode = '22023',
              detail = format('match_id=%s', v_match_id);
    end if;

    v_closes_at := private.match_postgame_correction_closes_at(v_match_id);

    if v_closes_at is null or now() < v_closes_at then
      raise exception
        'Impossible d’archiver la saison : un match possède encore une fenêtre de correction ouverte.'
        using errcode = '22023',
              detail = format(
                'match_id=%s status=%s correction_closes_at=%s',
                v_match_id,
                v_match_status,
                coalesce(v_closes_at::text, 'unknown')
              );
    end if;
  end loop;
end;
$function$;

comment on function private.assert_season_archive_ready(uuid) is
  'Verrouille les matchs non annules et refuse l archivage avant finalite sportive et post-match.';

-- Preserve the safe-empty-season recovery contract introduced in
-- 20260818161100. This migration only adds archive readiness; it must not make
-- harmless empty administrative recovery irreversible again.
create or replace function private.guard_season_competition_finality()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.status = 'archived'
     and new.status is distinct from old.status
     and private.season_has_historical_competition(old.id) then
    raise exception 'Une saison archivée avec des données de compétition ne peut pas être rouverte.'
      using errcode = '22023';
  end if;

  if old.season_predictions_locked_at is not null then
    if new.season_predictions_locked_at is null
       and private.season_prediction_lock_is_committed(old.id) then
      raise exception 'Les pronostics de saison révélés sont définitivement figés.'
        using errcode = '22023';
    end if;

    if new.season_predictions_locked_at is not null
       and new.season_predictions_locked_at is distinct from old.season_predictions_locked_at then
      raise exception 'La date de révélation des pronostics de saison est immuable.'
        using errcode = '22023';
    end if;
  end if;

  if old.status is distinct from 'archived'
     and new.status = 'archived'
  then
    perform private.assert_season_archive_ready(new.id);
  end if;

  return new;
end;
$function$;

revoke execute on function private.assert_match_postgame_correction_open(uuid)
  from public, anon, authenticated;
revoke execute on function private.guard_match_postgame_finality_update()
  from public, anon, authenticated;
revoke execute on function private.assert_season_archive_ready(uuid)
  from public, anon, authenticated;
