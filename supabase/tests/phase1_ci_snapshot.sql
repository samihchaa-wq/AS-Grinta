\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

with
profiles_snapshot as (
  select count(*)::int as row_count,
         md5(coalesce(string_agg(row_to_json(x)::text, ',' order by x.id), '')) as digest
  from (
    select id, email, first_name, last_name, role, status, is_goalkeeper
    from public.profiles
    where email like 'ci-%@example.invalid'
  ) x
),
profile_badges_snapshot as (
  select count(*)::int as row_count,
         md5(coalesce(string_agg(row_to_json(x)::text, ',' order by x.profile_id, x.badge_id), '')) as digest
  from (
    select pb.profile_id, pb.badge_id, pb.source, pb.awarded_by, pb.featured
    from public.profile_badges pb
    join public.profiles p on p.id = pb.profile_id
    where p.email like 'ci-%@example.invalid'
  ) x
),
season_awards_snapshot as (
  select count(*)::int as row_count,
         md5(coalesce(string_agg(row_to_json(x)::text, ',' order by x.profile_id, x.award_type), '')) as digest
  from (
    select sa.season_id, sa.profile_id, sa.award_type
    from public.season_awards sa
    join public.profiles p on p.id = sa.profile_id
    where p.email like 'ci-%@example.invalid'
  ) x
),
statistics_snapshot as (
  select count(*)::int as row_count,
         md5(coalesce(string_agg(row_to_json(x)::text, ',' order by x.period_key, x.display_order, x.player_name), '')) as digest
  from (
    select period_key, period_label, display_rank, display_order, player_name,
           is_goalkeeper, matches_played, wins, draws, losses, goals, hdm, clean_sheets
    from public.v_statistics_players
    where player_name like 'CI %'
  ) x
),
ranking_snapshot as (
  select count(*)::int as row_count,
         md5(coalesce(string_agg(row_to_json(x)::text, ',' order by x.profile_id), '')) as digest
  from (
    select cg.profile_id, cg.first_name, cg.surnom, cg.match_points,
           cg.season_points, cg.total_points, cg.match_bons, cg.match_exacts,
           cg.season_bons, cg.season_exacts
    from public.v_classement_general cg
    join public.profiles p on p.id = cg.profile_id
    where p.email in ('ci-normal@example.invalid', 'ci-admin@example.invalid')
  ) x
),
featured_snapshot as (
  select count(*)::int as row_count,
         md5(coalesce(string_agg(row_to_json(x)::text, ',' order by x.profile_id, x.sort_order, x.code), '')) as digest
  from public.featured_badges() x
)
select jsonb_build_object(
  'profiles', (select jsonb_build_object('count', row_count, 'md5', digest) from profiles_snapshot),
  'profile_badges', (select jsonb_build_object('count', row_count, 'md5', digest) from profile_badges_snapshot),
  'season_awards', (select jsonb_build_object('count', row_count, 'md5', digest) from season_awards_snapshot),
  'statistics', (select jsonb_build_object('count', row_count, 'md5', digest) from statistics_snapshot),
  'ranking', (select jsonb_build_object('count', row_count, 'md5', digest) from ranking_snapshot),
  'featured_badges', (select jsonb_build_object('count', row_count, 'md5', digest) from featured_snapshot)
)::text;
