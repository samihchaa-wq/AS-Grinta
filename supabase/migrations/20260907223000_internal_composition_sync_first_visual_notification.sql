-- Matchs « entre nous » :
-- 1. la feuille « Sur papier » reste une donnée d'administration tant que les
--    deux terrains ne sont pas validés ;
-- 2. Effectif, papier et terrain sont toujours confrontés au même effectif
--    convoqué avant d'être considérés comme publiés ;
-- 3. la notification collective ne peut être consommée que par la sauvegarde
--    visuelle explicite et une seule fois par match.

create or replace function private.internal_composition_visual_is_complete(
  p_match_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_expected integer;
  v_stored integer;
  v_team1_count integer;
  v_team2_count integer;
  v_team1_field integer;
  v_team2_field integer;
  v_team1_bench integer;
  v_team2_bench integer;
  v_team1_formation text;
  v_team2_formation text;
begin
  select count(*)::integer
  into v_expected
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.convocation_status = 'convoked';

  if v_expected = 0 then
    return false;
  end if;

  select composition.team1_formation, composition.team2_formation
  into v_team1_formation, v_team2_formation
  from public.match_internal_compositions composition
  where composition.match_id = p_match_id;

  if v_team1_formation is null or v_team2_formation is null then
    return false;
  end if;

  select
    count(*)::integer,
    count(*) filter (where entry.team_no = 1)::integer,
    count(*) filter (where entry.team_no = 2)::integer,
    count(*) filter (
      where entry.team_no = 1 and entry.zone = 'field'
    )::integer,
    count(*) filter (
      where entry.team_no = 2 and entry.zone = 'field'
    )::integer,
    count(*) filter (
      where entry.team_no = 1 and entry.zone = 'bench'
    )::integer,
    count(*) filter (
      where entry.team_no = 2 and entry.zone = 'bench'
    )::integer
  into
    v_stored,
    v_team1_count,
    v_team2_count,
    v_team1_field,
    v_team2_field,
    v_team1_bench,
    v_team2_bench
  from public.match_internal_composition_entries entry
  where entry.match_id = p_match_id;

  if v_stored <> v_expected
     or v_team1_count = 0
     or v_team2_count = 0
     or v_team1_field <> least(v_team1_count, 11)
     or v_team2_field <> least(v_team2_count, 11)
     or v_team1_bench <> greatest(v_team1_count - 11, 0)
     or v_team2_bench <> greatest(v_team2_count - 11, 0)
     or v_team1_formation <> private.internal_default_formation_code(v_team1_count)
     or v_team2_formation <> private.internal_default_formation_code(v_team2_count)
     or exists (
       select 1
       from public.match_internal_composition_entries entry
       where entry.match_id = p_match_id
         and (
           entry.team_no is null
           or entry.zone = 'available'
           or (
             entry.zone = 'field'
             and (
               entry.x is null
               or entry.y is null
               or entry.slot_label is null
             )
           )
         )
     )
     or exists (
       select 1
       from public.match_internal_composition_entries entry
       where entry.match_id = p_match_id
         and entry.zone = 'field'
       group by entry.team_no, entry.slot_label
       having count(*) > 1
     )
     or exists (
       select 1
       from public.match_internal_composition_entries entry
       where entry.match_id = p_match_id
         and entry.zone = 'field'
         and (
           (entry.team_no = 1 and not (
             entry.slot_label = any(
               private.internal_v4_formation_slots(v_team1_formation)
             )
           ))
           or
           (entry.team_no = 2 and not (
             entry.slot_label = any(
               private.internal_v4_formation_slots(v_team2_formation)
             )
           ))
         )
     ) then
    return false;
  end if;

  return true;
end;
$function$;

revoke all on function private.internal_composition_visual_is_complete(uuid)
  from public, anon, authenticated;
grant execute on function private.internal_composition_visual_is_complete(uuid)
  to service_role;

-- La RPC historique garde sa signature pour les clients déjà ouverts, mais
-- elle ne livre jamais une répartition papier à un non-admin tant que le
-- terrain courant n'est pas complet et synchronisé avec l'Effectif.
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
  v_can_see_assignments boolean;
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

  v_can_see_assignments := public.is_match_staff()
    or private.internal_composition_visual_is_complete(p_match_id);

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
      'team_no', case when v_can_see_assignments then entry.team_no else null end,
      'zone', case
        when v_can_see_assignments then coalesce(entry.zone, 'available')
        else 'available'
      end,
      'x', case when v_can_see_assignments then entry.x else null end,
      'y', case when v_can_see_assignments then entry.y else null end,
      'slot_label', case
        when v_can_see_assignments then entry.slot_label else null
      end,
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
    'team1_formation', case
      when v_can_see_assignments then v_team1_formation else null
    end,
    'team2_formation', case
      when v_can_see_assignments then v_team2_formation else null
    end,
    'entries', v_entries
  );
