-- Test autonome du barème saison N × 3.
-- Exécution : psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/season_scoring_nx3.sql

begin;

do $$
declare
  first_points integer;
  tied_first_points integer;
  third_points integer;
  half_bonus integer;
  three_quarter_bonus integer;
  perfect_bonus integer;
begin
  with predictions as (
    select i as predictor,
           case
             when i in (1, 2) then 15
             else 13 + i
           end as predicted_value,
           15 as target
    from generate_series(1, 18) as g(i)
  ), ranked as (
    select predictor,
           predicted_value,
           target,
           count(*) over () as participant_count,
           rank() over (order by abs(predicted_value - target)) as proximity_rank
    from predictions
  ), scored as (
    select predictor,
           (
             (participant_count - proximity_rank + 1)
             * 3
             * case when predicted_value = target then 2 else 1 end
           )::integer as points
    from ranked
  )
  select max(points) filter (where predictor = 1),
         max(points) filter (where predictor = 2),
         max(points) filter (where predictor = 3)
  into first_points, tied_first_points, third_points
  from scored;

  if first_points <> 108 or tied_first_points <> 108 then
    raise exception 'Les deux ex aequo premiers doivent obtenir 108 points chacun';
  end if;

  if third_points <> 48 then
    raise exception 'Après deux premiers ex aequo, le suivant doit être 3e avec 48 points';
  end if;

  select case
           when correct_pairs * 2 <= total_pairs then 0
           else round(
             participants::numeric * 30.0
             * (2 * correct_pairs - total_pairs)::numeric
             / total_pairs::numeric
           )::integer
         end
  into half_bonus
  from (values (18, 50, 100)) as sample(participants, correct_pairs, total_pairs);

  select case
           when correct_pairs * 2 <= total_pairs then 0
           else round(
             participants::numeric * 30.0
             * (2 * correct_pairs - total_pairs)::numeric
             / total_pairs::numeric
           )::integer
         end
  into three_quarter_bonus
  from (values (18, 75, 100)) as sample(participants, correct_pairs, total_pairs);

  select case
           when correct_pairs * 2 <= total_pairs then 0
           else round(
             participants::numeric * 30.0
             * (2 * correct_pairs - total_pairs)::numeric
             / total_pairs::numeric
           )::integer
         end
  into perfect_bonus
  from (values (18, 100, 100)) as sample(participants, correct_pairs, total_pairs);

  if half_bonus <> 0 then
    raise exception 'Le bonus doit être nul à 50 %% de duels corrects';
  end if;

  if three_quarter_bonus <> 270 then
    raise exception 'Le bonus doit être de 270 points à 75 %% pour N = 18';
  end if;

  if perfect_bonus <> 540 then
    raise exception 'Le bonus parfait doit être de 540 points pour N = 18';
  end if;
end
$$;

rollback;
