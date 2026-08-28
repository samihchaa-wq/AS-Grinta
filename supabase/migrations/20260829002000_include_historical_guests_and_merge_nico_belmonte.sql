begin;

-- Historical guest players must remain visible anywhere their archived
-- appearances are used (statistics, historical squads and compositions).
-- Also consolidate the known duplicate identity "Nico Pote Milan" into
-- "Nicolas Belmonte" while preserving the historical source alias.

do $$
declare
  v_keep uuid;
  v_drop uuid;
begin
  select id into v_keep
  from public.players
  where lower(btrim(display_name)) = lower('Nicolas Belmonte')
  limit 1;

  select id into v_drop
  from public.players
  where lower(btrim(display_name)) = lower('Nico Pote Milan')
  limit 1;

  -- Synthetic/staging databases may contain neither historical identity.
  -- That is valid: the generic historical backfill below can still run.
  if v_keep is null and v_drop is null then
    null;
  elsif v_keep is null and v_drop is not null then
    raise exception 'Nico Pote Milan exists but canonical Nicolas Belmonte is missing';
  elsif v_drop is not null and v_drop <> v_keep then
    if exists (
      select 1
      from public.historical_match_players old_row
      join public.historical_match_players keep_row
        on keep_row.match_id = old_row.match_id
       and keep_row.player_id = v_keep
      where old_row.player_id = v_drop
    ) then
      raise exception 'Cannot merge Nico Pote Milan into Nicolas Belmonte: overlapping historical match';
    end if;

    update public.historical_match_players
    set player_id = v_keep
    where player_id = v_drop;

    update public.historical_player_name_links
    set player_id = v_keep,
        updated_at = now()
    where player_id = v_drop;

    update public.player_aliases
    set player_id = v_keep
    where player_id = v_drop;

    insert into public.player_aliases(player_id, alias)
    select v_keep, 'Nico Pote Milan'
    where not exists (
      select 1
      from public.player_aliases
      where player_id = v_keep
        and lower(btrim(alias)) = lower('Nico Pote Milan')
    );

    update public.profiles set player_id = v_keep where player_id = v_drop;
    update public.season_players set player_id = v_keep where player_id = v_drop;
    update public.guest_players set player_id = v_keep where player_id = v_drop;

    delete from public.historical_player_statistics
    where player_id = v_drop;

    update public.historical_match_details
    set field_players = replace(field_players::text, '"Nico Pote Milan"', '"Nicolas Belmonte"')::jsonb,
        bench_players = replace(bench_players::text, '"Nico Pote Milan"', '"Nicolas Belmonte"')::jsonb,
        present_names = replace(present_names::text, '"Nico Pote Milan"', '"Nicolas Belmonte"')::jsonb,
        scorers = replace(scorers::text, '"Nico Pote Milan"', '"Nicolas Belmonte"')::jsonb,
        motm_names = replace(motm_names::text, '"Nico Pote Milan"', '"Nicolas Belmonte"')::jsonb
    where field_players::text like '%Nico Pote Milan%'
       or bench_players::text like '%Nico Pote Milan%'
       or present_names::text like '%Nico Pote Milan%'
       or scorers::text like '%Nico Pote Milan%'
       or motm_names::text like '%Nico Pote Milan%';

    delete from public.players where id = v_drop;
  end if;
end
$$;

-- Recompute Nicolas Belmonte only when that canonical identity exists. Existing
-- imported rows for everyone else remain untouched because a few contain
-- manually corrected historical values.
with agg as (
  select
    h.player_id,
    count(*) filter (where h.is_present)::integer as matches_played,
    count(*) filter (where h.is_present and m.score_as_grinta > m.score_adverse)::integer as wins,
    count(*) filter (where h.is_present and m.score_as_grinta = m.score_adverse)::integer as draws,
    count(*) filter (where h.is_present and m.score_as_grinta < m.score_adverse)::integer as losses,
    coalesce(sum(h.goals) filter (where h.is_present), 0)::integer as goals,
    count(*) filter (where h.is_present and h.is_motm)::integer as hdm,
    count(*) filter (where h.is_present and m.score_adverse = 0)::integer as team_clean_sheets,
    count(*) filter (
      where h.is_present
        and coalesce(h.is_goalkeeper, false)
        and m.score_adverse = 0
    )::integer as clean_sheets
  from public.historical_match_players h
  join public.historical_match_scores m on m.id = h.match_id
  join public.players p on p.id = h.player_id
  where lower(btrim(p.display_name)) = lower('Nicolas Belmonte')
  group by h.player_id
)
update public.historical_player_statistics s
set matches_played = a.matches_played,
    wins = a.wins,
    draws = a.draws,
    losses = a.losses,
    goals = a.goals,
    hdm = a.hdm,
    team_clean_sheets = a.team_clean_sheets,
    clean_sheets = a.clean_sheets,
    player_name = 'Nicolas Belmonte',
    updated_at = now()
