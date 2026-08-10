-- Complete the post-match composition editor with one atomic creation.
-- The existing allow_postmatch_composition_editor migration is intentionally
-- reused and not recreated.

create or replace function private.guard_finished_match_composition_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match_id uuid;
  v_status text;
begin
  v_match_id := case when tg_op = 'DELETE' then old.match_id else new.match_id end;
  select match.status::text into v_status
  from public.matches match
  where match.id = v_match_id;

  if v_status in ('termine', 'archive')
     and coalesce(
       current_setting('as_grinta.allow_postmatch_composition_write', true),
       'off'
     ) <> 'on' then
    raise exception 'Finished match compositions are immutable'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

revoke all on function private.guard_finished_match_composition_write()
from public, anon, authenticated;

drop trigger if exists guard_finished_match_composition_write
  on public.match_compositions;
create trigger guard_finished_match_composition_write
before insert or update or delete on public.match_compositions
for each row execute function private.guard_finished_match_composition_write();

drop trigger if exists guard_finished_match_composition_entry_write
  on public.match_composition_entries;
create trigger guard_finished_match_composition_entry_write
before insert or update or delete on public.match_composition_entries
for each row execute function private.guard_finished_match_composition_write();

drop trigger if exists guard_finished_match_composition_publication_write
  on public.match_composition_publications;
create trigger guard_finished_match_composition_publication_write
before insert or update or delete on public.match_composition_publications
for each row execute function private.guard_finished_match_composition_write();

create or replace function private.match_sport_finalization_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  with latest_publication as (
    select publication.version, publication.snapshot
    from public.match_composition_publications publication
    where publication.match_id = p_match_id
    order by publication.version desc
    limit 1
  ), planned_entries as (
    select
      (entry ->> 'participant_id')::uuid as participant_id,
      entry ->> 'zone' as planned_zone
    from latest_publication publication,
      lateral jsonb_array_elements(
        coalesce(publication.snapshot -> 'entries', '[]'::jsonb)
      ) entry
  )
  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', opponent.name,
    'is_home', match.location = 'domicile',
    'kickoff_at', match.kickoff_at,
    'match_status', match.status,
    'is_validated', finalization.match_id is not null,
    'version', coalesce(finalization.version, 0),
    'score_as_grinta', coalesce(finalization.score_as_grinta, match.score_as_grinta, 0),
    'score_adverse', coalesce(finalization.score_adverse, match.score_adverse, 0),
    'composition_version', coalesce(finalization.composition_version, workflow.composition_version, 0),
    'presence_state', workflow.presence_state,
    'vote_state', workflow.vote_state,
    'validated_at', finalization.validated_at,
    'corrected_at', finalization.corrected_at,
    'participants', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'is_guest', participant.guest_player_id is not null,
        'display_name', case
          when guest.id is not null then
            btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
          else coalesce(
            nullif(btrim(profile.surnom), ''),
            nullif(btrim(player.first_name), ''),
            btrim(concat_ws(' ', player.first_name, player.last_name))
          )
        end,
        'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
        'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
        'planned_zone', coalesce(planned.planned_zone, case participant.selection_status
          when 'starter' then 'field'
          when 'substitute' then 'bench'
          when 'not_selected' then 'not_selected'
          else 'available'
        end),
        'present', case
          when finalization.match_id is not null then participant.final_presence_status = 'present'
          else coalesce(planned.planned_zone in ('field', 'bench'), false)
        end,
        'final_presence_status', participant.final_presence_status,
        'final_selection_status', case
          when finalization.match_id is not null then participant.final_selection_status
          when planned.planned_zone = 'field' then 'starter'::public.sport_selection_status
          when planned.planned_zone = 'bench' then 'substitute'::public.sport_selection_status
          else 'not_selected'::public.sport_selection_status
        end,
        'goals', participant.final_goals,
        'clean_sheet', participant.final_clean_sheet,
        'is_motm', exists (
          select 1
          from public.match_sport_motm_results result
          where result.match_id = p_match_id
            and result.participant_id = participant.id
            and result.is_winner
            and result.finalization_version = (
              select max(latest.finalization_version)
              from public.match_sport_motm_results latest
              where latest.match_id = p_match_id
            )
        )
      ) order by
        case coalesce(planned.planned_zone, '')
          when 'field' then 1
          when 'bench' then 2
          else 3
        end,
        lower(coalesce(profile.surnom, player.first_name, guest.first_name)),
        participant.id
    ) filter (
      where participant.id is not null
        and (
          participant.is_eligible
          or participant.final_presence_status <> 'pending'
        )
    ), '[]'::jsonb)
  ) into v_result
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_finalizations finalization on finalization.match_id = match.id
  left join public.match_sport_participants participant on participant.match_id = match.id
  left join public.season_players player on player.id = participant.season_player_id
  left join public.profiles profile on profile.id = player.profile_id
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join planned_entries planned on planned.participant_id = participant.id
  where match.id = p_match_id
  group by match.id, opponent.name, workflow.match_id, finalization.match_id;

  return v_result;
end;
$function$;

