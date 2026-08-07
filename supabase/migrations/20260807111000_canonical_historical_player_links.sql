-- Le JSON historique reste la copie source importée, mais chaque libellé de
-- joueur possède désormais une résolution durable vers public.players.

create table public.historical_player_name_links (
  normalized_name text primary key check (btrim(normalized_name) <> ''),
  source_name text not null check (btrim(source_name) <> ''),
  player_id uuid not null references public.players(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.historical_player_name_links is
  'Résolution durable d''un libellé de joueur des archives vers son identité canonique. Les libellés ambigus peuvent pointer vers une identité d''archive distincte plutôt que d''être fusionnés arbitrairement.';

create index historical_player_name_links_player_id_idx
  on public.historical_player_name_links(player_id);

alter table public.historical_player_name_links enable row level security;
revoke all on table public.historical_player_name_links from anon, authenticated;

insert into public.historical_player_name_links(
  normalized_name,
  source_name,
  player_id
)
select
  private.normalize_player_name(hmp.source_name),
  min(hmp.source_name),
  min(hmp.player_id::text)::uuid
from public.historical_match_players hmp
group by private.normalize_player_name(hmp.source_name)
having count(distinct hmp.player_id) = 1
on conflict (normalized_name) do nothing;

do $assertions$
begin
  if exists (
    select 1
    from public.historical_match_players hmp
    left join public.historical_player_name_links link
      on link.normalized_name = private.normalize_player_name(hmp.source_name)
    where link.player_id is null
       or link.player_id is distinct from hmp.player_id
  ) then
    raise exception 'Historical player-name registry disagrees with normalized archive rows';
  end if;
end
$assertions$;

create or replace function private.resolve_historical_player_name(p_name text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_name text := nullif(btrim(p_name), '');
  v_normalized_name text;
  v_player_id uuid;
  v_identity_count integer;
begin
  if v_name is null then
    return null;
  end if;

  v_normalized_name := private.normalize_player_name(v_name);
  if v_normalized_name = private.normalize_player_name('Poste laissé vide') then
    return null;
  end if;

  select link.player_id
  into v_player_id
  from public.historical_player_name_links link
  where link.normalized_name = v_normalized_name;

  if found then
    return v_player_id;
  end if;

  select
    count(distinct alias.player_id)::integer,
    min(alias.player_id::text)::uuid
  into v_identity_count, v_player_id
  from public.player_aliases alias
  where private.normalize_player_name(alias.alias) = v_normalized_name;

  -- 0 correspondance ou plusieurs homonymes : on ne devine pas. Une
  -- identité d'archive distincte est créée et restera stable pour ce libellé.
  if v_identity_count <> 1 then
    v_player_id := private.create_player_identity(v_name);
  end if;

  insert into public.historical_player_name_links(
    normalized_name,
    source_name,
    player_id
  )
  values (v_normalized_name, v_name, v_player_id)
  on conflict (normalized_name) do update
  set updated_at = now()
  returning player_id into v_player_id;

  return v_player_id;
end;
$function$;

revoke all on function private.resolve_historical_player_name(text)
  from public, anon, authenticated;

create or replace function private.refresh_historical_match_players(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  delete from public.historical_match_players hmp
  where hmp.match_id = p_match_id;

  with field_row as (
    select
      h.match_id,
      btrim(e ->> 'name') as source_name,
      private.normalize_player_name(e ->> 'name') as normalized_name,
      true as is_present,
      true as is_starter,
      false as is_bench,
      false as is_motm,
      0::integer as goals,
      (e ->> 'is_gk')::boolean as is_goalkeeper,
      (e ->> 'x_pct')::numeric as x_pct,
      (e ->> 'y_pct')::numeric as y_pct,
      e ->> 'position_code' as position_code,
      e ->> 'position_label' as position_label
    from public.historical_match_details h
    cross join lateral jsonb_array_elements(coalesce(h.field_players, '[]'::jsonb)) e
    where h.match_id = p_match_id
      and btrim(coalesce(e ->> 'name', '')) <> ''
      and private.normalize_player_name(e ->> 'name')
        <> private.normalize_player_name('Poste laissé vide')
  ),
  bench_row as (
    select
      h.match_id,
      btrim(n.player_name) as source_name,
      private.normalize_player_name(n.player_name) as normalized_name,
      true, false, true, false, 0::integer,
      null::boolean, null::numeric, null::numeric, null::text, null::text
    from public.historical_match_details h
    cross join lateral jsonb_array_elements_text(coalesce(h.bench_players, '[]'::jsonb)) n(player_name)
    where h.match_id = p_match_id
      and btrim(coalesce(n.player_name, '')) <> ''
  ),
  present_row as (
    select
      h.match_id,
      btrim(n.player_name) as source_name,
      private.normalize_player_name(n.player_name) as normalized_name,
      true, false, false, false, 0::integer,
      null::boolean, null::numeric, null::numeric, null::text, null::text
    from public.historical_match_details h
    cross join lateral jsonb_array_elements_text(coalesce(h.present_names, '[]'::jsonb)) n(player_name)
    where h.match_id = p_match_id
      and btrim(coalesce(n.player_name, '')) <> ''
  ),
  scorer_row as (
    select
      h.match_id,
      btrim(e ->> 'name') as source_name,
      private.normalize_player_name(e ->> 'name') as normalized_name,
      true, false, false, false,
      coalesce((e ->> 'goals')::integer, 0),
      null::boolean, null::numeric, null::numeric, null::text, null::text
    from public.historical_match_details h
    cross join lateral jsonb_array_elements(coalesce(h.scorers, '[]'::jsonb)) e
    where h.match_id = p_match_id
      and btrim(coalesce(e ->> 'name', '')) <> ''
  ),
  motm_row as (
    select
      h.match_id,
      btrim(n.player_name) as source_name,
      private.normalize_player_name(n.player_name) as normalized_name,
      true, false, false, true, 0::integer,
      null::boolean, null::numeric, null::numeric, null::text, null::text
    from public.historical_match_details h
    cross join lateral jsonb_array_elements_text(coalesce(h.motm_names, '[]'::jsonb)) n(player_name)
    where h.match_id = p_match_id
      and btrim(coalesce(n.player_name, '')) <> ''
  ),
  all_row as (
    select * from field_row
    union all select * from bench_row
    union all select * from present_row
    union all select * from scorer_row
    union all select * from motm_row
  ),
  aggregated as (
    select
      row.match_id,
      row.normalized_name,
      min(row.source_name) as source_name,
      bool_or(row.is_present) as is_present,
      bool_or(row.is_starter) as is_starter,
      bool_or(row.is_bench) as is_bench,
      bool_or(row.is_motm) as is_motm,
      sum(row.goals)::integer as goals,
      bool_or(row.is_goalkeeper) filter (where row.is_goalkeeper is not null) as is_goalkeeper,
      max(row.x_pct) as x_pct,
      max(row.y_pct) as y_pct,
      max(row.position_code) as position_code,
      max(row.position_label) as position_label
    from all_row row
    where row.normalized_name <> private.normalize_player_name('Poste laissé vide')
    group by row.match_id, row.normalized_name
  ),
  resolved as materialized (
    select
      aggregated.*,
      private.resolve_historical_player_name(aggregated.source_name) as player_id
    from aggregated
  )
  insert into public.historical_match_players(
    match_id,
    player_id,
    source_name,
    is_present,
    is_starter,
    is_bench,
    is_motm,
    goals,
    is_goalkeeper,
    x_pct,
    y_pct,
    position_code,
    position_label
  )
  select
    resolved.match_id,
    resolved.player_id,
    resolved.source_name,
    resolved.is_present,
    resolved.is_starter,
    resolved.is_bench,
    resolved.is_motm,
    resolved.goals,
    resolved.is_goalkeeper,
    resolved.x_pct,
    resolved.y_pct,
    resolved.position_code,
    resolved.position_label
  from resolved
  where resolved.player_id is not null
  on conflict (match_id, player_id) do update
  set
    source_name = excluded.source_name,
    is_present = excluded.is_present,
    is_starter = excluded.is_starter,
    is_bench = excluded.is_bench,
    is_motm = excluded.is_motm,
    goals = excluded.goals,
    is_goalkeeper = excluded.is_goalkeeper,
    x_pct = excluded.x_pct,
    y_pct = excluded.y_pct,
    position_code = excluded.position_code,
    position_label = excluded.position_label;
end;
$function$;

revoke all on function private.refresh_historical_match_players(uuid)
  from public, anon, authenticated;

create or replace function private.sync_historical_match_players()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    perform private.refresh_historical_match_players(old.match_id);
    return old;
  end if;

  perform private.refresh_historical_match_players(new.match_id);
  return new;
end;
$function$;

revoke all on function private.sync_historical_match_players()
  from public, anon, authenticated;

create trigger sync_historical_match_players_after_write
after insert or update or delete on public.historical_match_details
for each row execute function private.sync_historical_match_players();