from agg a
where s.scope = 'all_time'
  and s.player_id = a.player_id;

-- Backfill every historical identity that has real appearances but was omitted
-- from the imported all-time ranking.
with raw as (
  select
    h.player_id,
    count(*) filter (where h.is_present)::integer as matches_played,
    count(*) filter (where h.is_present and m.score_as_grinta > m.score_adverse)::integer as wins,
    count(*) filter (where h.is_present and m.score_as_grinta = m.score_adverse)::integer as draws,
    count(*) filter (where h.is_present and m.score_as_grinta < m.score_adverse)::integer as losses,
    coalesce(sum(h.goals) filter (where h.is_present), 0)::integer as goals,
    count(*) filter (where h.is_present and h.is_motm)::integer as hdm,
    bool_and(coalesce(h.is_goalkeeper, false)) filter (where h.is_present) as is_goalkeeper,
    count(*) filter (where h.is_present and m.score_adverse = 0)::integer as team_clean_sheets,
    count(*) filter (
      where h.is_present
        and coalesce(h.is_goalkeeper, false)
        and m.score_adverse = 0
    )::integer as clean_sheets
  from public.historical_match_players h
  join public.historical_match_scores m on m.id = h.match_id
  group by h.player_id
), ranked as (
  select
    r.*,
    p.display_name,
    rank() over (
      partition by coalesce(r.is_goalkeeper, false)
      order by r.matches_played desc, r.goals desc, p.display_name
    )::integer as display_rank
  from raw r
  join public.players p on p.id = r.player_id
  where r.matches_played > 0
)
insert into public.historical_player_statistics(
  scope, season_name, display_rank, player_name, is_goalkeeper,
  matches_played, wins, draws, losses, goals, hdm, clean_sheets,
  source_label, profile_id, team_clean_sheets, player_id
)
select
  'all_time', null, r.display_rank, r.display_name, coalesce(r.is_goalkeeper, false),
  r.matches_played, r.wins, r.draws, r.losses, r.goals, r.hdm,
  case when coalesce(r.is_goalkeeper, false) then r.clean_sheets else 0 end,
  'normalized_historical_matches_backfill',
  (
    select pr.id
    from public.profiles pr
    where pr.player_id = r.player_id
    order by pr.created_at
    limit 1
  ),
  r.team_clean_sheets, r.player_id
from ranked r
where not exists (
  select 1
  from public.historical_player_statistics s
  where s.scope = 'all_time'
    and s.player_id = r.player_id
);

-- 2025-2026 is the previous season at migration time. Backfill any archived
-- participant omitted from that period's imported roster/statistics.
with raw as (
  select
    h.player_id,
    count(*) filter (where h.is_present)::integer as matches_played,
    count(*) filter (where h.is_present and m.score_as_grinta > m.score_adverse)::integer as wins,
    count(*) filter (where h.is_present and m.score_as_grinta = m.score_adverse)::integer as draws,
    count(*) filter (where h.is_present and m.score_as_grinta < m.score_adverse)::integer as losses,
    coalesce(sum(h.goals) filter (where h.is_present), 0)::integer as goals,
    count(*) filter (where h.is_present and h.is_motm)::integer as hdm,
    bool_and(coalesce(h.is_goalkeeper, false)) filter (where h.is_present) as is_goalkeeper,
    count(*) filter (where h.is_present and m.score_adverse = 0)::integer as team_clean_sheets,
    count(*) filter (
      where h.is_present
        and coalesce(h.is_goalkeeper, false)
        and m.score_adverse = 0
    )::integer as clean_sheets
  from public.historical_match_players h
  join public.historical_match_scores m on m.id = h.match_id
  where m.match_date >= date '2025-07-01'
    and m.match_date < date '2026-07-01'
  group by h.player_id
), ranked as (
  select
    r.*,
    p.display_name,
    rank() over (
      partition by coalesce(r.is_goalkeeper, false)
      order by r.matches_played desc, r.goals desc, p.display_name
    )::integer as display_rank
  from raw r
  join public.players p on p.id = r.player_id
  where r.matches_played > 0
)
insert into public.historical_player_statistics(
  scope, season_name, display_rank, player_name, is_goalkeeper,
  matches_played, wins, draws, losses, goals, hdm, clean_sheets,
  source_label, profile_id, team_clean_sheets, player_id
)
select
  'previous', '2025-2026', r.display_rank, r.display_name, coalesce(r.is_goalkeeper, false),
  r.matches_played, r.wins, r.draws, r.losses, r.goals, r.hdm,
  case when coalesce(r.is_goalkeeper, false) then r.clean_sheets else 0 end,
  'normalized_historical_matches_backfill',
  (
    select pr.id
    from public.profiles pr
    where pr.player_id = r.player_id
    order by pr.created_at
    limit 1
  ),
  r.team_clean_sheets, r.player_id
from ranked r
where not exists (
  select 1
  from public.historical_player_statistics s
  where s.scope = 'previous'
    and s.player_id = r.player_id
);

commit;
