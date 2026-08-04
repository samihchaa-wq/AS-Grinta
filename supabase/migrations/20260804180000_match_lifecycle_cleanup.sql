begin;

create or replace function private.match_prediction_closes_at(p_kickoff_at timestamptz)
returns timestamptz
language sql
stable
strict
set search_path to ''
as $function$
  select p_kickoff_at - interval '15 minutes';
$function$;

comment on function private.match_prediction_closes_at(timestamptz) is
  'Instant commun de fermeture du prono et d ouverture du Live: T-15 minutes.';

revoke all on function private.match_prediction_closes_at(timestamptz)
  from public, anon, authenticated;

create or replace function public.guard_match_prediction_window()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_kickoff timestamptz;
  v_match_status text;
  v_closed_at timestamptz;
begin
  if (select auth.uid()) is not null and pg_trigger_depth() <= 1 then
    if tg_op = 'UPDATE' and new.match_id is distinct from old.match_id then
      raise exception 'Le match d’un pronostic ne peut pas être modifié.' using errcode = '22023';
    end if;
    new.profile_id := (select auth.uid());
  end if;

  if new.is_filled then
    select m.kickoff_at, m.status, m.predictions_closed_at
    into v_kickoff, v_match_status, v_closed_at
    from public.matches m
    where m.id = new.match_id;

    if v_kickoff is null
       or v_match_status <> 'a_venir'
       or now() < private.match_features_open_at(v_kickoff)
       or now() >= private.match_prediction_closes_at(v_kickoff)
       or (v_closed_at is not null and now() >= v_closed_at) then
      raise exception 'Pronostic fermé' using errcode = '22023';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.save_match_prediction(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_match public.matches%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Utilisateur non authentifié.' using errcode = '42501';
  end if;
  if not private.is_active_profile() then
    raise exception 'Compte inactif.' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match requis.' using errcode = '22023';
  end if;
  if p_score_as_grinta is null or p_score_adverse is null
     or p_score_as_grinta not between 0 and 99
     or p_score_adverse not between 0 and 99 then
    raise exception 'Les scores doivent être compris entre 0 et 99.' using errcode = '22023';
  end if;

  select * into v_match
  from public.matches
  where id = p_match_id
  for share;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  if v_match.kickoff_at is null
     or v_match.status <> 'a_venir'
     or now() < private.match_features_open_at(v_match.kickoff_at)
     or now() >= private.match_prediction_closes_at(v_match.kickoff_at)
     or (v_match.predictions_closed_at is not null and now() >= v_match.predictions_closed_at) then
    raise exception 'Ce match n’est pas ouvert aux pronostics.' using errcode = '22023';
  end if;

  insert into public.match_predictions (
    match_id, profile_id, predicted_score_as_grinta, predicted_score_adverse,
    is_filled, updated_at
  ) values (
    p_match_id, v_actor_id, p_score_as_grinta, p_score_adverse, true, now()
  )
  on conflict (match_id, profile_id) do update
  set predicted_score_as_grinta = excluded.predicted_score_as_grinta,
      predicted_score_adverse = excluded.predicted_score_adverse,
      is_filled = true,
      updated_at = now();

  return true;
end;
$function$;

create or replace function public.push_prediction_j5_notifications()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match record;
  v_sent integer := 0;
begin
  if private.is_feature_enabled('notifications_paused') then
    return 0;
  end if;

  for v_match in
    select m.id
    from public.matches m
    where m.status = 'a_venir'
      and m.kickoff_at is not null
      and now() >= private.match_prediction_notification_at(m.kickoff_at)
      and now() < private.match_prediction_closes_at(m.kickoff_at)
      and (m.predictions_closed_at is null or now() < m.predictions_closed_at)
    order by m.kickoff_at
  loop
    insert into public.push_notification_log(match_id, kind, sent_at)
    values (v_match.id, 'prediction_j5', now())
    on conflict do nothing;
    if found then
      perform public.internal_push_notify('prediction_j5', v_match.id);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$function$;

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

  if old.status = 'a_venir' and new.status = 'termine' and old.match_type <> 'entre_nous' then
    if old.kickoff_at is null
       or (
         now() < old.kickoff_at + make_interval(mins => old.planned_duration_minutes + 15)
         and not exists (
           select 1 from public.match_live_sessions live_session
           where live_session.match_id = old.id and live_session.state = 'finished'
         )
       ) then
      raise exception 'Le match ne peut pas être validé avant sa fin.' using errcode = '22023';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_guard_match_lifecycle_write on public.matches;
create trigger trg_guard_match_lifecycle_write
before update or delete on public.matches
for each row execute function private.guard_match_lifecycle_write();

create or replace function public.admin_update_match_complete(
  p_match_id uuid,
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_status text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_squad_size_limit integer default null,
  p_address text default null,
  p_remember_address_as_default boolean default false,
  p_match_type text default 'championnat',
  p_jersey_note text default null
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select match.status, match.kickoff_at into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'Un match passé ou annulé ne se modifie plus depuis la fiche match.' using errcode = '22023';
  end if;
  if v_kickoff_at is not null and now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'Le match est verrouillé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  if p_squad_size_limit is not null then
    perform private.update_match_with_sport_limit(
      p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_status, p_win, p_draw, p_loss, p_squad_size_limit
    );
  else
    perform public.update_match_with_odds(
      p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_status, p_win, p_draw, p_loss
    );
  end if;

  perform public.admin_set_match_address(p_match_id, p_address, p_remember_address_as_default);
  perform public.admin_set_match_type(p_match_id, p_match_type);
  perform public.admin_set_match_jersey(p_match_id, p_jersey_note);

  return true;
end;
$function$;

create or replace function private.match_motm_opens_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $function$
  select finalization.validated_at
  from public.match_sport_finalizations finalization
  where finalization.match_id = p_match_id;
$function$;

comment on function private.match_motm_opens_at(uuid) is
  'Le vote HDM ouvre à la validation initiale du compte rendu.';

create or replace function private.ensure_match_motm_election(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_exists boolean;
  v_has_ballot boolean;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_version integer;
begin
  select true into v_exists
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;
  if v_exists then return; end if;

  select private.match_motm_opens_at(p_match_id) into v_opens_at;
  if v_opens_at is null then return; end if;

  if exists (
    select 1 from public.matches match
    where match.id = p_match_id and match.status = 'annule'
  ) then
    return;
  end if;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  if not v_has_ballot then return; end if;

  v_closes_at := v_opens_at + interval '24 hours';
  v_version := private.match_motm_anchor_version(p_match_id);

  insert into public.match_sport_motm_elections (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id, v_version, 'draft'::public.sport_vote_state,
    v_opens_at, v_closes_at, null, 0, 0, now(), now()
  )
  on conflict (match_id) do nothing;

  update public.match_sport_workflows
  set vote_state = 'draft', updated_at = now()
  where match_id = p_match_id;
end;
$function$;

create or replace function private.close_due_match_motm_elections()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row record;
  v_processed integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then return 0; end if;

  for v_row in
    select election.match_id
    from public.match_sport_motm_elections election
    where election.state in ('draft', 'open')
    order by election.closes_at nulls last, election.match_id
    for update skip locked
  loop
    perform private.transition_match_motm_election(v_row.match_id);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$function$;

update public.match_sport_motm_elections election
set opens_at = finalization.validated_at,
    closes_at = finalization.validated_at + interval '24 hours',
    updated_at = now()
from public.match_sport_finalizations finalization
where finalization.match_id = election.match_id
  and election.state in ('draft', 'open');

commit;
