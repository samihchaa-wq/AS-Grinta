-- Composition visuelle des matchs « entre nous ».
-- V2 reste intacte pour les clients déjà ouverts. V3 persiste les formations
-- et les postes, avec jusqu'à 11 titulaires et un banc sans plafond artificiel.

alter table public.match_internal_compositions
  add column if not exists team1_formation text,
  add column if not exists team2_formation text;

alter table public.match_internal_composition_entries
  add column if not exists slot_label text;

alter table public.match_internal_composition_entries
  drop constraint if exists match_internal_composition_entries_slot_label_length;

alter table public.match_internal_composition_entries
  add constraint match_internal_composition_entries_slot_label_length
  check (slot_label is null or char_length(slot_label) between 1 and 8);

create or replace function private.internal_formation_is_allowed(
  p_code text,
  p_player_count integer
)
returns boolean
language sql
immutable
set search_path to ''
as $function$
  select case p_player_count
    when 1 then p_code = 'GB'
    when 2 then p_code = '1'
    when 3 then p_code = any(array['1-1','2'])
    when 4 then p_code = any(array['2-1','1-2'])
    when 5 then p_code = any(array['2-1-1','1-2-1','2-2'])
    when 6 then p_code = any(array['2-2-1','2-1-2','1-3-1'])
    when 7 then p_code = any(array['2-3-1','3-2-1','2-2-2'])
    when 8 then p_code = any(array['3-3-1','2-3-2','3-2-2'])
    when 9 then p_code = any(array['3-3-2','3-2-3','2-3-3'])
    when 10 then p_code = any(array['3-4-2','4-3-2','4-2-3','3-3-3'])
    when 11 then p_code = any(array[
      '4-4-2','4-3-3','4-2-3-1','3-5-2','3-4-3','5-3-2'
    ])
    else false
  end;
$function$;

create or replace function private.internal_formation_slots(p_code text)
returns text[]
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_lines integer[];
  v_line_count integer;
  v_result text[] := array['GB']::text[];
  v_count integer;
  v_labels text[];
  v_i integer;
begin
  if p_code = 'GB' then
    return v_result;
  end if;

  if p_code is null or p_code !~ '^[1-5](-[1-5]){0,3}$' then
    return null;
  end if;

  select array_agg(part::integer order by ord)
  into v_lines
  from unnest(string_to_array(p_code, '-')) with ordinality as t(part, ord);

  v_line_count := cardinality(v_lines);

  for v_i in 1..v_line_count loop
    v_count := v_lines[v_i];

    if v_line_count = 1 then
      v_labels := case v_count
        when 1 then array['MC']
        when 2 then array['MCG','MCD']
        when 3 then array['MCG','MC','MCD']
        when 4 then array['MG','MCG','MCD','MD']
        when 5 then array['MG','MCG','MC','MCD','MD']
      end;
    elsif v_i = 1 then
      v_labels := case v_count
        when 1 then array['DC']
        when 2 then array['DCG','DCD']
        when 3 then array['DCG','DC','DCD']
        when 4 then array['DG','DCG','DCD','DD']
        when 5 then array['DG','DCG','DC','DCD','DD']
      end;
    elsif v_i = v_line_count then
      v_labels := case v_count
        when 1 then array['BU']
        when 2 then array['BUG','BUD']
        when 3 then array['AG','BU','AD']
        when 4 then array['AG','BUG','BUD','AD']
        when 5 then array['AG','AIG','BU','AID','AD']
      end;
    elsif v_line_count >= 4 and v_i = 2 then
      v_labels := case v_count
        when 1 then array['MDC']
        when 2 then array['MDG','MDD']
        when 3 then array['MDG','MDC','MDD']
        when 4 then array['MG','MCG','MCD','MD']
        when 5 then array['MG','MCG','MC','MCD','MD']
      end;
    elsif v_line_count >= 4 and v_i = v_line_count - 1 then
      v_labels := case v_count
        when 1 then array['MOC']
        when 2 then array['MOG','MOD']
        when 3 then array['MOG','MOC','MOD']
        when 4 then array['MG','MCG','MCD','MD']
        when 5 then array['MG','MCG','MC','MCD','MD']
      end;
    else
      v_labels := case v_count
        when 1 then array['MC']
        when 2 then array['MCG','MCD']
        when 3 then array['MCG','MC','MCD']
        when 4 then array['MG','MCG','MCD','MD']
        when 5 then array['MG','MCG','MC','MCD','MD']
      end;
    end if;

    v_result := v_result || v_labels;
  end loop;

  return v_result;
