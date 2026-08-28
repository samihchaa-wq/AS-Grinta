begin;

-- Supprimer un match en cours ou déjà joué depuis les options d'administration.
--
-- Le garde-fou de cycle de vie refusait toute suppression dès l'ouverture du
-- Live (T-15) et pour tout match terminé ou archivé. Les écrans du calendrier
-- et de l'historique proposent pourtant l'action « Supprimer » : elle échouait
-- avec « Le match est verrouillé depuis l'ouverture du Live. » ou « Un match
-- passé ne peut pas être supprimé. », sans jamais aboutir.
--
-- La suppression complète d'un match reste une opération d'administration
-- vérifiée : elle passe uniquement par public.delete_match, réservée au staff.
-- Cette RPC pose désormais un drapeau de session local à la transaction, que le
-- garde-fou reconnaît. Toute autre suppression directe dans public.matches
-- reste bloquée exactement comme avant.

create or replace function private.guard_match_lifecycle_write()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_lock_at timestamptz;
  v_identity_changed boolean := false;
  v_full_match_delete boolean := coalesce(
    current_setting('as_grinta.allow_match_delete', true),
    'off'
  ) = 'on';
begin
  v_lock_at := case
    when old.kickoff_at is null then null
    else private.match_prediction_closes_at(old.kickoff_at)
  end;

  if tg_op = 'DELETE' then
    if not v_full_match_delete then
      if old.status in ('termine', 'archive') then
        raise exception 'Un match passé ne peut pas être supprimé.' using errcode = '22023';
      end if;
      if v_lock_at is not null and now() >= v_lock_at then
        raise exception 'Le match est verrouillé depuis l’ouverture du Live.' using errcode = '22023';
      end if;
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

alter function private.guard_match_lifecycle_write() owner to postgres;
revoke all on function private.guard_match_lifecycle_write()
  from public, anon, authenticated;

comment on function private.guard_match_lifecycle_write() is
  'Garde-fou du cycle de vie d''un match. La suppression complète par public.delete_match est la seule exception au verrou T-15 et au verrou des matchs passés.';

-- La composition d'un match terminé est immuable, et sa correction n'est
-- ouverte que 24 heures. Supprimer le match entier n'est pas une correction de
-- compte rendu : la suppression vérifiée doit rester possible au-delà de cette
-- fenêtre.
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
  v_full_match_delete boolean := tg_op = 'DELETE' and coalesce(
    current_setting('as_grinta.allow_match_delete', true),
    'off'
  ) = 'on';
begin
  v_match_id := case when tg_op = 'DELETE' then old.match_id else new.match_id end;

  select match.status::text into v_status
  from public.matches match
  where match.id = v_match_id;

  if v_status in ('termine', 'archive')
     and not v_is_cascade_delete
     and not v_full_match_delete then
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

alter function private.guard_finished_match_composition_write() owner to postgres;
revoke all on function private.guard_finished_match_composition_write()
  from public, anon, authenticated;

create or replace function public.delete_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  -- Drapeaux valables uniquement dans cette transaction.
  perform set_config('as_grinta.allow_postmatch_composition_write', 'on', true);
  perform set_config('as_grinta.allow_match_delete', 'on', true);

  delete from public.match_live_events where match_id = p_match_id;
  delete from public.match_live_sessions where match_id = p_match_id;
  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;
  delete from public.match_sport_motm_elections where match_id = p_match_id;
  delete from public.match_composition_entries where match_id = p_match_id;
  delete from public.match_composition_publications where match_id = p_match_id;
  delete from public.match_compositions where match_id = p_match_id;
  delete from public.match_sport_participant_events where match_id = p_match_id;
  delete from public.sport_availability_notification_events where match_id = p_match_id;
  delete from public.match_sport_finalization_versions where match_id = p_match_id;
  delete from public.match_sport_finalizations where match_id = p_match_id;
  delete from public.match_sport_participants where match_id = p_match_id;
  delete from public.match_sport_workflows where match_id = p_match_id;
  delete from public.match_attendance where match_id = p_match_id;
  delete from public.match_player_stats where match_id = p_match_id;
  delete from public.match_predictions where match_id = p_match_id;
  delete from public.match_odds where match_id = p_match_id;
  delete from public.push_delivery_log where match_id = p_match_id;
  delete from public.push_notification_log where match_id = p_match_id;

  delete from public.matches where id = p_match_id;
  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$function$;

alter function public.delete_match(uuid) owner to postgres;
revoke all on function public.delete_match(uuid) from public, anon;
grant execute on function public.delete_match(uuid) to authenticated, service_role;

comment on function public.delete_match(uuid) is
  'Suppression complète d''un match par le staff, y compris pendant le Live ou après sa validation. Efface le match et toutes ses données dépendantes.';

commit;
