-- Matchs internes à AS Grinta : deux compositions libres, sans adversaire,
-- pronostic, HDM ni impact sur les statistiques officielles.

create table if not exists public.internal_matches (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete restrict,
  kickoff_at timestamptz not null,
  address text,
  team_a_name text not null default 'Les Verts',
  team_b_name text not null default 'Les Bleus',
  score_a smallint,
  score_b smallint,
  status text not null default 'a_venir',
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint internal_matches_team_a_name_check
    check (char_length(btrim(team_a_name)) between 1 and 40),
  constraint internal_matches_team_b_name_check
    check (char_length(btrim(team_b_name)) between 1 and 40),
  constraint internal_matches_distinct_names_check
    check (lower(btrim(team_a_name)) <> lower(btrim(team_b_name))),
  constraint internal_matches_address_check
    check (address is null or char_length(btrim(address)) between 1 and 300),
  constraint internal_matches_scores_check
    check (
      (score_a is null and score_b is null)
      or
      (score_a between 0 and 99 and score_b between 0 and 99)
    ),
  constraint internal_matches_status_check
    check (status in ('a_venir', 'termine')),
  constraint internal_matches_status_score_check
    check (
      (status = 'a_venir' and score_a is null and score_b is null)
      or
      (status = 'termine' and score_a is not null and score_b is not null)
    )
);

create index if not exists internal_matches_season_kickoff_idx
  on public.internal_matches(season_id, kickoff_at desc);

create table if not exists public.internal_match_players (
  internal_match_id uuid not null
    references public.internal_matches(id) on delete cascade,
  season_player_id uuid not null
    references public.season_players(id) on delete restrict,
  team_no smallint not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (internal_match_id, season_player_id),
  constraint internal_match_players_team_check check (team_no in (1, 2)),
  constraint internal_match_players_sort_check check (sort_order >= 0)
);

create index if not exists internal_match_players_team_order_idx
  on public.internal_match_players(internal_match_id, team_no, sort_order);

alter table public.internal_matches enable row level security;
alter table public.internal_match_players enable row level security;

create policy internal_matches_authenticated_read
  on public.internal_matches
  for select
  to authenticated
  using (true);

create policy internal_match_players_authenticated_read
  on public.internal_match_players
  for select
  to authenticated
  using (true);

grant select on public.internal_matches to authenticated;
grant select on public.internal_match_players to authenticated;
revoke all on public.internal_matches from anon;
revoke all on public.internal_match_players from anon;

