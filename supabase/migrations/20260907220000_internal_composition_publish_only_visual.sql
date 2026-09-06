-- Les matchs « entre nous » ne sont annoncés qu'après publication des deux
-- terrains complets. L'enregistrement « Sur papier » reste privé aux admins et
-- ne consomme jamais la notification unique.

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
      then 'Les compositions sont en ligne'
    else 'La composition est en ligne'
  end;

  v_body := case
    when v_match.match_type = 'entre_nous' then format(
      'Les compositions du match entre nous du %s sont en ligne.',
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
  v_expected integer;
  v_stored integer;
  v_team1_count integer;
  v_team2_count integer;
  v_team1_field integer;
  v_team2_field integer;
  v_team1_bench integer;
  v_team2_bench integer;
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
    if not exists (
      select 1
      from public.match_internal_compositions composition
      where composition.match_id = p_match_id
        and nullif(btrim(composition.team1_formation), '') is not null
        and nullif(btrim(composition.team2_formation), '') is not null
    ) then
      return false;
    end if;

    select count(*)::integer
    into v_expected
    from public.match_sport_participants participant
    where participant.match_id = p_match_id
      and participant.convocation_status = 'convoked';

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

    if v_expected = 0
       or v_stored <> v_expected
       or v_team1_count = 0
       or v_team2_count = 0
       or v_team1_field <> least(v_team1_count, 11)
       or v_team2_field <> least(v_team2_count, 11)
       or v_team1_bench <> greatest(v_team1_count - 11, 0)
       or v_team2_bench <> greatest(v_team2_count - 11, 0)
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
       ) then
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

  if v_profile_ids is null or cardinality(v_profile_ids) = 0 then
    return false;
  end if;

  return private.dispatch_composition_published_push(p_match_id, v_profile_ids);
end;
$function$;

revoke all on function private.dispatch_composition_published_push(uuid, uuid[])
  from public, anon, authenticated;
revoke all on function private.notify_composition_published(uuid)
  from public, anon, authenticated;
grant execute on function private.dispatch_composition_published_push(uuid, uuid[])
  to service_role;
grant execute on function private.notify_composition_published(uuid)
  to service_role;