end;
$function$;

create or replace function public.get_internal_composition(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_match_type text;
  v_team1_name text;
  v_team2_name text;
  v_team1_jersey text;
  v_team2_jersey text;
  v_team1_formation text;
  v_team2_formation text;
  v_entries jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select match_type into v_match_type
  from public.matches
  where id = p_match_id;

  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;

  select
    comp.team1_name,
    comp.team2_name,
    comp.team1_jersey,
    comp.team2_jersey,
    comp.team1_formation,
    comp.team2_formation
  into
    v_team1_name,
    v_team2_name,
    v_team1_jersey,
    v_team2_jersey,
    v_team1_formation,
    v_team2_formation
  from public.match_internal_compositions comp
  where comp.match_id = p_match_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', participant.id,
      'season_player_id', participant.season_player_id,
      'guest_player_id', participant.guest_player_id,
      'display_name', coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ),
      'last_initial', nullif(upper(left(coalesce(
        nullif(btrim(guest.last_name), ''),
        nullif(btrim(player.last_name), ''),
        nullif(btrim(profile.last_name), ''),
        ''
      ), 1)), ''),
      'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
      'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
      'is_guest', participant.guest_player_id is not null,
      'team_no', entry.team_no,
      'slot_label', entry.slot_label,
      'sort_order', coalesce(entry.sort_order, 999)
    )
    order by coalesce(entry.sort_order, 999),
      coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      )
  ), '[]'::jsonb)
  into v_entries
  from public.match_sport_participants participant
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  left join public.match_internal_composition_entries entry
    on entry.match_id = p_match_id
   and entry.participant_id = participant.id
  where participant.match_id = p_match_id
    and participant.convocation_status = 'convoked';

  return jsonb_build_object(
    'match_id', p_match_id,
    'notification_sent', exists (
      select 1
      from public.push_notification_log log
      where log.match_id = p_match_id
        and log.kind = 'composition_published'
    ),
    'team1_name', coalesce(v_team1_name, 'Équipe 1'),
    'team2_name', coalesce(v_team2_name, 'Équipe 2'),
    'team1_jersey', coalesce(v_team1_jersey, 'orange'),
    'team2_jersey', coalesce(v_team2_jersey, 'blue'),
    'team1_formation', v_team1_formation,
    'team2_formation', v_team2_formation,
    'entries', v_entries
  );
end;
$function$;