create or replace function public.admin_save_internal_match(
  p_match_id uuid,
  p_season_id uuid,
  p_kickoff_at timestamptz,
  p_address text,
  p_team_a_name text,
  p_team_b_name text,
  p_score_a integer,
  p_score_b integer,
  p_players jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_match_id uuid;
  v_user_id uuid := auth.uid();
  v_team_a text := btrim(coalesce(p_team_a_name, ''));
  v_team_b text := btrim(coalesce(p_team_b_name, ''));
  v_address text := nullif(btrim(coalesce(p_address, '')), '');
  v_status text;
  v_player_count integer;
  v_distinct_count integer;
  v_valid_count integer;
begin
  if not private.is_admin() then
    raise exception 'Accès administrateur requis.' using errcode = '42501';
  end if;
  if v_user_id is null then
    raise exception 'Utilisateur non authentifié.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.seasons where id = p_season_id) then
    raise exception 'Saison introuvable.' using errcode = '23503';
  end if;
  if p_kickoff_at is null then
    raise exception 'La date et l’heure sont obligatoires.' using errcode = '22023';
  end if;
  if char_length(v_team_a) not between 1 and 40
     or char_length(v_team_b) not between 1 and 40 then
    raise exception 'Les noms d’équipe doivent contenir entre 1 et 40 caractères.'
      using errcode = '22023';
  end if;
  if lower(v_team_a) = lower(v_team_b) then
    raise exception 'Les deux équipes doivent avoir des noms différents.'
      using errcode = '22023';
  end if;
  if v_address is not null and char_length(v_address) > 300 then
    raise exception 'L’adresse ne peut pas dépasser 300 caractères.'
      using errcode = '22023';
  end if;
  if (p_score_a is null) <> (p_score_b is null) then
    raise exception 'Les deux scores doivent être renseignés ensemble.'
      using errcode = '22023';
  end if;
  if p_score_a is not null and
     (p_score_a not between 0 and 99 or p_score_b not between 0 and 99) then
    raise exception 'Les scores doivent être compris entre 0 et 99.'
      using errcode = '22023';
  end if;
  if p_players is null or jsonb_typeof(p_players) <> 'array' then
    raise exception 'La composition doit être une liste.' using errcode = '22023';
  end if;

  select count(*), count(distinct item->>'season_player_id')
    into v_player_count, v_distinct_count
  from jsonb_array_elements(p_players) as item;

  if v_player_count > 60 then
    raise exception 'Une composition interne ne peut pas dépasser 60 joueurs.'
      using errcode = '22023';
  end if;
  if v_player_count <> v_distinct_count then
    raise exception 'Un joueur ne peut apparaître que dans une seule équipe.'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_players) as item
    where coalesce((item->>'team_no')::integer, 0) not in (1, 2)
       or nullif(item->>'season_player_id', '') is null
       or coalesce((item->>'sort_order')::integer, -1) < 0
  ) then
    raise exception 'Composition invalide.' using errcode = '22023';
  end if;

  select count(*)
    into v_valid_count
  from jsonb_array_elements(p_players) as item
  join public.season_players sp
    on sp.id = (item->>'season_player_id')::uuid
   and sp.season_id = p_season_id
   and sp.is_active = true
   and sp.is_coach = false;

  if v_valid_count <> v_player_count then
    raise exception 'La composition contient un joueur indisponible pour cette saison.'
      using errcode = '22023';
  end if;

  v_status := case when p_score_a is null then 'a_venir' else 'termine' end;

  if p_match_id is null then
    insert into public.internal_matches (
      season_id,
      kickoff_at,
      address,
      team_a_name,
      team_b_name,
      score_a,
      score_b,
      status,
      created_by
    ) values (
      p_season_id,
      p_kickoff_at,
      v_address,
      v_team_a,
      v_team_b,
      p_score_a,
      p_score_b,
      v_status,
      v_user_id
    ) returning id into v_match_id;
  else
    update public.internal_matches
       set season_id = p_season_id,
           kickoff_at = p_kickoff_at,
           address = v_address,
           team_a_name = v_team_a,
           team_b_name = v_team_b,
           score_a = p_score_a,
           score_b = p_score_b,
           status = v_status,
           updated_at = now()
     where id = p_match_id;
    if not found then
      raise exception 'Match entre nous introuvable.' using errcode = 'P0002';
    end if;
    v_match_id := p_match_id;
    delete from public.internal_match_players
     where internal_match_id = v_match_id;
  end if;

  insert into public.internal_match_players (
    internal_match_id,
    season_player_id,
    team_no,
    sort_order
  )
  select
    v_match_id,
    (item->>'season_player_id')::uuid,
    (item->>'team_no')::smallint,
    coalesce((item->>'sort_order')::integer, 0)
  from jsonb_array_elements(p_players) as item;

  return v_match_id;
end;
$$;

create or replace function public.admin_delete_internal_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
begin
  if not private.is_admin() then
    raise exception 'Accès administrateur requis.' using errcode = '42501';
  end if;
  delete from public.internal_matches where id = p_match_id;
  return found;
end;
$$;

revoke all on function public.admin_save_internal_match(
  uuid, uuid, timestamptz, text, text, text, integer, integer, jsonb
) from public, anon;
grant execute on function public.admin_save_internal_match(
  uuid, uuid, timestamptz, text, text, text, integer, integer, jsonb
) to authenticated;

revoke all on function public.admin_delete_internal_match(uuid) from public, anon;
grant execute on function public.admin_delete_internal_match(uuid) to authenticated;