end;
$function$;

create or replace function private.dispatch_composition_published_push(
  p_match_id uuid,
  p_profile_ids uuid[]
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_request_id bigint;
  v_title text;
  v_body text;
  v_match record;
begin
  if p_profile_ids is null
     or cardinality(p_profile_ids) = 0
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  select
    m.kickoff_at,
    m.match_type,
    nullif(btrim(o.name), '') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found or v_match.kickoff_at is null then
    return false;
  end if;

  v_title := case
    when v_match.match_type = 'entre_nous'
      then 'Compositions faites'
    else 'La composition est en ligne'
  end;

  v_body := case
    when v_match.match_type = 'entre_nous' then format(
      'Les compositions du match entre nous du %s sont prêtes.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM')
    )
    else format(
      'La compo du match du %s contre %s est en ligne.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM'),
      v_match.opponent_name
    )
  end;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';
  if v_token is null then
    return false;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', to_jsonb(p_profile_ids),
      'title', v_title,
      'message', v_body
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception when others then
  return false;
end;
$function$;

create or replace function private.notify_composition_published(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_status text;
  v_match_type text;
  v_kickoff_at timestamptz;
  v_first boolean;
  v_profile_ids uuid[];
begin
  select m.status, m.match_type, m.kickoff_at
  into v_status, v_match_type, v_kickoff_at
  from public.matches m
  where m.id = p_match_id;

  if not found or v_status <> 'a_venir' or v_kickoff_at is null then
    return false;
  end if;
  if now() >= v_kickoff_at then
    return false;
  end if;

  if v_match_type = 'entre_nous' then
    -- Aucun ancien client, sauvegarde papier ou RPC historique ne peut
    -- consommer la notification : seul V5 pose ce marqueur transactionnel.
    if coalesce(
      pg_catalog.current_setting(
        'as_grinta.internal_visual_publish',
        true
      ),
      ''
    ) <> '1' then
      return false;
    end if;

    if not private.internal_composition_visual_is_complete(p_match_id) then
      return false;
    end if;
  end if;

  insert into public.push_notification_log(match_id, kind, sent_at)
  values (p_match_id, 'composition_published', now())
  on conflict (match_id, kind) do nothing;

  get diagnostics v_first = row_count;
  if not v_first then
    return false;
  end if;

  if v_match_type = 'entre_nous' then
    -- « Tous » signifie tous les profils actifs qui ont conservé le réglage
    -- de notification de composition activé, pas seulement les convoqués.
    select array_agg(profile.id order by profile.id)
    into v_profile_ids
    from public.profiles profile
    where profile.status = 'active'
      and profile.notify_composition;
  else
    select array_agg(distinct player.profile_id)
    into v_profile_ids
    from public.match_sport_participants participant
    join public.season_players player
      on player.id = participant.season_player_id
    join public.profiles profile
      on profile.id = player.profile_id
    where participant.match_id = p_match_id
      and participant.is_eligible
      and participant.convocation_status = 'convoked'
      and profile.status = 'active'
      and profile.notify_composition;
  end if;

  if v_profile_ids is null or cardinality(v_profile_ids) = 0 then
    return false;
  end if;

  return private.dispatch_composition_published_push(p_match_id, v_profile_ids);
end;
$function$;

-- V5 est le seul chemin de validation visuelle « Sur terrain ». V4 reste le
-- chemin de sauvegarde papier/compatibilité et ne peut plus notifier seul.
create or replace function public.admin_save_internal_composition_v5(
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
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  perform pg_catalog.set_config(
    'as_grinta.internal_visual_publish',
    '1',
    true
  );

  return public.admin_save_internal_composition_v4(
    p_match_id,
    p_team1_name,
    p_team2_name,
    p_team1_jersey,
    p_team2_jersey,
    p_team1_formation,
    p_team2_formation,
    p_entries,
    true
  );
end;
$function$;

revoke all on function public.admin_save_internal_composition_v5(
  uuid, text, text, text, text, text, text, jsonb
) from public, anon;
grant execute on function public.admin_save_internal_composition_v5(
  uuid, text, text, text, text, text, text, jsonb
) to authenticated, service_role;

revoke all on function private.dispatch_composition_published_push(uuid, uuid[])
  from public, anon, authenticated;
revoke all on function private.notify_composition_published(uuid)
  from public, anon, authenticated;
grant execute on function private.dispatch_composition_published_push(uuid, uuid[])
  to service_role;
grant execute on function private.notify_composition_published(uuid)
  to service_role;
