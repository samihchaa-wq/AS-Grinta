-- A season must not become immutable while one of its finished matches is
-- still mutable. Otherwise an in-window score/stat correction can change the
-- prediction leaderboards after season_awards have already been persisted.
--
-- Archive also takes row locks on the finished matches before deciding that
-- their correction windows are closed. That serializes archive with a
-- correction already in flight: either the correction commits first and its
-- result is awarded, or archive commits first and the correction is then
-- rejected because its parent season is archived.

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

create or replace function private.assert_season_archive_ready(p_season_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_match_id uuid;
  v_closes_at timestamptz;
begin
  -- Lock every currently finished match in a deterministic order. If a
  -- correction already owns one of these rows, archive waits for it and then
  -- evaluates the committed corrected state before titles are awarded.
  for v_match_id in
    select match.id
    from public.matches match
    where match.season_id = p_season_id
      and match.status = 'termine'
    order by match.id
    for update
  loop
    v_closes_at := private.match_postgame_correction_closes_at(v_match_id);

    if v_closes_at is null or now() < v_closes_at then
      raise exception
        'Impossible d’archiver la saison : un match possède encore une fenêtre de correction ouverte.'
        using errcode = '22023',
              detail = format(
                'match_id=%s correction_closes_at=%s',
                v_match_id,
                coalesce(v_closes_at::text, 'unknown')
              );
    end if;
  end loop;
end;
$function$;

comment on function private.assert_season_archive_ready(uuid) is
  'Verrouille les matchs termines et refuse l archivage tant qu une correction reste possible.';

create or replace function private.guard_season_competition_finality()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.status = 'archived' and new.status is distinct from old.status then
    raise exception 'Une saison archivée ne peut pas être rouverte.'
      using errcode = '22023';
  end if;

  if old.season_predictions_locked_at is not null
     and new.season_predictions_locked_at is distinct from old.season_predictions_locked_at then
    raise exception 'Les pronostics de saison révélés sont définitivement figés.'
      using errcode = '22023';
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
revoke execute on function private.assert_season_archive_ready(uuid)
  from public, anon, authenticated;