create or replace function public.admin_save_internal_composition_v3(
  p_match_id uuid,
  p_team1_name text,
  p_team2_name text,
  p_team1_jersey text,
  p_team2_jersey text,
  p_team1_formation text,
  p_team2_formation text,
  p_entries jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_type text;
  v_status text;
  v_kickoff_at timestamptz;
  v_team1_name text := coalesce(nullif(btrim(p_team1_name), ''), 'Équipe 1');
  v_team2_name text := coalesce(nullif(btrim(p_team2_name), ''), 'Équipe 2');
  v_team1_jersey text := lower(btrim(coalesce(p_team1_jersey, '')));
  v_team2_jersey text := lower(btrim(coalesce(p_team2_jersey, '')));
  v_team1_formation text := btrim(coalesce(p_team1_formation, ''));
  v_team2_formation text := btrim(coalesce(p_team2_formation, ''));
  v_expected_count integer;
  v_team1_count integer;
  v_team2_count integer;
  v_team1_starters integer;
  v_team2_starters integer;
  v_team1_slots text[];
  v_team2_slots text[];
  v_entry jsonb;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_entries, 'null'::jsonb)) <> 'array' then
    raise exception 'La composition doit être une liste.' using errcode = '22023';
  end if;
  if char_length(v_team1_name) > 40 or char_length(v_team2_name) > 40 then
    raise exception 'Nom d''équipe trop long (40 caractères max).' using errcode = '22023';
  end if;
  if v_team1_jersey not in ('france', 'orange', 'blue')
      or v_team2_jersey not in ('france', 'orange', 'blue') then
    raise exception 'Maillot invalide.' using errcode = '22023';
  end if;
  if v_team1_jersey = v_team2_jersey then
    raise exception 'Les deux équipes doivent avoir des maillots différents.'
      using errcode = '22023';
  end if;

  select
    m.match_type,
    m.status,
    coalesce(
      m.kickoff_at,
      ((m.match_date + m.match_time) at time zone 'Europe/Paris')
    )
  into v_match_type, v_status, v_kickoff_at
  from public.matches m
  where m.id = p_match_id
  for update;

  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'La composition d’un match terminé ou annulé est verrouillée.'
      using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Horaire du match introuvable : composition refusée.' using errcode = '22023';
  end if;
  if now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'La composition est figée depuis l’ouverture du Live.'
      using errcode = '22023';
  end if;

  select count(*)::integer
  into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.convocation_status = 'convoked';

  if v_expected_count = 0 then
    raise exception 'Aucun joueur convoqué.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_entries) <> v_expected_count then
    raise exception 'Tous les joueurs convoqués doivent apparaître exactement une fois.'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_entries) e
    group by e ->> 'participant_id'
    having count(*) > 1
  ) then
    raise exception 'Un joueur apparaît plusieurs fois dans la composition.'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_entries) e
    where not exists (
      select 1
      from public.match_sport_participants participant
      where participant.id = (e ->> 'participant_id')::uuid
        and participant.match_id = p_match_id
        and participant.convocation_status = 'convoked'
    )
  ) then
    raise exception 'La composition contient un joueur non convoqué.'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_entries) e
    where nullif(btrim(e ->> 'team_no'), '') is null
       or (e ->> 'team_no') !~ '^[12]

  select
    count(*) filter (where (e ->> 'team_no')::integer = 1)::integer,
    count(*) filter (where (e ->> 'team_no')::integer = 2)::integer,
    count(*) filter (
      where (e ->> 'team_no')::integer = 1
        and nullif(btrim(e ->> 'slot_label'), '') is not null
    )::integer,
    count(*) filter (
      where (e ->> 'team_no')::integer = 2
        and nullif(btrim(e ->> 'slot_label'), '') is not null
    )::integer
  into v_team1_count, v_team2_count, v_team1_starters, v_team2_starters
  from jsonb_array_elements(p_entries) e;

  if v_team1_count = 0 or v_team2_count = 0 then
    raise exception 'Les deux équipes doivent contenir au moins un joueur.'
      using errcode = '22023';
  end if;
  if v_team1_starters <> least(v_team1_count, 11)
      or v_team2_starters <> least(v_team2_count, 11) then
    raise exception 'Chaque équipe doit avoir jusqu’à 11 titulaires ; le surplus reste sur le banc.'
      using errcode = '22023';
  end if;
  if not private.internal_formation_is_allowed(
      v_team1_formation, least(v_team1_count, 11)
    ) or not private.internal_formation_is_allowed(
      v_team2_formation, least(v_team2_count, 11)
    ) then
    raise exception 'Formation invalide pour le nombre de titulaires.'
      using errcode = '22023';
  end if;

  v_team1_slots := private.internal_formation_slots(v_team1_formation);
  v_team2_slots := private.internal_formation_slots(v_team2_formation);

  if exists (
    select 1
    from jsonb_array_elements(p_entries) e
    where (e ->> 'team_no')::integer = 1
      and nullif(btrim(e ->> 'slot_label'), '') is not null
      and not (btrim(e ->> 'slot_label') = any(v_team1_slots))
  ) or exists (
    select 1
    from jsonb_array_elements(p_entries) e
    where (e ->> 'team_no')::integer = 2
      and nullif(btrim(e ->> 'slot_label'), '') is not null
      and not (btrim(e ->> 'slot_label') = any(v_team2_slots))
  ) then
    raise exception 'Un poste ne correspond pas à la formation choisie.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_entries) e
    where nullif(btrim(e ->> 'slot_label'), '') is not null
    group by (e ->> 'team_no'), btrim(e ->> 'slot_label')
    having count(*) > 1
  ) then
    raise exception 'Deux joueurs ne peuvent pas occuper le même poste dans une équipe.'
      using errcode = '22023';
  end if;

  insert into public.match_internal_compositions (
    match_id,
    team1_name,
    team2_name,
    team1_jersey,
    team2_jersey,
    team1_formation,
    team2_formation,
    updated_by
  ) values (
    p_match_id,
    v_team1_name,
    v_team2_name,
    v_team1_jersey,
    v_team2_jersey,
    v_team1_formation,
    v_team2_formation,
    (select auth.uid())
  )
  on conflict (match_id) do update
  set team1_name = excluded.team1_name,
      team2_name = excluded.team2_name,
      team1_jersey = excluded.team1_jersey,
      team2_jersey = excluded.team2_jersey,
      team1_formation = excluded.team1_formation,
      team2_formation = excluded.team2_formation,
      updated_by = excluded.updated_by,
      updated_at = now();

  delete from public.match_internal_composition_entries
  where match_id = p_match_id;

  for v_entry in
    select value
    from jsonb_array_elements(p_entries)
  loop
    insert into public.match_internal_composition_entries (
      match_id,
      participant_id,
      team_no,
      slot_label,
      sort_order
    ) values (
      p_match_id,
      (v_entry ->> 'participant_id')::uuid,
      (v_entry ->> 'team_no')::smallint,
      nullif(btrim(v_entry ->> 'slot_label'), ''),
      coalesce((v_entry ->> 'sort_order')::integer, 0)
    );
  end loop;

  perform private.notify_composition_published(p_match_id);
  return public.get_internal_composition(p_match_id);
