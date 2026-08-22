begin;

-- Les parts de titularisation par poste totalisent desormais exactement cent.
--
-- Chaque part etait arrondie independamment, si bien que la somme affichee
-- pouvait valoir 99 ou 101 : un joueur titularise 3 fois au milieu, 3 fois en
-- attaque et 2 fois en defense voyait 38 + 38 + 25 = 101.
--
-- Chaque part est maintenant arrondie a l'entier inferieur, puis les unites
-- restantes vont aux postes dont la decimale supprimee est la plus grande
-- (methode dite du plus fort reste). La somme vaut exactement cent, et chaque
-- part reste a une unite pres de sa valeur exacte.

comment on column public.season_wrapped.position_shares is
  'Part de titularisations a chaque poste, du plus joue au moins joue : '
  '[{"position": "Milieu", "share": 62}, ...]. Les parts sont entieres et '
  'totalisent exactement cent.';

create or replace function private.build_season_wrapped(p_season_id uuid)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rows integer := 0;
  v_min_ranked constant integer := 8;
begin
  if not private.season_wrapped_is_supported(p_season_id) then
    delete from public.season_wrapped where season_id = p_season_id;
    return 0;
  end if;

  delete from public.season_wrapped where season_id = p_season_id;

  with season_matches as (
    select
      match.id,
      match.kickoff_at,
      match.score_as_grinta,
      match.score_adverse
    from public.matches match
    where match.season_id = p_season_id
      and match.status in ('termine', 'archive')
  ),
  roster as (
    select season_player.id as season_player_id, season_player.profile_id
    from public.season_players season_player
    left join public.profiles profile
      on profile.id = season_player.profile_id
    where season_player.season_id = p_season_id
      and coalesce(profile.is_test_account, false) = false
  ),
  -- Même définition de « présent » que l'écran Statistiques.
  presence as (
    select
      present.season_player_id,
      season_matches.score_as_grinta,
      season_matches.score_adverse
    from season_matches
    join (
      select match_id, season_player_id from public.match_attendance
      union
      select match_id, season_player_id from public.match_player_stats
      union
      select match_id, season_player_id from public.match_man_of_match
    ) present on present.match_id = season_matches.id
  ),
  results as (
    select
      presence.season_player_id,
      count(*)::integer as matches_played,
      count(*) filter (
        where presence.score_as_grinta > presence.score_adverse
      )::integer as wins,
      count(*) filter (
        where presence.score_as_grinta = presence.score_adverse
      )::integer as draws,
      count(*) filter (
        where presence.score_as_grinta < presence.score_adverse
      )::integer as losses,
      count(*) filter (where presence.score_adverse = 0)::integer
        as clean_matches
    from presence
    group by presence.season_player_id
  ),
  scored as (
    select
      stat.season_player_id,
      coalesce(sum(stat.goals), 0)::integer as goals
    from public.match_player_stats stat
    join season_matches on season_matches.id = stat.match_id
    group by stat.season_player_id
  ),
  elected as (
    select
      vote.season_player_id,
      count(distinct vote.match_id)::integer as motm
    from public.match_man_of_match vote
    join season_matches on season_matches.id = vote.match_id
    group by vote.season_player_id
  ),
  -- Les 22 emplacements de la feuille de match, regroupés dans le même
  -- vocabulaire de postes que l'archive du club.
  slots(family, sx, sy) as (
    values
      ('Gardien',           0.50, 0.85),
      ('Arrière latéral',   0.10, 0.65),
      ('Arrière latéral',   0.90, 0.65),
      ('Défenseur central', 0.32, 0.70),
      ('Défenseur central', 0.50, 0.72),
      ('Défenseur central', 0.68, 0.70),
      ('Milieu défensif',   0.30, 0.50),
      ('Milieu défensif',   0.50, 0.53),
      ('Milieu défensif',   0.70, 0.50),
      ('Milieu',            0.10, 0.38),
      ('Milieu',            0.34, 0.38),
      ('Milieu',            0.50, 0.40),
      ('Milieu',            0.66, 0.38),
      ('Milieu',            0.90, 0.38),
      ('Milieu offensif',   0.32, 0.25),
      ('Milieu offensif',   0.50, 0.27),
      ('Milieu offensif',   0.68, 0.25),
      ('Ailier',            0.12, 0.22),
      ('Ailier',            0.88, 0.22),
      ('Attaquant',         0.35, 0.10),
      ('Attaquant',         0.50, 0.08),
      ('Attaquant',         0.65, 0.10)
  ),
  field_entries as (
    select participant.season_player_id, entry.x, entry.y
    from public.match_composition_entries entry
    join season_matches on season_matches.id = entry.match_id
    join public.match_sport_participants participant
      on participant.id = entry.participant_id
    where entry.zone = 'field'::public.sport_composition_zone
      and entry.x is not null
      and entry.y is not null
      and participant.season_player_id is not null
  ),
  placed as (
    select field_entries.season_player_id, nearest.family
    from field_entries
    cross join lateral (
      select slots.family
      from slots
      order by
        (slots.sx - field_entries.x) ^ 2
        + (slots.sy - field_entries.y) ^ 2
      limit 1
    ) nearest
  ),
  position_counts as (
    select season_player_id, family, count(*)::integer as played
    from placed
    group by season_player_id, family
  ),
  versatility as (
    select season_player_id, count(*)::integer as versatility
    from position_counts
    group by season_player_id
  ),
  -- Part de titularisations à chaque poste, du plus joué au moins joué.
  -- Les parts totalisent exactement cent : chacune est arrondie à l'entier
  -- inférieur, puis les unités restantes vont aux postes dont la décimale
  -- supprimée est la plus grande.
  position_totals as (
    select season_player_id, sum(played)::numeric as total
    from position_counts
    group by season_player_id
  ),
  position_exact as (
    select
      position_counts.season_player_id,
      position_counts.family,
      position_counts.played,
      floor(100.0 * position_counts.played / position_totals.total)::integer
        as floor_share,
      100.0 * position_counts.played / position_totals.total
        - floor(100.0 * position_counts.played / position_totals.total)
        as remainder
    from position_counts
    join position_totals
      on position_totals.season_player_id = position_counts.season_player_id
  ),
  position_adjusted as (
    select
      position_exact.season_player_id,
      position_exact.family,
      position_exact.played,
      position_exact.floor_share
        + case
            when row_number() over (
              partition by position_exact.season_player_id
              order by
                position_exact.remainder desc,
                position_exact.played desc,
                position_exact.family
            ) <= 100 - sum(position_exact.floor_share) over (
              partition by position_exact.season_player_id
            )
            then 1
            else 0
          end as share
    from position_exact
  ),
  position_shares as (
    select
      position_adjusted.season_player_id,
      jsonb_agg(
        jsonb_build_object(
          'position', position_adjusted.family,
          'share', position_adjusted.share
        )
        order by position_adjusted.played desc, position_adjusted.family
      ) as shares
    from position_adjusted
    group by position_adjusted.season_player_id
  ),
  favourite_position as (
    select distinct on (season_player_id) season_player_id, family
    from position_counts
    order by season_player_id, played desc, family
  ),
  -- Réactivité : délai entre l'ouverture des disponibilités, J-6 à midi
  -- heure de Paris, et la réponse du joueur.
  responses as (
    select
      participant.season_player_id,
      extract(epoch from (
        participant.availability_updated_at
        - (
          (
            ((season_matches.kickoff_at at time zone 'Europe/Paris')::date
              - 6)
            + time '12:00'
          ) at time zone 'Europe/Paris'
        )
      )) / 3600.0 as hours
    from public.match_sport_participants participant
    join season_matches on season_matches.id = participant.match_id
    where participant.season_player_id is not null
      and participant.availability_updated_at is not null
      and participant.availability_status in (
        'available'::public.sport_availability_status,
        'absent'::public.sport_availability_status
      )
  ),
  response_stats as (
    select
      season_player_id,
      count(*)::integer as answered,
      avg(greatest(hours, 0))::numeric(8,2) as avg_response_hours
    from responses
    group by season_player_id
  ),
  base as (
    select
      roster.season_player_id,
      roster.profile_id,
      coalesce(results.matches_played, 0) as matches_played,
      coalesce(results.wins, 0) as wins,
      coalesce(results.draws, 0) as draws,
      coalesce(results.losses, 0) as losses,
      coalesce(results.clean_matches, 0) as clean_matches,
      coalesce(scored.goals, 0) as goals,
      coalesce(elected.motm, 0) as motm,
      coalesce(versatility.versatility, 0) as versatility,
      favourite_position.family as top_position,
      coalesce(position_shares.shares, '[]'::jsonb) as position_shares,
      coalesce(response_stats.answered, 0) as answered,
      response_stats.avg_response_hours
    from roster
    left join results
      on results.season_player_id = roster.season_player_id
    left join scored
      on scored.season_player_id = roster.season_player_id
    left join elected
      on elected.season_player_id = roster.season_player_id
    left join versatility
      on versatility.season_player_id = roster.season_player_id
    left join favourite_position
      on favourite_position.season_player_id = roster.season_player_id
    left join position_shares
      on position_shares.season_player_id = roster.season_player_id
    left join response_stats
      on response_stats.season_player_id = roster.season_player_id
  ),
  -- Un joueur sans aucun match joué n'a pas de bilan.
  pool as (
    select
      base.*,
      round(100.0 * base.wins / base.matches_played, 2) as win_pct,
      (base.matches_played >= v_min_ranked) as ranks_on_average,
      (base.answered >= v_min_ranked) as ranks_on_response
    from base
    where base.matches_played > 0
  ),
  ranked as (
    select
      pool.*,
      count(*) over ()::integer as roster_size,
      rank() over (order by pool.matches_played desc)::integer
        as matches_played_rank,
      rank() over (order by pool.goals desc)::integer as goals_rank,
      rank() over (order by pool.motm desc)::integer as motm_rank,
      rank() over (order by pool.clean_matches desc)::integer
        as clean_matches_rank,
      rank() over (order by pool.versatility desc)::integer
        as versatility_rank,
      rank() over (
        partition by pool.ranks_on_average order by pool.win_pct desc
      )::integer as win_pct_rank_raw,
      count(*) over (partition by pool.ranks_on_average)::integer
        as win_pct_pool_raw,
      rank() over (
        partition by pool.ranks_on_response
        order by pool.avg_response_hours asc
      )::integer as avg_response_rank_raw,
      count(*) over (partition by pool.ranks_on_response)::integer
        as avg_response_pool_raw
    from pool
  )
  insert into public.season_wrapped (
    season_id, season_player_id, profile_id, computed_at, roster_size,
    matches_played, matches_played_rank,
    wins, draws, losses,
    win_pct, win_pct_rank, win_pct_pool,
    avg_response_hours, avg_response_rank, avg_response_pool,
    goals, goals_rank,
    motm, motm_rank,
    clean_matches, clean_matches_rank,
    versatility, versatility_rank,
    top_position,
    position_shares
  )
  select
    p_season_id,
    ranked.season_player_id,
    ranked.profile_id,
    now(),
    ranked.roster_size,
    ranked.matches_played,
    ranked.matches_played_rank,
    ranked.wins,
    ranked.draws,
    ranked.losses,
    ranked.win_pct,
    case when ranked.ranks_on_average then ranked.win_pct_rank_raw end,
    case when ranked.ranks_on_average then ranked.win_pct_pool_raw end,
    ranked.avg_response_hours,
    case when ranked.ranks_on_response
      then ranked.avg_response_rank_raw end,
    case when ranked.ranks_on_response
      then ranked.avg_response_pool_raw end,
    ranked.goals,
    ranked.goals_rank,
    ranked.motm,
    ranked.motm_rank,
    ranked.clean_matches,
    ranked.clean_matches_rank,
    ranked.versatility,
    ranked.versatility_rank,
    ranked.top_position,
    ranked.position_shares
  from ranked;

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$function$;

