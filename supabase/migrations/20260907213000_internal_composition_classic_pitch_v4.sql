-- Aligne les compositions « entre nous » sur le modèle de terrain classique.
-- V2/V3 restent disponibles pour compatibilité ; V4 ajoute zone/x/y et permet
-- d'enregistrer séparément la vue papier ou une composition terrain complète.

alter table public.match_internal_composition_entries
  add column if not exists zone text,
  add column if not exists x numeric,
  add column if not exists y numeric;

update public.match_internal_composition_entries
set zone = case
  when slot_label is not null then 'field'
  else 'available'
end
where zone is null;

alter table public.match_internal_composition_entries
  alter column zone set default 'available';

alter table public.match_internal_composition_entries
  drop constraint if exists match_internal_composition_entries_zone_check;
alter table public.match_internal_composition_entries
  add constraint match_internal_composition_entries_zone_check
  check (zone in ('available', 'field', 'bench'));

alter table public.match_internal_composition_entries
  drop constraint if exists match_internal_composition_entries_field_coordinates_check;
alter table public.match_internal_composition_entries
  add constraint match_internal_composition_entries_field_coordinates_check
  check (
    (zone = 'field' and x between 0 and 1 and y between 0 and 1 and slot_label is not null)
    or
    (zone <> 'field' and x is null and y is null)
  );

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
    comp.team1_name, comp.team2_name,
    comp.team1_jersey, comp.team2_jersey,
    comp.team1_formation, comp.team2_formation
  into
    v_team1_name, v_team2_name,
    v_team1_jersey, v_team2_jersey,
    v_team1_formation, v_team2_formation
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
      'zone', coalesce(entry.zone, 'available'),
      'x', entry.x,
      'y', entry.y,
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
      select 1 from public.push_notification_log log
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

create or replace function public.admin_save_internal_composition_v4(
  p_match_id uuid,
  p_team1_name text,
  p_team2_name text,
  p_team1_jersey text,
  p_team2_jersey text,
  p_team1_formation text,
  p_team2_formation text,
  p_entries jsonb,
  p_require_visual_complete boolean default false
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
  v_expected_count integer;
  v_team1_count integer;
  v_team2_count integer;
  v_team1_field integer;
  v_team2_field integer;
  v_team1_bench integer;
  v_team2_bench integer;
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
      or v_team2_jersey not in ('france', 'orange', 'blue')
      or v_team1_jersey = v_team2_jersey then
    raise exception 'Maillots invalides ou identiques.' using errcode = '22023';
  end if;

  select m.match_type, m.status,
    coalesce(m.kickoff_at, ((m.match_date + m.match_time) at time zone 'Europe/Paris'))
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

  select count(*)::integer into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.convocation_status = 'convoked';

  if jsonb_array_length(p_entries) <> v_expected_count then
    raise exception 'Tous les joueurs convoqués doivent apparaître exactement une fois.'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_entries) e
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
    where coalesce(e ->> 'zone', 'available') not in ('available', 'field', 'bench')
       or (
         coalesce(e ->> 'zone', 'available') = 'field'
         and (
           nullif(btrim(e ->> 'slot_label'), '') is null
           or (e ->> 'x') is null
           or (e ->> 'y') is null
           or (e ->> 'x')::numeric not between 0 and 1
           or (e ->> 'y')::numeric not between 0 and 1
         )
       )
  ) then
    raise exception 'Placement terrain invalide.' using errcode = '22023';
  end if;

  if p_require_visual_complete then
    if exists (
      select 1 from jsonb_array_elements(p_entries) e
      where coalesce(btrim(e ->> 'team_no'), '') not in ('1', '2')
    ) then
      raise exception 'Chaque joueur doit être affecté à une équipe.'
        using errcode = '22023';
    end if;

    select
      count(*) filter (where (e ->> 'team_no') = '1')::integer,
      count(*) filter (where (e ->> 'team_no') = '2')::integer,
      count(*) filter (where (e ->> 'team_no') = '1' and e ->> 'zone' = 'field')::integer,
      count(*) filter (where (e ->> 'team_no') = '2' and e ->> 'zone' = 'field')::integer,
      count(*) filter (where (e ->> 'team_no') = '1' and e ->> 'zone' = 'bench')::integer,
      count(*) filter (where (e ->> 'team_no') = '2' and e ->> 'zone' = 'bench')::integer
    into v_team1_count, v_team2_count, v_team1_field, v_team2_field,
         v_team1_bench, v_team2_bench
    from jsonb_array_elements(p_entries) e;

    if v_team1_count = 0 or v_team2_count = 0 then
      raise exception 'Les deux équipes doivent contenir au moins un joueur.'
        using errcode = '22023';
    end if;
    if nullif(btrim(p_team1_formation), '') is null
        or nullif(btrim(p_team2_formation), '') is null then
      raise exception 'Choisis le dispositif de chaque équipe.' using errcode = '22023';
    end if;
    if v_team1_field <> least(v_team1_count, 11)
        or v_team2_field <> least(v_team2_count, 11)
        or v_team1_bench <> greatest(v_team1_count - 11, 0)
        or v_team2_bench <> greatest(v_team2_count - 11, 0) then
      raise exception 'Terrain ou banc incomplet.' using errcode = '22023';
    end if;
    if exists (
      select 1 from jsonb_array_elements(p_entries) e
      where e ->> 'zone' = 'field'
      group by e ->> 'team_no', e ->> 'slot_label'
      having count(*) > 1
    ) then
      raise exception 'Deux joueurs ne peuvent pas occuper le même poste.'
        using errcode = '22023';
    end if;
  end if;

  insert into public.match_internal_compositions (
    match_id, team1_name, team2_name, team1_jersey, team2_jersey,
    team1_formation, team2_formation, updated_by
  ) values (
    p_match_id, v_team1_name, v_team2_name, v_team1_jersey, v_team2_jersey,
    nullif(btrim(p_team1_formation), ''), nullif(btrim(p_team2_formation), ''),
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

  for v_entry in select value from jsonb_array_elements(p_entries)
  loop
    insert into public.match_internal_composition_entries (
      match_id, participant_id, team_no, zone, x, y, slot_label, sort_order
    ) values (
      p_match_id,
      (v_entry ->> 'participant_id')::uuid,
      nullif(btrim(v_entry ->> 'team_no'), '')::smallint,
      coalesce(v_entry ->> 'zone', 'available'),
      case when v_entry ->> 'zone' = 'field' then (v_entry ->> 'x')::numeric else null end,
      case when v_entry ->> 'zone' = 'field' then (v_entry ->> 'y')::numeric else null end,
      case when v_entry ->> 'zone' = 'field'
        then nullif(btrim(v_entry ->> 'slot_label'), '') else null end,
      coalesce((v_entry ->> 'sort_order')::integer, 0)
    );
  end loop;

  if exists (
    select 1
    from jsonb_array_elements(p_entries) e
    where coalesce(btrim(e ->> 'team_no'), '') in ('1', '2')
  ) then
    perform private.notify_composition_published(p_match_id);
  end if;

  return public.get_internal_composition(p_match_id);
end;
$function$;

revoke all on function public.admin_save_internal_composition_v4(
  uuid, text, text, text, text, text, text, jsonb, boolean
) from public, anon;
grant execute on function public.admin_save_internal_composition_v4(
  uuid, text, text, text, text, text, text, jsonb, boolean
) to authenticated, service_role;