end;
$function$;

create or replace function public.admin_reset_internal_composition(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_type text;
  v_status text;
  v_kickoff_at timestamptz;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select
    m.match_type,
    m.status,
    coalesce(
      m.kickoff_at,
      ((m.match_date + m.match_time) at time zone 'Europe/Paris')
    )
  into v_match_type, v_status, v_kickoff_at
  from public.matches m
  where m.id = p_match_id
  for update;

  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'La composition d’un match terminé ou annulé est verrouillée.'
      using errcode = '22023';
  end if;
  if v_kickoff_at is null
      or now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'La composition est figée depuis l’ouverture du Live.'
      using errcode = '22023';
  end if;

  update public.match_internal_compositions
  set team1_formation = null,
      team2_formation = null,
      updated_by = (select auth.uid()),
      updated_at = now()
  where match_id = p_match_id;

  delete from public.match_internal_composition_entries
  where match_id = p_match_id;

  return public.get_internal_composition(p_match_id);
end;
$function$;

revoke all on function private.internal_formation_is_allowed(text, integer)
  from public, anon, authenticated;
revoke all on function private.internal_formation_slots(text)
  from public, anon, authenticated;

revoke all on function public.admin_save_internal_composition_v3(
  uuid, text, text, text, text, text, text, jsonb
) from public, anon;
grant execute on function public.admin_save_internal_composition_v3(
  uuid, text, text, text, text, text, text, jsonb
) to authenticated, service_role;

revoke all on function public.admin_reset_internal_composition(uuid)
  from public, anon;
grant execute on function public.admin_reset_internal_composition(uuid)
  to authenticated, service_role;

       or (e ->> 'team_no')::integer not in (1, 2)
  ) then
    raise exception 'Chaque joueur doit être affecté à une équipe.'
      using errcode = '22023';
  end if;

  select
    count(*) filter (where (e ->> 'team_no')::integer = 1)::integer,
    count(*) filter (where (e ->> 'team_no')::integer = 2)::integer,
    count(*) filter (
      where (e ->> 'team_no')::integer = 1
        and nullif(btrim(e ->> 'slot_label'), '') is not null
    )::integer,
    count(*) filter (
      where (e ->> 'team_no')::integer = 2
        and nullif(btrim(e ->> 'slot_label'), '') is not null
    )::integer
  into v_team1_count, v_team2_count, v_team1_starters, v_team2_starters
  from jsonb_array_elements(p_entries) e;

  if v_team1_count = 0 or v_team2_count = 0 then
    raise exception 'Les deux équipes doivent contenir au moins un joueur.'
      using errcode = '22023';
  end if;
  if v_team1_starters <> least(v_team1_count, 11)
      or v_team2_starters <> least(v_team2_count, 11) then
    raise exception 'Chaque équipe doit avoir jusqu’à 11 titulaires ; le surplus reste sur le banc.'
      using errcode = '22023';
  end if;
  if not private.internal_formation_is_allowed(
      v_team1_formation, least(v_team1_count, 11)
    ) or not private.internal_formation_is_allowed(
      v_team2_formation, least(v_team2_count, 11)
    ) then
    raise exception 'Formation invalide pour le nombre de titulaires.'
      using errcode = '22023';
  end if;

  v_team1_slots := private.internal_formation_slots(v_team1_formation);
  v_team2_slots := private.internal_formation_slots(v_team2_formation);

  if exists (
    select 1
    from jsonb_array_elements(p_entries) e
    where (e ->> 'team_no')::integer = 1
      and nullif(btrim(e ->> 'slot_label'), '') is not null
      and not (btrim(e ->> 'slot_label') = any(v_team1_slots))
  ) or exists (
    select 1
    from jsonb_array_elements(p_entries) e
    where (e ->> 'team_no')::integer = 2
      and nullif(btrim(e ->> 'slot_label'), '') is not null
      and not (btrim(e ->> 'slot_label') = any(v_team2_slots))
  ) then
    raise exception 'Un poste ne correspond pas à la formation choisie.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_entries) e
    where nullif(btrim(e ->> 'slot_label'), '') is not null
    group by (e ->> 'team_no'), btrim(e ->> 'slot_label')
    having count(*) > 1
  ) then
    raise exception 'Deux joueurs ne peuvent pas occuper le même poste dans une équipe.'
      using errcode = '22023';
  end if;

  insert into public.match_internal_compositions (
    match_id,
    team1_name,
    team2_name,
    team1_jersey,
    team2_jersey,
    team1_formation,
    team2_formation,
    updated_by
  ) values (
    p_match_id,
    v_team1_name,
    v_team2_name,
    v_team1_jersey,
    v_team2_jersey,
    v_team1_formation,
    v_team2_formation,
    (select auth.uid())
  )
  on conflict (match_id) do update
  set team1_name = excluded.team1_name,
      team2_name = excluded.team2_name,
      team1_jersey = excluded.team1_jersey,
      team2_jersey = excluded.team2_jersey,
      team1_formation = excluded.team1_formation,
      team2_formation = excluded.team2_formation,
      updated_by = excluded.updated_by,
      updated_at = now();

  delete from public.match_internal_composition_entries
  where match_id = p_match_id;

  for v_entry in
    select value
    from jsonb_array_elements(p_entries)
  loop
    insert into public.match_internal_composition_entries (
      match_id,
      participant_id,
      team_no,
      slot_label,
      sort_order
    ) values (
      p_match_id,
      (v_entry ->> 'participant_id')::uuid,
      (v_entry ->> 'team_no')::smallint,
      nullif(btrim(v_entry ->> 'slot_label'), ''),
      coalesce((v_entry ->> 'sort_order')::integer, 0)
    );
  end loop;

  perform private.notify_composition_published(p_match_id);
  return public.get_internal_composition(p_match_id);