create or replace function private.create_postmatch_composition(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_allow_squad_size_exception boolean default false,
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
  v_formation text := nullif(btrim(p_formation_code), '');
  v_match_status text;
  v_kickoff_at timestamptz;
  v_squad_limit integer;
  v_finalized boolean;
  v_expected_count integer;
  v_input_count integer;
  v_field_count integer;
  v_selected_count integer;
  v_present_count integer;
  v_invalid_count integer;
  v_exception_used boolean;
  v_snapshot jsonb;
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

  select
    match.status::text,
    match.kickoff_at,
    workflow.squad_size_limit,
    finalization.match_id is not null
  into v_match_status, v_kickoff_at, v_squad_limit, v_finalized
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_finalizations finalization on finalization.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status not in ('termine', 'archive') or now() < v_kickoff_at then
    raise exception 'Post-match composition requires a finished match'
      using errcode = '22023';
  end if;
  if not v_finalized then
    raise exception 'The match must be finalized before creating its composition'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from public.match_compositions composition
    where composition.match_id = p_match_id
  ) or exists (
    select 1 from public.match_composition_publications publication
    where publication.match_id = p_match_id
  ) then
    raise exception 'A composition already exists for this match'
      using errcode = '55000';
  end if;

  create temporary table if not exists pg_temp.postmatch_composition_input (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null,
    x numeric(7,6),
    y numeric(7,6),
    slot_label text,
    sort_order integer not null
  ) on commit drop;
  truncate table pg_temp.postmatch_composition_input;

  begin
    insert into pg_temp.postmatch_composition_input(
      participant_id, zone, x, y, slot_label, sort_order
    )
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
      raise exception 'A participant can appear only once in a composition'
        using errcode = '22023';
    when invalid_text_representation or check_violation or numeric_value_out_of_range then
      raise exception 'Invalid composition entry' using errcode = '22023';
  end;

  select count(*) into v_input_count
  from pg_temp.postmatch_composition_input;
  select count(*) into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (
      participant.is_eligible
      or participant.final_presence_status <> 'pending'
    );
  if v_input_count <> v_expected_count then
    raise exception 'Every finalized participant must appear exactly once'
      using errcode = '22023';
  end if;

  select count(*) into v_invalid_count
  from pg_temp.postmatch_composition_input input
  left join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
   and (
     participant.is_eligible
     or participant.final_presence_status <> 'pending'
   )
  where participant.id is null
     or input.zone = 'available'
     or (
       input.zone = 'field'
       and (
         input.x is null or input.y is null
         or input.x < 0 or input.x > 1
         or input.y < 0 or input.y > 1
       )
     )
     or (input.zone <> 'field' and (input.x is not null or input.y is not null))
     or (
       participant.final_presence_status = 'present'
       and input.zone not in ('field', 'bench')
     )
     or (
       participant.final_presence_status <> 'present'
       and input.zone <> 'not_selected'
     );
  if v_invalid_count > 0 then
    raise exception 'Composition must contain only actual present players'
      using errcode = '22023';
  end if;

  select
    count(*) filter (where input.zone = 'field'),
    count(*) filter (where input.zone in ('field', 'bench'))
  into v_field_count, v_selected_count
  from pg_temp.postmatch_composition_input input;
  select count(*) into v_present_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.final_presence_status = 'present';

  if v_field_count > 11 then
    raise exception 'A composition cannot contain more than 11 starters'
      using errcode = '22023';
  end if;
  if v_selected_count <> v_present_count then
    raise exception 'Every actual present player must be on the field or bench'
      using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit
     and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit'
      using errcode = '22023';
  end if;
  v_exception_used := v_selected_count > v_squad_limit;

  perform set_config(
    'as_grinta.allow_postmatch_composition_write',
    'on',
    true
  );

  insert into public.match_compositions(
    match_id, formation_code, status, version, has_unpublished_changes,
    squad_size_exception_approved, published_at, published_by,
    last_modified_at, last_modified_by, closed_at
  ) values (
    p_match_id, v_formation, 'published', 1, false,
    v_exception_used, now(), v_actor, now(), v_actor, now()
  );

  insert into public.match_composition_entries(
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select p_match_id, participant_id, zone, x, y, slot_label, sort_order
  from pg_temp.postmatch_composition_input;

  update public.match_sport_participants participant
  set selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        else 'not_selected'::public.sport_selection_status
      end,
      final_selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        else 'not_selected'::public.sport_selection_status
      end,
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      updated_at = now()
  from pg_temp.postmatch_composition_input input
  where participant.id = input.participant_id
    and participant.match_id = p_match_id;

  update public.match_sport_workflows workflow
  set composition_state = 'published',
      composition_version = 1,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  update public.match_sport_finalizations finalization
  set composition_version = 1,
      updated_at = now()
  where finalization.match_id = p_match_id;

  v_snapshot := private.composition_snapshot(p_match_id)
    || jsonb_build_object(
      'published_at', now(),
      'publication_kind', 'postmatch'
    );

  insert into public.match_composition_publications(
    match_id, version, formation_code, snapshot,
    publication_kind, published_by
  ) values (
    p_match_id, 1, v_formation, v_snapshot, 'postmatch', v_actor
  );

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'publish_postmatch_composition',
    v_actor,
    v_reason,
    jsonb_build_object(
      'version', 1,
      'publication_kind', 'postmatch',
      'field_count', v_field_count,
      'bench_count', v_selected_count - v_field_count,
      'present_count', v_present_count,
      'match_status', v_match_status,
      'exception_used', v_exception_used
    )
  );

  return private.get_published_match_composition(p_match_id);
end;
$function$;

revoke all on function private.create_postmatch_composition(
  uuid, text, jsonb, boolean, text
) from public, anon, authenticated;

create or replace function public.admin_create_postmatch_composition(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_allow_squad_size_exception boolean default false,
  p_reason text default null
)
returns jsonb
language sql
set search_path = ''
as $function$
  select private.create_postmatch_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    p_allow_squad_size_exception,
    p_reason
  );
$function$;

revoke all on function public.admin_create_postmatch_composition(
  uuid, text, jsonb, boolean, text
) from public, anon;
grant execute on function public.admin_create_postmatch_composition(
  uuid, text, jsonb, boolean, text
) to authenticated;
