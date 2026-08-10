-- Salves de remplacements : plusieurs changements a la meme minute.
--
-- p_substitution acceptait uniquement un couple {player_in, player_out}.
-- Il accepte desormais aussi un tableau de couples, tous horodates a la
-- meme minute et la meme periode. La forme objet reste acceptee telle
-- quelle : les anciens appels continuent de fonctionner.
--
-- Les controles sont renforces au passage : un meme joueur ne peut pas
-- apparaitre deux fois dans une salve, et le sortant doit reellement
-- quitter le terrain (seul l'entrant etait verifie jusqu'ici).

create or replace function private.save_match_live_lineup(
  p_match_id uuid,
  p_entries jsonb,
  p_substitution jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_elapsed integer;
  v_running_since timestamptz;
  v_half smallint;
  v_true_elapsed integer;
  v_minute integer;
  v_expected_count integer;
  v_input_count integer;
  v_invalid_count integer;
  v_field_count integer;
  v_bad_boundary_count integer;
  v_subs jsonb;
  v_sub_count integer;
  v_bad_sub_count integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    raise exception 'Lineup entries must be a JSON array' using errcode = '22023';
  end if;

  select session.state, session.elapsed_seconds, session.running_since, session.half
  into v_state, v_elapsed, v_running_since, v_half
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state not in ('not_started', 'running', 'paused', 'halftime') then
    raise exception 'The lineup can only be edited while the live session is open' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.live_lineup_input (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null,
    x numeric(7,6),
    y numeric(7,6),
    slot_label text,
    sort_order integer not null
  ) on commit drop;
  truncate table pg_temp.live_lineup_input;

  begin
    insert into pg_temp.live_lineup_input (participant_id, zone, x, y, slot_label, sort_order)
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
      raise exception 'A participant can appear only once' using errcode = '22023';
    when invalid_text_representation or check_violation or numeric_value_out_of_range then
      raise exception 'Invalid lineup entry' using errcode = '22023';
  end;

  if exists (select 1 from pg_temp.live_lineup_input where zone = 'available') then
    raise exception 'Live lineup entries cannot use the available zone' using errcode = '22023';
  end if;

  select count(*) into v_input_count from pg_temp.live_lineup_input;
  select count(*) into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (participant.is_eligible or participant.final_presence_status <> 'pending');
  if v_input_count <> v_expected_count then
    raise exception 'Every eligible participant must appear exactly once' using errcode = '22023';
  end if;

  select count(*) into v_invalid_count
  from pg_temp.live_lineup_input input
  left join public.match_sport_participants participant
    on participant.id = input.participant_id and participant.match_id = p_match_id
  where participant.id is null
     or (input.zone = 'field' and (
       input.x is null or input.y is null
       or input.x < 0 or input.x > 1 or input.y < 0 or input.y > 1
     ))
     or (input.zone <> 'field' and (input.x is not null or input.y is not null));
  if v_invalid_count > 0 then
    raise exception 'Invalid lineup zone or coordinates' using errcode = '22023';
  end if;

  select count(*) into v_field_count from pg_temp.live_lineup_input where zone = 'field';
  if v_field_count > 11 then
    raise exception 'A lineup cannot contain more than 11 starters' using errcode = '22023';
  end if;

  -- Une salve : p_substitution accepte soit un couple {player_in, player_out},
  -- soit un tableau de couples appliques a la meme minute.
  create temporary table if not exists pg_temp.live_sub_input (
    player_in uuid not null,
    player_out uuid not null
  ) on commit drop;
  truncate table pg_temp.live_sub_input;

  if p_substitution is not null then
    if jsonb_typeof(p_substitution) = 'array' then
      v_subs := p_substitution;
    else
      v_subs := jsonb_build_array(p_substitution);
    end if;

    begin
      insert into pg_temp.live_sub_input (player_in, player_out)
      select (item ->> 'player_in')::uuid, (item ->> 'player_out')::uuid
      from jsonb_array_elements(v_subs) item;
    exception
      when invalid_text_representation or not_null_violation then
        raise exception 'Invalid substitution payload' using errcode = '22023';
    end;

    select count(*) into v_sub_count from pg_temp.live_sub_input;

    if exists (select 1 from pg_temp.live_sub_input where player_in = player_out) then
      raise exception 'Invalid substitution payload' using errcode = '22023';
    end if;

    -- Un meme joueur ne peut pas apparaitre deux fois dans la salve.
    if exists (
      select 1
      from (
        select player_in as participant_id from pg_temp.live_sub_input
        union all
        select player_out from pg_temp.live_sub_input
      ) involved
      group by involved.participant_id
      having count(*) > 1
    ) then
      raise exception 'A player cannot appear twice in the same substitution batch'
        using errcode = '22023';
    end if;

    -- Etat avant la salve : l'entrant n'etait pas sur le terrain, le
    -- sortant y etait.
    select count(*) into v_bad_sub_count
    from pg_temp.live_sub_input sub
    left join public.match_composition_entries old_in
      on old_in.match_id = p_match_id and old_in.participant_id = sub.player_in
    left join public.match_composition_entries old_out
      on old_out.match_id = p_match_id and old_out.participant_id = sub.player_out
    where coalesce(old_in.zone, 'not_selected') = 'field'
       or coalesce(old_out.zone, 'not_selected') <> 'field';
    if v_bad_sub_count > 0 then
      raise exception 'Substitution must bring in a non-field player and remove a field player'
        using errcode = '22023';
    end if;

    -- Etat apres la salve : l'entrant finit sur le terrain, le sortant non.
    select count(*) into v_bad_sub_count
    from pg_temp.live_sub_input sub
    left join pg_temp.live_lineup_input new_in
      on new_in.participant_id = sub.player_in
    left join pg_temp.live_lineup_input new_out
      on new_out.participant_id = sub.player_out
    where coalesce(new_in.zone, 'not_selected') <> 'field'
       or coalesce(new_out.zone, 'not_selected') = 'field';
    if v_bad_sub_count > 0 then
      raise exception 'The incoming player must end up on the field' using errcode = '22023';
    end if;
  end if;

  -- Sanity check: any zone crossing the field/bench boundary that wasn't
  -- flagged as the declared substitution is silently corrupting
  -- Remplacements/Faits du match and the times-benched counter — reject it.
  select count(*) into v_bad_boundary_count
  from pg_temp.live_lineup_input input
  join public.match_composition_entries old_entry
    on old_entry.match_id = p_match_id and old_entry.participant_id = input.participant_id
  where (old_entry.zone = 'field') <> (input.zone = 'field')
    and not exists (
      select 1 from pg_temp.live_sub_input sub
      where sub.player_in = input.participant_id
         or sub.player_out = input.participant_id
    );
  if v_bad_boundary_count > 0 then
    raise exception 'A field/bench change was not declared as a substitution' using errcode = '22023';
  end if;

  delete from public.match_composition_entries where match_id = p_match_id;
  insert into public.match_composition_entries (
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select p_match_id, participant_id, zone, x, y, slot_label, sort_order
  from pg_temp.live_lineup_input;

  update public.match_sport_participants participant
  set selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        else 'not_selected'::public.sport_selection_status
      end,
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      updated_at = now()
  from pg_temp.live_lineup_input input
  where participant.id = input.participant_id and participant.match_id = p_match_id;

  update public.match_compositions
  set last_modified_at = now(), last_modified_by = v_actor
  where match_id = p_match_id;

  if coalesce(v_sub_count, 0) > 0 then
    v_true_elapsed := v_elapsed + case
      when v_state = 'running'
      then greatest(0, extract(epoch from now() - v_running_since))::integer
      else 0
    end;
    v_minute := v_true_elapsed / 60 + 1;

    -- Toute la salve porte la meme minute et la meme periode.
    insert into public.match_live_events (
      match_id, event_type, minute, half,
      player_in_participant_id, player_out_participant_id, created_by
    )
    select p_match_id, 'substitution', v_minute, v_half,
           sub.player_in, sub.player_out, v_actor
    from pg_temp.live_sub_input sub;
  end if;

  update public.match_live_sessions
  set lineup_revision = lineup_revision + 1, updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  return private.match_live_snapshot(p_match_id);
end;
$function$;
