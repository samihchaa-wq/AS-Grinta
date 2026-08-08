-- La composition suit la convocation, plus la disponibilité déclarée.
--
-- L'effectif accepte désormais de convoquer un joueur noté absent ou sans
-- réponse : c'est une décision d'administrateur, prise en connaissance de
-- cause, et `recompute_match_convocations_internal` la préserve déjà via
-- `convocation_manual_override`.
--
-- La composition, elle, refusait encore ces joueurs : l'enregistrement de la
-- feuille entière échouait, et la composition publiée les masquait avant le
-- coup d'envoi. Les deux règles se contredisaient.
--
-- Désormais un joueur peut être aligné dès lors qu'il est convoqué. Le refus
-- du joueur non convoqué est conservé, ainsi que la règle d'après-match, qui
-- continue de s'appuyer sur la présence réellement constatée.

create or replace function private.save_match_composition(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_allow_squad_size_exception boolean default false,
  p_reason text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_formation text := nullif(btrim(p_formation_code), '');
  v_match_status text;
  v_kickoff_at timestamptz;
  v_squad_limit integer;
  v_expected_count integer;
  v_input_count integer;
  v_selected_count integer;
  v_field_count integer;
  v_invalid_identity_count integer;
  v_invalid_zone_count integer;
  v_exception_used boolean := false;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    raise exception 'Composition entries must be a JSON array' using errcode = '22023';
  end if;
  if v_formation is not null and char_length(v_formation) > 32 then
    raise exception 'Formation code cannot exceed 32 characters' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.status, match.kickoff_at, workflow.squad_size_limit
  into v_match_status, v_kickoff_at, v_squad_limit
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status not in ('a_venir', 'termine', 'archive') then
    raise exception 'Composition cannot be edited for this match state' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.composition_input (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null,
    x numeric(7,6),
    y numeric(7,6),
    slot_label text,
    sort_order integer not null
  ) on commit drop;
  truncate table pg_temp.composition_input;

  begin
    insert into pg_temp.composition_input (participant_id, zone, x, y, slot_label, sort_order)
    select
      (item ->> 'participant_id')::uuid,
      (item ->> 'zone')::public.sport_composition_zone,
      case when item ->> 'x' is null then null else (item ->> 'x')::numeric end,
      case when item ->> 'y' is null then null else (item ->> 'y')::numeric end,
      nullif(btrim(item ->> 'slot_label'), ''),
      greatest(0, coalesce((item ->> 'sort_order')::integer, 0))
    from jsonb_array_elements(p_entries) item;
  exception
    when unique_violation then
      raise exception 'A participant can appear only once in a composition' using errcode = '22023';
    when invalid_text_representation or check_violation or numeric_value_out_of_range then
      raise exception 'Invalid composition entry' using errcode = '22023';
  end;

  select count(*) into v_input_count from pg_temp.composition_input;
  select count(*) into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible;

  if v_input_count <> v_expected_count then
    raise exception 'Every eligible participant must appear exactly once' using errcode = '22023';
  end if;

  select count(*) into v_invalid_identity_count
  from pg_temp.composition_input input
  left join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
   and participant.is_eligible
  where participant.id is null;
  if v_invalid_identity_count > 0 then
    raise exception 'Composition contains an ineligible participant' using errcode = '22023';
  end if;

  select count(*) into v_invalid_zone_count
  from pg_temp.composition_input input
  join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
  where
    (
      input.zone = 'field'
      and (
        input.x is null or input.y is null
        or input.x < 0 or input.x > 1
        or input.y < 0 or input.y > 1
      )
    )
    or (
      input.zone <> 'field' and (input.x is not null or input.y is not null)
    )
    or (
      -- Avant le coup d'envoi, seule la convocation compte : un joueur noté
      -- absent ou sans réponse reste alignable si l'admin l'a convoqué.
      v_match_status = 'a_venir'
      and input.zone in ('field', 'bench', 'available')
      and participant.convocation_status <> 'convoked'
    )
    or (
      v_match_status in ('termine', 'archive')
      and input.zone in ('field', 'bench')
      and participant.final_presence_status <> 'present'
    );

  if v_invalid_zone_count > 0 then
    raise exception 'Composition zones conflict with presence or convocation decisions' using errcode = '22023';
  end if;

  select
    count(*) filter (where zone = 'field'),
    count(*) filter (where zone in ('field', 'bench'))
  into v_field_count, v_selected_count
  from pg_temp.composition_input;

  if v_field_count > 11 then
    raise exception 'A composition cannot contain more than 11 starters' using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit
    and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit' using errcode = '22023';
  end if;
  v_exception_used := v_selected_count > v_squad_limit;

  insert into public.match_compositions (
    match_id, formation_code, status, version, has_unpublished_changes,
    squad_size_exception_approved, last_modified_by
  ) values (
    p_match_id, v_formation, 'draft', 0, true, v_exception_used, v_actor
  )
  on conflict (match_id) do update
  set formation_code = excluded.formation_code,
      has_unpublished_changes = true,
      squad_size_exception_approved = excluded.squad_size_exception_approved,
      last_modified_at = now(),
      last_modified_by = excluded.last_modified_by;

  delete from public.match_composition_entries where match_id = p_match_id;
  insert into public.match_composition_entries (
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select p_match_id, participant_id, zone, x, y, slot_label, sort_order
  from pg_temp.composition_input;

  update public.match_sport_participants participant
  set selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        when 'not_selected' then 'not_selected'::public.sport_selection_status
        else 'undecided'::public.sport_selection_status
      end,
      final_selection_status = case
        when v_match_status in ('termine', 'archive') then case input.zone
          when 'field' then 'starter'::public.sport_selection_status
          when 'bench' then 'substitute'::public.sport_selection_status
          else 'not_selected'::public.sport_selection_status
        end
        else participant.final_selection_status
      end,
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      updated_at = now()
  from pg_temp.composition_input input
  where participant.id = input.participant_id
    and participant.match_id = p_match_id;

  update public.match_sport_workflows workflow
  set composition_state = case
        when workflow.composition_state = 'none' then 'draft'::public.sport_composition_state
        else workflow.composition_state
      end,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    case when v_match_status in ('termine', 'archive')
      then 'save_postmatch_composition'
      else 'save_composition_draft'
    end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'formation_code', v_formation,
      'field_count', v_field_count,
      'bench_count', v_selected_count - v_field_count,
      'match_status', v_match_status,
      'exception_used', v_exception_used
    )
  );

  return private.composition_snapshot(p_match_id);