comment on function private.build_season_wrapped(uuid) is
  'Calcule et remplace le bilan de saison de tous les joueurs d une saison.';

revoke all on function private.build_season_wrapped(uuid)
  from public, anon, authenticated;

-- Le bilan servi à l'application expose la répartition des postes.
create or replace function public.get_my_season_wrapped()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_season record;
  v_result jsonb;
begin
  if not public.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select * into v_season from private.season_wrapped_current_season();
  if not found then
    return null;
  end if;

  select jsonb_build_object(
    'season_name', v_season.season_name,
    'roster_size', wrapped.roster_size,
    'computed_at', wrapped.computed_at,
    'matches_played', wrapped.matches_played,
    'matches_played_rank', wrapped.matches_played_rank,
    'wins', wrapped.wins,
    'draws', wrapped.draws,
    'losses', wrapped.losses,
    'win_pct', wrapped.win_pct,
    'win_pct_rank', wrapped.win_pct_rank,
    'win_pct_pool', wrapped.win_pct_pool,
    'avg_response_hours', wrapped.avg_response_hours,
    'avg_response_rank', wrapped.avg_response_rank,
    'avg_response_pool', wrapped.avg_response_pool,
    'goals', wrapped.goals,
    'goals_rank', wrapped.goals_rank,
    'motm', wrapped.motm,
    'motm_rank', wrapped.motm_rank,
    'clean_matches', wrapped.clean_matches,
    'clean_matches_rank', wrapped.clean_matches_rank,
    'versatility', wrapped.versatility,
    'versatility_rank', wrapped.versatility_rank,
    'top_position', wrapped.top_position,
    'position_shares', wrapped.position_shares
  )
  into v_result
  from public.season_wrapped wrapped
  where wrapped.season_id = v_season.season_id
    and wrapped.profile_id = auth.uid();

  return v_result;
end;
$function$;

comment on function public.get_my_season_wrapped() is
  'Retourne le bilan de saison de l appelant pour la saison qui vient de se terminer.';

revoke all on function public.get_my_season_wrapped()
  from public, anon;
grant execute on function public.get_my_season_wrapped() to authenticated;

commit;
