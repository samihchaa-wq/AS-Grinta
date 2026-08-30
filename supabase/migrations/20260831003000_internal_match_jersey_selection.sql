-- Les matchs « entre nous » disposent désormais de trois maillots dans
-- l'application. La composition mémorise les deux maillots effectivement
-- opposés, tout en conservant Orange/Bleu comme valeur historique.

alter table public.match_internal_compositions
  add column if not exists team1_jersey_id text not null default 'orange',
  add column if not exists team2_jersey_id text not null default 'blue';

alter table public.match_internal_compositions
  drop constraint if exists match_internal_compositions_team1_jersey_id_check,
  drop constraint if exists match_internal_compositions_team2_jersey_id_check,
  drop constraint if exists match_internal_compositions_distinct_jerseys_check;

alter table public.match_internal_compositions
  add constraint match_internal_compositions_team1_jersey_id_check
    check (team1_jersey_id in ('france', 'orange', 'blue')),
  add constraint match_internal_compositions_team2_jersey_id_check
    check (team2_jersey_id in ('france', 'orange', 'blue')),
  add constraint match_internal_compositions_distinct_jerseys_check
    check (team1_jersey_id <> team2_jersey_id);

-- Le lecteur public aux profils actifs renvoie aussi l'identité canonique du
-- joueur. Le client réutilise ainsi exactement les profils de postes de la
-- simulation de composition, sans deuxième source métier.
create or replace function public.get_internal_composition(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_match_type text;
  v_team1_name text;
  v_team2_name text;
  v_team1_jersey_id text;
  v_team2_jersey_id text;
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
    comp.team1_jersey_id,
    comp.team2_jersey_id
  into
    v_team1_name,
    v_team2_name,
    v_team1_jersey_id,
    v_team2_jersey_id
  from public.match_internal_compositions comp
  where comp.match_id = p_match_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', participant.id,
      'season_player_id', participant.season_player_id,
      'guest_player_id', participant.guest_player_id,
      'canonical_player_id', player.player_id,
      'display_name', coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ),
      'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
      'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
      'is_guest', participant.guest_player_id is not null,
      'team_no', entry.team_no,
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
    'team1_name', coalesce(v_team1_name, 'Équipe 1'),
    'team2_name', coalesce(v_team2_name, 'Équipe 2'),
    'team1_jersey_id', coalesce(v_team1_jersey_id, 'orange'),
    'team2_jersey_id', coalesce(v_team2_jersey_id, 'blue'),
    'entries', v_entries
  );
end;
$function$;

-- Nouvelle RPC plutôt qu'une surcharge : PostgREST peut ainsi résoudre la
-- signature sans ambiguïté pendant une mise à jour progressive des clients.
create or replace function public.admin_save_internal_composition_v2(
  p_match_id uuid,
  p_team1_name text,
  p_team2_name text,
  p_team1_jersey_id text,
  p_team2_jersey_id text,
  p_entries jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_type text;
  v_team1_name text := coalesce(nullif(btrim(p_team1_name), ''), 'Équipe 1');
  v_team2_name text := coalesce(nullif(btrim(p_team2_name), ''), 'Équipe 2');
  v_team1_jersey_id text := lower(coalesce(nullif(btrim(p_team1_jersey_id), ''), 'orange'));
  v_team2_jersey_id text := lower(coalesce(nullif(btrim(p_team2_jersey_id), ''), 'blue'));
  v_entry jsonb;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if char_length(v_team1_name) > 40 or char_length(v_team2_name) > 40 then
    raise exception 'Nom d''équipe trop long (40 caractères max).' using errcode = '22023';
  end if;
  if v_team1_jersey_id not in ('france', 'orange', 'blue')
     or v_team2_jersey_id not in ('france', 'orange', 'blue') then
    raise exception 'Maillot invalide.' using errcode = '22023';
  end if;
  if v_team1_jersey_id = v_team2_jersey_id then
    raise exception 'Les deux équipes doivent avoir des maillots différents.' using errcode = '22023';
  end if;

  select match_type into v_match_type
  from public.matches
  where id = p_match_id;
  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;

  insert into public.match_internal_compositions (
    match_id,
    team1_name,
    team2_name,
    team1_jersey_id,
    team2_jersey_id,
    updated_by
  ) values (
    p_match_id,
    v_team1_name,
    v_team2_name,
    v_team1_jersey_id,
    v_team2_jersey_id,
    (select auth.uid())
  )
  on conflict (match_id) do update
  set team1_name = excluded.team1_name,
      team2_name = excluded.team2_name,
      team1_jersey_id = excluded.team1_jersey_id,
      team2_jersey_id = excluded.team2_jersey_id,
      updated_by = excluded.updated_by,
      updated_at = now();

  delete from public.match_internal_composition_entries
  where match_id = p_match_id;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb))
  loop
    insert into public.match_internal_composition_entries (
      match_id,
      participant_id,
      team_no,
      sort_order
    ) values (
      p_match_id,
      (v_entry ->> 'participant_id')::uuid,
      nullif(v_entry ->> 'team_no', '')::smallint,
      coalesce((v_entry ->> 'sort_order')::integer, 0)
    );
  end loop;

  return public.admin_get_internal_composition(p_match_id);
end;
$function$;

revoke all on function public.admin_save_internal_composition_v2(
  uuid, text, text, text, text, jsonb
) from public, anon;
grant execute on function public.admin_save_internal_composition_v2(
  uuid, text, text, text, text, jsonb
) to authenticated, service_role;