end;
$function$;

create or replace function public.admin_reset_internal_composition(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_type text;
  v_status text;
  v_kickoff_at timestamptz;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select
    m.match_type,
    m.status,
    coalesce(
      m.kickoff_at,
      ((m.match_date + m.match_time) at time zone 'Europe/Paris')
    )
  into v_match_type, v_status, v_kickoff_at
  from public.matches m
  where m.id = p_match_id
  for update;

  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'La composition d’un match terminé ou annulé est verrouillée.'
      using errcode = '22023';
  end if;
  if v_kickoff_at is null
      or now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'La composition est figée depuis l’ouverture du Live.'
      using errcode = '22023';
  end if;

  update public.match_internal_compositions
  set team1_formation = null,
      team2_formation = null,
      updated_by = (select auth.uid()),
      updated_at = now()
  where match_id = p_match_id;

  delete from public.match_internal_composition_entries
  where match_id = p_match_id;

  return public.get_internal_composition(p_match_id);
end;
$function$;

revoke all on function private.internal_formation_is_allowed(text, integer)
  from public, anon, authenticated;
revoke all on function private.internal_formation_slots(text)
  from public, anon, authenticated;

revoke all on function public.admin_save_internal_composition_v3(
  uuid, text, text, text, text, text, text, jsonb
) from public, anon;
grant execute on function public.admin_save_internal_composition_v3(
  uuid, text, text, text, text, text, text, jsonb
) to authenticated, service_role;

revoke all on function public.admin_reset_internal_composition(uuid)
  from public, anon;
grant execute on function public.admin_reset_internal_composition(uuid)
  to authenticated, service_role;
