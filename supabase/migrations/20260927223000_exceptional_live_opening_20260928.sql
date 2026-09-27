-- Exception ponctuelle du 28 septembre 2026.
--
-- Pour le match de 21:00 à Paris, la frontière commune Live / fermeture des
-- pronostics / gel Effectif-Compo est avancée à 19:00 Paris. La règle reste
-- strictement T-15 pour tous les autres matchs.
begin;

create or replace function private.match_prediction_closes_at(
  p_kickoff_at timestamptz
)
returns timestamptz
language sql
stable
strict
set search_path = ''
as $function$
  select case
    -- Exception décidée pour AS Grinta - Toulouse Métropole du 28/09/2026 :
    -- coup d'envoi 21:00 Paris (19:00 UTC), Live/pronos/verrou à 19:00 Paris
    -- (17:00 UTC). Toute autre rencontre conserve T-15.
    when p_kickoff_at = timestamptz '2026-09-28 19:00:00+00'
      then timestamptz '2026-09-28 17:00:00+00'
    else p_kickoff_at - interval '15 minutes'
  end;
$function$;

comment on function private.match_prediction_closes_at(timestamptz) is
  'Frontière commune fermeture pronostics / ouverture Live / verrou pré-match. Exception unique le 28/09/2026 à 19:00 Paris pour le match de 21:00 ; sinon T-15.';


CREATE OR REPLACE FUNCTION private.confirm_start_match_live(p_match_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_state public.match_live_state;
  v_kickoff_at timestamptz;
  v_field_count integer;
  v_composition_version integer;
  v_snapshot_map jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, match.kickoff_at
  into v_state, v_kickoff_at
  from public.match_live_sessions session
  join public.matches match on match.id = session.match_id
  where session.match_id = p_match_id
  for update of session;

  if not found then
    raise exception 'Open the live workspace before starting the match'
      using errcode = '22023';
  end if;
  if v_state <> 'not_started' then
    raise exception 'The match has already been started' using errcode = '22023';
  end if;
  if v_kickoff_at is null
     or now() < private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'Le Live n’est pas encore ouvert.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.match_composition_entries entry
    left join public.match_sport_participants participant
      on participant.match_id = entry.match_id
     and participant.id = entry.participant_id
    where entry.match_id = p_match_id
      and entry.zone in ('field', 'bench')
      and coalesce(participant.convocation_status::text, '') <> 'convoked'
  ) then
    raise exception 'Live lineup is stale after a convocation change'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.match_sport_participants participant
    where participant.match_id = p_match_id
      and participant.is_eligible
      and participant.convocation_status = 'convoked'
      and participant.promoted_after_withdrawal_at is not null
      and not exists (
        select 1
        from public.match_composition_entries entry
        where entry.match_id = p_match_id
          and entry.participant_id = participant.id
          and entry.zone in ('field', 'bench')
      )
  ) then
    raise exception 'Live lineup is missing a promoted player'
      using errcode = '22023';
  end if;

  select count(*) filter (where zone = 'field')
  into v_field_count
  from public.match_composition_entries
  where match_id = p_match_id;

  if v_field_count > 11 then
    raise exception 'A lineup cannot contain more than 11 starters'
      using errcode = '22023';
  end if;

  -- Le coup d'envoi publie l'équipe réellement alignée : c'est elle que les
  -- joueurs doivent voir, pas la dernière publication d'avant-match.
  perform private.publish_match_live_composition(p_match_id);

  select composition.version
  into v_composition_version
  from public.match_compositions composition
  where composition.match_id = p_match_id;

  select coalesce(
    jsonb_object_agg(entry.participant_id::text, entry.zone),
    '{}'::jsonb
  )
  into v_snapshot_map
  from public.match_composition_entries entry
  where entry.match_id = p_match_id
    and entry.zone in ('field', 'bench');

  update public.match_live_sessions
  set state = 'running',
      started_at = now(),
      running_since = now(),
      elapsed_seconds = 0,
      half = 1,
      starting_composition_version = v_composition_version,
      starting_lineup_snapshot = v_snapshot_map,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id,
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    p_match_id,
    'start_match_live',
    v_actor,
    v_reason,
    jsonb_build_object('field_count', v_field_count)
  );

  return private.match_live_snapshot(p_match_id);
