begin;

create or replace function private.match_postgame_correction_closes_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $function$
  with anchor as (
    select coalesce(
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
    ) as closes_at
  ), election as (
    select e.state::text as state, e.closes_at, e.closed_at
    from public.match_sport_motm_elections e
    where e.match_id = p_match_id
  )
  select case
    when anchor.closes_at is null then null
    when election.state = 'closed' and election.closed_at is not null then
      least(
        anchor.closes_at,
        election.closed_at,
        coalesce(election.closes_at, anchor.closes_at)
      )
    when election.closes_at is not null then
      least(anchor.closes_at, election.closes_at)
    else anchor.closes_at
  end
  from anchor
  left join election on true;
$function$;

comment on function private.match_postgame_correction_closes_at(uuid) is
  'Deadline immuable des corrections post-match : au plus validation initiale + 24 h, et exactement la clôture HDM lorsqu elle survient plus tôt.';

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

-- Un redémarrage exceptionnel du vote HDM ne doit jamais créer une nouvelle
-- fenêtre de 24 h. Il réutilise l'échéance de la validation initiale et est
-- refusé une fois cette échéance atteinte.
create or replace function private.admin_restart_match_motm_vote(
  p_match_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_has_ballot boolean;
  v_version integer;
  v_state public.sport_vote_state;
  v_closes_at timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.matches match where match.id = p_match_id) then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  select coalesce(
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
  ) into v_closes_at;

  if v_closes_at is null or now() >= v_closes_at then
    raise exception 'MOTM vote cannot be restarted after the post-match window closes'
      using errcode = '22023';
  end if;

  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  v_version := private.match_motm_anchor_version(p_match_id);
  v_state := (case when v_has_ballot then 'open' else 'cancelled' end)::public.sport_vote_state;

  insert into public.match_sport_motm_elections as election (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    v_state,
    case when v_has_ballot then now() else null end,
    case when v_has_ballot then v_closes_at else null end,
    null, 0, 0, now(), now()
  )
  on conflict (match_id) do update
  set finalization_version = excluded.finalization_version,
      state = excluded.state,
      opens_at = excluded.opens_at,
      closes_at = excluded.closes_at,
      closed_at = null,
      total_votes = 0,
      max_votes = 0,
      updated_at = now();

  update public.match_sport_workflows
  set vote_state = v_state, updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'restart_motm_vote', v_actor, v_reason,
    jsonb_build_object(
      'anchor_version', v_version,
      'state', v_state,
      'closes_at', v_closes_at
    )
  );

  return jsonb_build_object(
    'match_id', p_match_id,
    'state', v_state,
    'closes_at', case when v_has_ballot then v_closes_at else null end
  );
end;
$function$;

revoke all on function private.match_postgame_correction_closes_at(uuid)
  from public, anon, authenticated;
revoke all on function private.assert_match_postgame_correction_open(uuid)
  from public, anon, authenticated;
revoke all on function private.guard_postgame_correction_window()
  from public, anon, authenticated;
revoke all on function private.guard_finished_match_composition_write()
  from public, anon, authenticated;

commit;
