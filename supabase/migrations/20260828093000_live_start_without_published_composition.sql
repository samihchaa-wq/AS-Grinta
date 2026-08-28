-- Le Live ne doit jamais être une impasse.
--
-- Avant ce lot, ouvrir le Tableau Blanc exigeait une composition déjà publiée.
-- Sans publication l'ouverture échouait, et comme la composition est figée
-- depuis T-15 le coach n'avait plus aucun moyen d'avancer.
--
-- Ce lot apporte trois changements :
--   1. l'ouverture du Live fabrique une composition de départ quand aucune
--      publication n'existe : le brouillon déjà enregistré s'il y en a un,
--      sinon les convoqués sur le banc ;
--   2. le lineup Live est aligné sur les participants réellement éligibles,
--      condition sans laquelle toute sauvegarde du lineup est refusée ;
--   3. le coup d'envoi publie la composition réellement alignée, pour que les
--      joueurs voient enfin l'équipe de départ.

begin;

-- Le lineup Live n'accepte une sauvegarde que si chaque participant éligible y
-- figure exactement une fois, et il n'accepte jamais la zone « available ».
-- Cette fonction rétablit ces deux invariants sans jamais déplacer un joueur
-- déjà positionné par le coach.
create or replace function private.align_match_live_lineup_participants(
  p_match_id uuid,
  p_seed_convoked_on_bench boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- Une personne devenue inéligible (passée coach, sortie de l'effectif de
  -- saison) ne peut plus faire partie d'un lineup Live valide.
  delete from public.match_composition_entries entry
  where entry.match_id = p_match_id
    and not exists (
      select 1
      from public.match_sport_participants participant
      where participant.match_id = p_match_id
        and participant.id = entry.participant_id
        and (
          participant.is_eligible
          or participant.final_presence_status <> 'pending'
        )
    );

  -- « available » est la zone d'attente de l'écran Composition ; le Live ne la
  -- connaît pas. Un convoqué encore en attente rejoint le banc, les autres
  -- passent en non retenus.
  update public.match_composition_entries entry
  set zone = case
        when participant.convocation_status = 'convoked'
          then 'bench'::public.sport_composition_zone
        else 'not_selected'::public.sport_composition_zone
      end,
      x = null,
      y = null,
      slot_label = null,
      updated_at = now()
  from public.match_sport_participants participant
  where entry.match_id = p_match_id
    and participant.match_id = p_match_id
    and participant.id = entry.participant_id
    and entry.zone = 'available';

  -- sort_order reste à 0 pour les entrées fabriquées ici : le banc est alors
  -- trié par nom à l'affichage, ce qui est plus lisible qu'un ordre technique.
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
    case
      when coalesce(p_seed_convoked_on_bench, false)
       and participant.convocation_status = 'convoked'
        then 'bench'::public.sport_composition_zone
      else 'not_selected'::public.sport_composition_zone
    end,
    null,
    null,
    null,
    0
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (
      participant.is_eligible
      or participant.final_presence_status <> 'pending'
    )
    and not exists (
      select 1
      from public.match_composition_entries existing
      where existing.match_id = p_match_id
        and existing.participant_id = participant.id
    )
  on conflict (match_id, participant_id) do nothing;
end;
$function$;

revoke all on function
  private.align_match_live_lineup_participants(uuid, boolean)
  from public, anon, authenticated;

comment on function
  private.align_match_live_lineup_participants(uuid, boolean)
is
  'Rend le lineup Live sauvegardable : un participant éligible par entrée, aucune zone « available ».';

-- Publie la composition telle qu'elle est réellement alignée, sans repasser
-- par les contrôles de l'écran d'administration. L'appelant a déjà vérifié le
-- rôle coach/admin et verrouillé la session Live : au coup d'envoi, ce qui est
-- sur le terrain fait foi.
create or replace function private.publish_match_live_composition(
  p_match_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_current_version integer;
  v_formation text;
  v_field_count integer;
  v_bench_count integer;
  v_next_state public.sport_composition_state;
  v_publication_kind text;
  v_snapshot jsonb;
begin
  select composition.version, composition.formation_code
  into v_current_version, v_formation
  from public.match_compositions composition
  where composition.match_id = p_match_id
  for update;

  if not found then
    return null;
  end if;

  select
    count(*) filter (where zone = 'field'),
    count(*) filter (where zone = 'bench')
  into v_field_count, v_bench_count
  from public.match_composition_entries
  where match_id = p_match_id;

  v_next_state := case
    when v_current_version = 0 then 'published'::public.sport_composition_state
    else 'updated'::public.sport_composition_state
  end;
  v_publication_kind := case
    when v_current_version = 0 then 'initial'
    else 'update'
  end;

  update public.match_compositions composition
  set status = v_next_state,
      version = v_current_version + 1,
      has_unpublished_changes = false,
      published_at = now(),
      published_by = v_actor,
      last_modified_at = now(),
      last_modified_by = v_actor
  where composition.match_id = p_match_id;

  update public.match_sport_workflows workflow
  set composition_state = v_next_state,
      composition_version = v_current_version + 1,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  v_snapshot := private.composition_snapshot(p_match_id)
    || jsonb_build_object(
      'published_at', now(),
      'publication_kind', v_publication_kind
    );

  insert into public.match_composition_publications(
    match_id,
    version,
    formation_code,
    snapshot,
    publication_kind,
    published_by
  ) values (
    p_match_id,
    v_current_version + 1,
    v_formation,
    v_snapshot,
    v_publication_kind,
    v_actor
  );

  insert into private.sport_admin_audit_log(
    match_id,
    action,
    actor_profile_id,
    metadata
  ) values (
    p_match_id,
    'publish_kickoff_composition',
    v_actor,
    jsonb_build_object(
      'version', v_current_version + 1,
      'publication_kind', v_publication_kind,
      'field_count', v_field_count,
      'bench_count', v_bench_count
    )
  );

  return v_current_version + 1;
end;
$function$;

revoke all on function private.publish_match_live_composition(uuid)
  from public, anon, authenticated;

comment on function private.publish_match_live_composition(uuid)
is
  'Publie la composition du coup d’envoi à partir du lineup Live, pour que les joueurs voient l’équipe alignée.';

-- Ouverture du Tableau Blanc. Reprend la version du 18/08/2026 et remplace le
-- refus « No published composition to start from » par une composition de
-- départ fabriquée sur place.
create or replace function private.open_match_live_workspace(
  p_match_id uuid,
  p_planned_duration_minutes integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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

  if now() < v_kickoff_at - interval '15 minutes' then
    raise exception 'Le Live ouvre 15 minutes avant le coup d’envoi.'
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

-- Coup d'envoi. Reprend la version du 18/08/2026 et publie la composition
-- réellement alignée avant de lancer le chronomètre.
create or replace function private.confirm_start_match_live(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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
     or now() < v_kickoff_at - interval '15 minutes' then
    raise exception 'Le Live ouvre 15 minutes avant le coup d’envoi.'
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

commit;
