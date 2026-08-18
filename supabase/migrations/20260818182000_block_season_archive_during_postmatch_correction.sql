-- A season must not become immutable while one of its finished matches is
-- still mutable. Otherwise an in-window score/stat correction can change the
-- prediction leaderboards after season_awards have already been persisted.

create or replace function private.assert_season_archive_ready(p_season_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_match_id uuid;
  v_closes_at timestamptz;
begin
  select match.id, deadline.closes_at
  into v_match_id, v_closes_at
  from public.matches match
  cross join lateral (
    select private.match_postgame_correction_closes_at(match.id) as closes_at
  ) deadline
  where match.season_id = p_season_id
    and match.status = 'termine'
    and (
      deadline.closes_at is null
      or now() < deadline.closes_at
    )
  order by deadline.closes_at nulls first, match.id
  limit 1;

  if found then
    raise exception
      'Impossible d’archiver la saison : un match possède encore une fenêtre de correction ouverte.'
      using errcode = '22023',
            detail = format(
              'match_id=%s correction_closes_at=%s',
              v_match_id,
              coalesce(v_closes_at::text, 'unknown')
            );
  end if;
end;
$function$;

comment on function private.assert_season_archive_ready(uuid) is
  'Refuse l archivage tant qu un match termine de la saison peut encore etre corrige.';

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

revoke execute on function private.assert_season_archive_ready(uuid)
  from public, anon, authenticated;
