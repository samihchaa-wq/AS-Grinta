-- « Matchs entre nous » : match interne sans adversaire réel, sans limite
-- convocable, sans pronostics ni élection HDM ni saisie de stats de fin de
-- match. La composition devient une répartition en deux équipes nommables
-- (au lieu d'un placement sur un terrain), gérée dans des tables séparées
-- du système de composition classique pour ne pas perturber sa logique de
-- publication/finalisation/HDM déjà complexe.

alter table public.matches
  alter column opponent_id drop not null;

alter table public.matches
  drop constraint matches_match_type_check;

alter table public.matches
  add constraint matches_match_type_check
  check (match_type = any (array['amical'::text, 'championnat'::text, 'entre_nous'::text]));

-- Un match entre nous n'a pas d'adversaire : ne pas tenter de calculer des
-- cotes pour lui (calculate_match_odds_v5 lève une exception si
-- l'adversaire est introuvable, ce qui casserait aussi bien la création
-- que le recalcul groupé des cotes des matchs à venir).
create or replace function public.upsert_match_odds_v4(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_match record;
  v_result jsonb;
begin
  select id, opponent_id, match_date, status
  into v_match
  from public.matches
  where id = p_match_id;

  if not found or v_match.status <> 'a_venir' or v_match.opponent_id is null then
    return;
  end if;

  v_result := public.calculate_match_odds_v5(v_match.opponent_id, v_match.match_date);

  insert into public.match_odds(
    match_id, odds_victoire_as_grinta, odds_nul, odds_victoire_adverse,
    probability_win, probability_draw, probability_loss,
    model_version, computed_at
  ) values (
    v_match.id,
    (v_result->>'win')::numeric,
    (v_result->>'draw')::numeric,
    (v_result->>'loss')::numeric,
    (v_result->>'probability_win')::numeric,
    (v_result->>'probability_draw')::numeric,
    (v_result->>'probability_loss')::numeric,
    v_result->>'model_version',
    now()
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      probability_win = excluded.probability_win,
      probability_draw = excluded.probability_draw,
      probability_loss = excluded.probability_loss,
      expected_goals_as_grinta = null,
      expected_goals_adverse = null,
      confidence = null,
      model_version = excluded.model_version,
      computed_at = excluded.computed_at;
end;
$$;

-- Un match entre nous n'a pas de pronostics : ne pas semer de lignes
-- match_predictions pour lui.
create or replace function public.seed_match_predictions()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.opponent_id is null then
    return new;
  end if;

  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled,
    use_x2
  )
  select new.id, p.id, 0, 0, false, false
  from public.profiles p
  where p.status = 'active'
  on conflict (match_id, profile_id) do nothing;

  return new;
end;
$$;

-- Un match entre nous n'a pas d'élection homme du match.
create or replace function private.ensure_match_motm_election(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_exists boolean;
  v_kickoff timestamptz;
  v_opponent_id uuid;
  v_has_source boolean;
  v_has_ballot boolean;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_version integer;
  v_state public.sport_vote_state;
begin
  select true into v_exists
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;
  if v_exists then
    return;
  end if;

  select match.kickoff_at, match.opponent_id into v_kickoff, v_opponent_id
  from public.matches match
  where match.id = p_match_id;
  if v_kickoff is null or v_opponent_id is null then
    return;
  end if;

  v_has_source := exists (
    select 1 from public.match_composition_publications pub
    where pub.match_id = p_match_id
  ) or exists (
    select 1 from public.match_sport_finalization_versions version
    where version.match_id = p_match_id
  );
  if not v_has_source then
    return;
  end if;

  v_opens_at := private.match_motm_opens_at(p_match_id);
  v_closes_at := v_kickoff + interval '24 hours';
  v_version := private.match_motm_anchor_version(p_match_id);
  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  v_state := (case when v_has_ballot then 'draft' else 'cancelled' end)::public.sport_vote_state;

  insert into public.match_sport_motm_elections (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    v_state,
    case when v_has_ballot then v_opens_at else null end,
    case when v_has_ballot then v_closes_at else null end,
    null, 0, 0, now(), now()
  )
  on conflict (match_id) do nothing;

  update public.match_sport_workflows
  set vote_state = v_state,
      updated_at = now()
  where match_id = p_match_id;
end;
$$;

-- Création / modification d'un match entre nous : pas d'adversaire, pas de
-- cotes, lieu toujours domicile, limite convocable maximale (30, tout
-- convoqué disponible reste convoqué grâce à la logique déjà en place).
create or replace function public.create_internal_match(
  p_season_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_address text default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  new_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null or p_match_date is null or p_match_time is null then
    raise exception 'Season, date and time are required' using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Match date is outside allowed bounds' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.seasons s where s.id = p_season_id and s.status = 'open'
  ) then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;

  insert into public.matches(
    season_id, opponent_id, match_date, match_time, location,
    planned_duration_minutes, status, match_type, address, created_by
  ) values (
    p_season_id, null, p_match_date, p_match_time, 'domicile',
    90, 'a_venir', 'entre_nous', nullif(btrim(p_address), ''), (select auth.uid())
  ) returning id into new_id;

  perform private.configure_match_sport_workflow(new_id, 30);

  return new_id;
end;
$$;

grant execute on function public.create_internal_match(uuid, date, time without time zone, text) to authenticated;

create or replace function public.update_internal_match(
  p_match_id uuid,
  p_season_id uuid,
  p_match_date date,
  p_match_time time without time zone
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null or p_season_id is null or p_match_date is null or p_match_time is null then
    raise exception 'Match, saison, date et heure requis.' using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Date de match hors limites.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.matches m where m.id = p_match_id and m.match_type = 'entre_nous'
  ) then
    raise exception 'Match entre nous introuvable.' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.seasons s where s.id = p_season_id) then
    raise exception 'Saison introuvable.' using errcode = 'P0002';
  end if;

  update public.matches
  set season_id = p_season_id,
      match_date = p_match_date,
      match_time = p_match_time,
      updated_at = now()
  where id = p_match_id;

  perform private.configure_match_sport_workflow(p_match_id, 30);

  return true;
end;
$$;

grant execute on function public.update_internal_match(uuid, uuid, date, time without time zone) to authenticated;

-- Composition à deux équipes des matchs entre nous : indépendante du
-- système classique (terrain/banc/publication/HDM) pour rester simple.
create table public.match_internal_compositions (
  match_id uuid primary key
    references public.matches(id) on delete cascade,
  team1_name text not null default 'Équipe 1',
  team2_name text not null default 'Équipe 2',
  updated_at timestamptz not null default now(),
  updated_by uuid
);

alter table public.match_internal_compositions enable row level security;

create policy "match_internal_compositions_select"
  on public.match_internal_compositions for select
  to authenticated
  using (true);

create policy "match_internal_compositions_write"
  on public.match_internal_compositions for all
  to authenticated
  using (public.is_match_staff())
  with check (public.is_match_staff());

create table public.match_internal_composition_entries (
  match_id uuid not null
    references public.match_internal_compositions(match_id) on delete cascade,
  participant_id uuid not null,
  team_no smallint,
  sort_order integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (match_id, participant_id),
  constraint match_internal_composition_entries_team_no_check
    check (team_no is null or team_no in (1, 2)),
  constraint match_internal_composition_entries_participant_fkey
    foreign key (participant_id, match_id)
    references public.match_sport_participants(id, match_id) on delete cascade
);

alter table public.match_internal_composition_entries enable row level security;

create policy "match_internal_composition_entries_select"
  on public.match_internal_composition_entries for select
  to authenticated
  using (true);

create policy "match_internal_composition_entries_write"
  on public.match_internal_composition_entries for all
  to authenticated
  using (public.is_match_staff())
  with check (public.is_match_staff());

create or replace function public.admin_get_internal_composition(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_match_type text;
  v_team1_name text;
  v_team2_name text;
  v_entries jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select match_type into v_match_type from public.matches where id = p_match_id;
  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;

  select comp.team1_name, comp.team2_name
  into v_team1_name, v_team2_name
  from public.match_internal_compositions comp
  where comp.match_id = p_match_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', participant.id,
      'season_player_id', participant.season_player_id,
      'guest_player_id', participant.guest_player_id,
      'display_name', coalesce(
        nullif(btrim(profile.surnom), ''),
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
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      )
  ), '[]'::jsonb)
  into v_entries
  from public.match_sport_participants participant
  left join public.season_players player on player.id = participant.season_player_id
  left join public.profiles profile on profile.id = player.profile_id
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join public.match_internal_composition_entries entry
    on entry.match_id = p_match_id and entry.participant_id = participant.id
  where participant.match_id = p_match_id
    and participant.convocation_status = 'convoked';

  return jsonb_build_object(
    'match_id', p_match_id,
    'team1_name', coalesce(v_team1_name, 'Équipe 1'),
    'team2_name', coalesce(v_team2_name, 'Équipe 2'),
    'entries', v_entries
  );
end;
$$;

grant execute on function public.admin_get_internal_composition(uuid) to authenticated;

create or replace function public.admin_save_internal_composition(
  p_match_id uuid,
  p_team1_name text,
  p_team2_name text,
  p_entries jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_match_type text;
  v_team1_name text := coalesce(nullif(btrim(p_team1_name), ''), 'Équipe 1');
  v_team2_name text := coalesce(nullif(btrim(p_team2_name), ''), 'Équipe 2');
  v_entry jsonb;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if char_length(v_team1_name) > 40 or char_length(v_team2_name) > 40 then
    raise exception 'Nom d''équipe trop long (40 caractères max).' using errcode = '22023';
  end if;

  select match_type into v_match_type from public.matches where id = p_match_id;
  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;

  insert into public.match_internal_compositions (match_id, team1_name, team2_name, updated_by)
  values (p_match_id, v_team1_name, v_team2_name, (select auth.uid()))
  on conflict (match_id) do update
  set team1_name = excluded.team1_name,
      team2_name = excluded.team2_name,
      updated_by = excluded.updated_by,
      updated_at = now();

  delete from public.match_internal_composition_entries
  where match_id = p_match_id;

  for v_entry in select value from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb))
  loop
    insert into public.match_internal_composition_entries (
      match_id, participant_id, team_no, sort_order
    ) values (
      p_match_id,
      (v_entry ->> 'participant_id')::uuid,
      nullif(v_entry ->> 'team_no', '')::smallint,
      coalesce((v_entry ->> 'sort_order')::integer, 0)
    );
  end loop;

  return public.admin_get_internal_composition(p_match_id);
end;
$$;

grant execute on function public.admin_save_internal_composition(uuid, text, text, jsonb) to authenticated;
