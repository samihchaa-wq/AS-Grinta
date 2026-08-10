begin;

create or replace function private.match_postgame_correction_closes_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    (
      select election.closes_at
      from public.match_sport_motm_elections election
      where election.match_id = p_match_id
    ),
    (
      select finalization.validated_at + interval '24 hours'
      from public.match_sport_finalizations finalization
      where finalization.match_id = p_match_id
    ),
    (
      select match.result_validated_at + interval '24 hours'
      from public.matches match
      where match.id = p_match_id
    )
  );
$function$;

comment on function private.match_postgame_correction_closes_at(uuid) is
  'Deadline immuable des corrections post-match : clôture HDM si elle existe, sinon validation initiale + 24 h.';

create or replace function private.assert_match_postgame_correction_open(p_match_id uuid)
returns void
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_status text;
  v_closes_at timestamptz;
begin
  select match.status::text,
         private.match_postgame_correction_closes_at(match.id)
  into v_status, v_closes_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  if v_status = 'archive' then
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
  'Refuse toute correction post-match à partir de la clôture du vote HDM, sans prolonger la fenêtre lors des corrections.';

create or replace function private.guard_postgame_correction_window()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if old.status = 'termine'
     and (
       new.score_as_grinta is distinct from old.score_as_grinta
       or new.score_adverse is distinct from old.score_adverse
       or new.result_validated_at is distinct from old.result_validated_at
     ) then
    perform private.assert_match_postgame_correction_open(old.id);

    -- Le RPC historique réécrit result_validated_at à chaque correction.
    -- On conserve ici l'instant de validation initiale afin qu'une correction
    -- ne puisse jamais repousser la fenêtre de 24 heures.
    if old.result_validated_at is not null then
      new.result_validated_at := old.result_validated_at;
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_guard_postgame_correction_window on public.matches;
create trigger trg_guard_postgame_correction_window
before update on public.matches
for each row execute function private.guard_postgame_correction_window();

create or replace function private.guard_finished_match_composition_write()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_id uuid;
  v_status text;
  v_is_cascade_delete boolean := tg_op = 'DELETE' and pg_trigger_depth() > 1;
begin
  v_match_id := case when tg_op = 'DELETE' then old.match_id else new.match_id end;

  select match.status::text into v_status
  from public.matches match
  where match.id = v_match_id;

  if v_status in ('termine', 'archive') and not v_is_cascade_delete then
    if coalesce(
      current_setting('as_grinta.allow_postmatch_composition_write', true),
      'off'
    ) <> 'on' then
      raise exception 'Finished match compositions are immutable'
        using errcode = '55000';
    end if;

    perform private.assert_match_postgame_correction_open(v_match_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

comment on function private.guard_finished_match_composition_write() is
  'Autorise les écritures de composition post-match uniquement via le workflow prévu et jusqu’à la même échéance que le vote HDM.';

revoke all on function private.match_postgame_correction_closes_at(uuid)
  from public, anon, authenticated;
revoke all on function private.assert_match_postgame_correction_open(uuid)
  from public, anon, authenticated;
revoke all on function private.guard_postgame_correction_window()
  from public, anon, authenticated;
revoke all on function private.guard_finished_match_composition_write()
  from public, anon, authenticated;

commit;