end;
$function$;

CREATE OR REPLACE FUNCTION private.open_match_live_workspace(p_match_id uuid, p_planned_duration_minutes integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_match_status text;
  v_kickoff_at timestamptz;
  v_default_duration integer;
  v_existing_state public.match_live_state;
  v_publication_snapshot jsonb;
  v_formation text;
  v_has_entries boolean;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach, administrator or moderator role required'
      using errcode = '42501';
  end if;

  select match.status, match.kickoff_at, match.planned_duration_minutes
  into v_match_status, v_kickoff_at, v_default_duration
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' then
    raise exception 'Live tracking is only available for upcoming matches'
      using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;

  select session.state
  into v_existing_state
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if found and v_existing_state <> 'not_started' then
    return private.match_live_snapshot(p_match_id);
  end if;

  if now() < private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'Le Live n’est pas encore ouvert.'
      using errcode = '22023';
  end if;

  if found then
    update public.match_live_sessions
    set planned_duration_minutes = greatest(
          1,
          least(
            200,
            coalesce(p_planned_duration_minutes, planned_duration_minutes)
          )
        ),
        updated_by = v_actor,
        updated_at = now()
    where match_id = p_match_id;

    select exists (
      select 1
      from public.match_composition_entries entry
      where entry.match_id = p_match_id
    ) into v_has_entries;

    if v_has_entries then
      -- Un espace de travail déjà ouvert reste la vérité du terrain. On se
      -- contente de le garder sauvegardable si l'effectif a bougé entre-temps.
      perform private.align_match_live_lineup_participants(p_match_id, false);
      return private.match_live_snapshot(p_match_id);
    end if;
  end if;

  -- Les entrées de composition référencent la ligne de composition du match :
  -- sans elle, ni brouillon ni lineup Live ne peuvent exister.
  insert into public.match_compositions (
    match_id,
    formation_code,
    status,
    version,
    has_unpublished_changes,
    last_modified_by
  ) values (
    p_match_id,
    '4-2-1-3',
    'draft',
    0,
    true,
    v_actor
  )
  on conflict (match_id) do nothing;

  select publication.snapshot, publication.formation_code
  into v_publication_snapshot, v_formation
  from public.match_composition_publications publication
  where publication.match_id = p_match_id
  order by publication.version desc
  limit 1;

  insert into public.match_live_sessions (
    match_id,
    state,
    planned_duration_minutes,
    updated_by
  ) values (
    p_match_id,
    'not_started',
    greatest(
      1,
      least(200, coalesce(p_planned_duration_minutes, v_default_duration))
    ),
    v_actor
  )
  on conflict (match_id) do update
  set planned_duration_minutes = greatest(
        1,
        least(
          200,
          coalesce(
            p_planned_duration_minutes,
            match_live_sessions.planned_duration_minutes
          )
        )
      ),
      updated_by = v_actor,
      updated_at = now();

  if v_publication_snapshot is not null then
    -- Rebuild the operational Live lineup from the last publication, but apply
    -- the current convocation truth. A withdrawn player must never reappear
    -- just because the publication snapshot predates the withdrawal.
    delete from public.match_composition_entries
    where match_id = p_match_id;

    insert into public.match_composition_entries (
      match_id,
      participant_id,
      zone,
      x,
      y,
      slot_label,
      sort_order
    )
    select
      p_match_id,
      (entry ->> 'participant_id')::uuid,
      case
        when (entry ->> 'zone') in ('field', 'bench')
         and coalesce(participant.convocation_status::text, '') <> 'convoked'
          then 'not_selected'::public.sport_composition_zone
        else (entry ->> 'zone')::public.sport_composition_zone
      end,
      case
        when (entry ->> 'zone') = 'field'
         and participant.convocation_status = 'convoked'
          then (entry ->> 'x')::numeric
        else null
      end,
      case
        when (entry ->> 'zone') = 'field'
         and participant.convocation_status = 'convoked'
          then (entry ->> 'y')::numeric
        else null
      end,
      case
        when (entry ->> 'zone') = 'field'
         and participant.convocation_status = 'convoked'
          then entry ->> 'slot_label'
        else null
      end,
      coalesce((entry ->> 'sort_order')::integer, 0)
    from jsonb_array_elements(v_publication_snapshot -> 'entries') entry
    left join public.match_sport_participants participant
      on participant.match_id = p_match_id
     and participant.id = (entry ->> 'participant_id')::uuid
    where (entry ->> 'zone') in ('field', 'bench', 'not_selected');
  else
    -- Aucune publication : la composition de départ est fabriquée ici. Un
    -- brouillon déjà enregistré sert de base, sinon les convoqués arrivent sur
    -- le banc et le coach les glisse sur le terrain avant le coup d'envoi.
    v_formation := (
      select composition.formation_code
      from public.match_compositions composition
      where composition.match_id = p_match_id
    );
  end if;

  perform private.align_match_live_lineup_participants(
    p_match_id,
    v_publication_snapshot is null
  );

  -- A player promoted after a published withdrawal did not necessarily exist
  -- on that publication. Put that promoted, currently-convoked participant on
  -- the Live bench instead of silently omitting them.
  insert into public.match_composition_entries (
    match_id,
    participant_id,
    zone,
    x,
    y,
    slot_label,
    sort_order
  )
  select
    p_match_id,
    participant.id,
    'bench'::public.sport_composition_zone,
    null,
    null,
    null,
    900 + row_number() over (
      order by participant.promoted_after_withdrawal_at, participant.id
    )::integer
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.convocation_status = 'convoked'
    and participant.promoted_after_withdrawal_at is not null
    and not exists (
      select 1
      from public.match_composition_entries existing
      where existing.match_id = p_match_id
        and existing.participant_id = participant.id
        and existing.zone in ('field', 'bench')
    )
  on conflict (match_id, participant_id) do update
  set zone = 'bench',
      x = null,
      y = null,
      slot_label = null,
      sort_order = excluded.sort_order,
      updated_at = now();

  update public.match_compositions
  set formation_code = coalesce(v_formation, '4-2-1-3'),
      last_modified_at = now(),
      last_modified_by = v_actor
  where match_id = p_match_id;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_publish_match_composition(p_match_id uuid, p_allow_squad_size_exception boolean DEFAULT false, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_status text; v_kickoff_at timestamptz; begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; select m.status,m.kickoff_at into v_status,v_kickoff_at from public.matches m where m.id=p_match_id; if not found then raise exception 'Match not found' using errcode='P0002'; end if; if v_status='a_venir' and v_kickoff_at is not null and now()>=private.match_prediction_closes_at(v_kickoff_at) then raise exception 'La composition est figée depuis l’ouverture du Live.' using errcode='22023'; end if; return private.publish_match_composition(p_match_id,p_allow_squad_size_exception,p_reason); end;$function$;

CREATE OR REPLACE FUNCTION public.admin_remove_match_guest(p_match_id uuid, p_participant_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
     and now() >= (
       case
         when v_kickoff_at = timestamptz '2026-09-28 19:00:00+00'
           then timestamptz '2026-09-28 17:00:00+00'
         else v_kickoff_at - interval '15 minutes'
       end
     ) then
    raise exception 'L’effectif est figé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  return private.remove_match_guest(p_match_id, p_participant_id, p_reason);
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_save_match_composition(p_match_id uuid, p_formation_code text, p_entries jsonb, p_allow_squad_size_exception boolean, p_reason text, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_status text; v_kickoff_at timestamptz; begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; select m.status,m.kickoff_at into v_status,v_kickoff_at from public.matches m where m.id=p_match_id; if not found then raise exception 'Match not found' using errcode='P0002'; end if; if v_status='a_venir' and v_kickoff_at is not null and now()>=private.match_prediction_closes_at(v_kickoff_at) then raise exception 'La composition est figée depuis l’ouverture du Live.' using errcode='22023'; end if; perform private.lock_match_composition_version(p_match_id,p_expected_version); perform private.save_match_composition(p_match_id,p_formation_code,p_entries,p_allow_squad_size_exception,p_reason); return private.publish_match_composition(p_match_id,p_allow_squad_size_exception,p_reason); end;$function$;

commit;