end;
$function$;

create or replace function private.get_published_match_composition(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_result jsonb;
  v_kickoff_at timestamptz;
  v_before_kickoff boolean;
  v_entries jsonb := '[]'::jsonb;
  v_entry jsonb;
  v_participant record;
  v_field_count integer := 0;
  v_bench_count integer := 0;
  v_available_count integer := 0;
  v_not_selected_count integer := 0;
  v_latest_motm_version integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select publication.snapshot, match.kickoff_at
  into v_result, v_kickoff_at
  from public.match_composition_publications publication
  join public.matches match on match.id = publication.match_id
  where publication.match_id = p_match_id
  order by publication.version desc
  limit 1;

  if v_result is null then
    return null;
  end if;

  v_before_kickoff := now() < v_kickoff_at;

  select max(finalization_version) into v_latest_motm_version
  from public.match_sport_motm_results
  where match_id = p_match_id;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(v_result -> 'entries', '[]'::jsonb))
    order by coalesce((value ->> 'sort_order')::integer, 0)
  loop
    select
      participant.availability_status::text as availability_status,
      participant.convocation_status::text as convocation_status,
      participant.final_presence_status::text as final_presence_status,
      participant.season_player_id,
      participant.guest_player_id,
      coalesce(participant.final_goals, 0) as goals,
      coalesce(profile.photo_url, player.photo_url, guest.photo_url) as photo_url,
      coalesce(
        nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ) as display_name,
      exists (
        select 1 from public.match_sport_motm_results result
        where result.match_id = p_match_id
          and result.participant_id = participant.id
          and result.is_winner
          and result.finalization_version = v_latest_motm_version
      ) as is_motm
    into v_participant
    from public.match_sport_participants participant
    left join public.season_players player on player.id = participant.season_player_id
    left join public.profiles profile on profile.id = player.profile_id
    left join public.guest_players guest on guest.id = participant.guest_player_id
    where participant.match_id = p_match_id
      and participant.id = (v_entry ->> 'participant_id')::uuid;

    if found then
      v_entry := v_entry || jsonb_build_object(
        'availability_status', v_participant.availability_status,
        'convocation_status', v_participant.convocation_status,
        'photo_url', v_participant.photo_url,
        'goals', v_participant.goals,
        'is_motm', v_participant.is_motm,
        'display_name', coalesce(v_participant.display_name, v_entry ->> 'display_name')
      );
      if v_before_kickoff then
        -- La composition publiée montre ce que l'admin a décidé : un convoqué
        -- reste affiché à son poste même si sa disponibilité dit le contraire.
        if v_participant.convocation_status <> 'convoked'
           and (v_entry ->> 'zone') in ('field', 'bench', 'available') then
          v_entry := v_entry || jsonb_build_object(
            'zone', 'not_selected', 'x', null, 'y', null,
            'selection_status', 'not_selected'
          );
        end if;
      elsif v_participant.final_presence_status = 'present'
            and (v_entry ->> 'zone') in ('available', 'not_selected') then
        v_entry := v_entry || jsonb_build_object(
          'zone', 'bench', 'selection_status', 'substitute'
        );
      end if;
    end if;

    case v_entry ->> 'zone'
      when 'field' then v_field_count := v_field_count + 1;
      when 'bench' then v_bench_count := v_bench_count + 1;
      when 'available' then v_available_count := v_available_count + 1;
      else v_not_selected_count := v_not_selected_count + 1;
    end case;

    v_entries := v_entries || jsonb_build_array(v_entry);
  end loop;

  for v_participant in
    select
      participant.id,
      participant.season_player_id,
      participant.guest_player_id,
      coalesce(participant.final_goals, 0) as goals,
      coalesce(profile.photo_url, player.photo_url, guest.photo_url) as photo_url,
      coalesce(
        nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ) as display_name,
      coalesce(player.is_goalkeeper, guest.is_goalkeeper, false) as is_goalkeeper,
      exists (
        select 1 from public.match_sport_motm_results result
        where result.match_id = p_match_id
          and result.participant_id = participant.id
          and result.is_winner
          and result.finalization_version = v_latest_motm_version
      ) as is_motm
    from public.match_sport_participants participant
    left join public.season_players player on player.id = participant.season_player_id
    left join public.profiles profile on profile.id = player.profile_id
    left join public.guest_players guest on guest.id = participant.guest_player_id
    where participant.match_id = p_match_id
      and participant.final_presence_status = 'present'
      and not exists (
        select 1 from jsonb_array_elements(v_entries)
        where (value ->> 'participant_id')::uuid = participant.id
      )
  loop
    v_entry := jsonb_build_object(
      'participant_id', v_participant.id,
      'season_player_id', v_participant.season_player_id,
      'guest_player_id', v_participant.guest_player_id,
      'display_name', v_participant.display_name,
      'photo_url', v_participant.photo_url,
      'goals', v_participant.goals,
      'is_motm', v_participant.is_motm,
      'is_goalkeeper', v_participant.is_goalkeeper,
      'is_guest', v_participant.guest_player_id is not null,
      'zone', 'bench',
      'selection_status', 'substitute',
      'availability_status', 'available',
      'convocation_status', 'convoked',
      'x', null, 'y', null,
      'sort_order', 999
    );
    v_bench_count := v_bench_count + 1;
    v_entries := v_entries || jsonb_build_array(v_entry);
  end loop;

  return v_result || jsonb_build_object(
    'entries', v_entries,
    'field_count', v_field_count,
    'bench_count', v_bench_count,
    'available_count', v_available_count,
    'not_selected_count', v_not_selected_count
  );
end;
$function$;

comment on function private.save_match_composition(uuid, text, jsonb, boolean, text) is
  'Enregistre la composition d''un match. Avant le coup d''envoi, seule la '
  'convocation conditionne le droit d''aligner un joueur : la disponibilité '
  'déclarée ne bloque plus une décision d''administrateur.';
