-- Dynamic odds model V3
-- Replays recent team and opponent form with exponential decay, Poisson score
-- probabilities, Bayesian uncertainty shrinkage, and automatic recalculation.

alter table public.match_odds
  add column if not exists probability_win numeric,
  add column if not exists probability_draw numeric,
  add column if not exists probability_loss numeric,
  add column if not exists expected_goals_as_grinta numeric,
  add column if not exists expected_goals_adverse numeric,
  add column if not exists confidence numeric,
  add column if not exists model_version text not null default 'legacy';

create or replace function public.calculate_match_odds_v3(
  p_opponent_id uuid,
  p_location text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_n integer;
  v_global_gf numeric;
  v_global_ga numeric;
  v_global_form numeric;
  v_opp_gf numeric;
  v_opp_ga numeric;
  v_opp_form numeric;
  v_momentum numeric;
  v_venue_gf numeric;
  v_venue_ga numeric;
  v_opp_weight numeric;
  v_lambda_for numeric;
  v_lambda_against numeric;
  v_pw numeric;
  v_pd numeric;
  v_pl numeric;
  v_raw_win numeric;
  v_raw_draw numeric;
  v_raw_loss numeric;
  v_conf numeric;
  v_win numeric;
  v_draw numeric;
  v_loss numeric;
begin
  if p_location not in ('domicile', 'exterieur') then
    raise exception 'Lieu invalide';
  end if;

  if not exists (select 1 from public.opponents where id = p_opponent_id) then
    raise exception 'Adversaire introuvable';
  end if;

  with base as (
    select
      m.match_date,
      m.created_at,
      m.location,
      m.opponent_id,
      m.score_as_grinta::numeric as gf,
      m.score_adverse::numeric as ga,
      row_number() over(order by m.match_date desc, m.created_at desc) as rn_global,
      row_number() over(
        partition by m.opponent_id
        order by m.match_date desc, m.created_at desc
      ) as rn_opp
    from public.matches m
    where m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  )
  select
    sum(gf * power(0.5::numeric, (rn_global - 1) / 8.0))
      / nullif(sum(power(0.5::numeric, (rn_global - 1) / 8.0)), 0),
    sum(ga * power(0.5::numeric, (rn_global - 1) / 8.0))
      / nullif(sum(power(0.5::numeric, (rn_global - 1) / 8.0)), 0),
    sum(
      (case when gf > ga then 1 when gf = ga then 0.5 else 0 end)
      * power(0.5::numeric, (rn_global - 1) / 5.0)
    ) / nullif(sum(power(0.5::numeric, (rn_global - 1) / 5.0)), 0)
  into v_global_gf, v_global_ga, v_global_form
  from base
  where rn_global <= 30;

  v_global_gf := coalesce(v_global_gf, 3.5);
  v_global_ga := coalesce(v_global_ga, 2.5);
  v_global_form := coalesce(v_global_form, 0.5);

  with base as (
    select
      m.score_as_grinta::numeric as gf,
      m.score_adverse::numeric as ga,
      row_number() over(order by m.match_date desc, m.created_at desc) as rn
    from public.matches m
    where m.opponent_id = p_opponent_id
      and m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  )
  select
    count(*)::integer,
    sum(gf * power(0.5::numeric, (rn - 1) / 2.5))
      / nullif(sum(power(0.5::numeric, (rn - 1) / 2.5)), 0),
    sum(ga * power(0.5::numeric, (rn - 1) / 2.5))
      / nullif(sum(power(0.5::numeric, (rn - 1) / 2.5)), 0),
    sum(
      (case when gf > ga then 1 when gf = ga then 0.5 else 0 end)
      * power(0.5::numeric, (rn - 1) / 2.0)
    ) / nullif(sum(power(0.5::numeric, (rn - 1) / 2.0)), 0),
    coalesce(sum(
      (case when gf > ga then 1 when gf = ga then 0 else -1 end)
      * case rn when 1 then 0.50 when 2 then 0.30 when 3 then 0.20 else 0 end
    ), 0)
  into v_n, v_opp_gf, v_opp_ga, v_opp_form, v_momentum
  from base;

  v_n := coalesce(v_n, 0);
  v_opp_gf := coalesce(v_opp_gf, v_global_gf);
  v_opp_ga := coalesce(v_opp_ga, v_global_ga);
  v_opp_form := coalesce(v_opp_form, v_global_form);
  v_momentum := coalesce(v_momentum, 0);

  with recent as (
    select
      m.location,
      m.score_as_grinta::numeric as gf,
      m.score_adverse::numeric as ga,
      row_number() over(order by m.match_date desc, m.created_at desc) as rn
    from public.matches m
    where m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  )
  select avg(gf), avg(ga)
  into v_venue_gf, v_venue_ga
  from recent
  where rn <= 40 and location = p_location;

  v_venue_gf := coalesce(v_venue_gf, v_global_gf);
  v_venue_ga := coalesce(v_venue_ga, v_global_ga);

  v_opp_weight := least(0.78, 0.20 + 0.58 * (1 - exp(-v_n / 6.0)));

  v_lambda_for := greatest(0.30, least(8.00,
    ((1 - v_opp_weight) * v_global_gf + v_opp_weight * v_opp_gf)
    * power(greatest(0.65, least(1.45, v_venue_gf / nullif(v_global_gf, 0))), 0.35)
    * exp(0.22 * (v_opp_form - v_global_form) + 0.18 * v_momentum)
  ));

  v_lambda_against := greatest(0.30, least(8.00,
    ((1 - v_opp_weight) * v_global_ga + v_opp_weight * v_opp_ga)
    * power(greatest(0.65, least(1.45, v_venue_ga / nullif(v_global_ga, 0))), 0.35)
    * exp(-0.18 * (v_opp_form - v_global_form) - 0.16 * v_momentum)
  ));

  select
    sum(case when x > y then probability else 0 end),
    sum(case when x = y then probability else 0 end),
    sum(case when x < y then probability else 0 end)
  into v_pw, v_pd, v_pl
  from generate_series(0, 16) x
  cross join generate_series(0, 16) y
  cross join lateral (
    select
      exp(-v_lambda_for) * power(v_lambda_for, x) / factorial(x)::numeric
      * exp(-v_lambda_against) * power(v_lambda_against, y) / factorial(y)::numeric
      as probability
  ) p;

  v_raw_win := v_pw / nullif(v_pw + v_pl + v_pd * 0.90, 0);
  v_raw_draw := v_pd * 0.90 / nullif(v_pw + v_pl + v_pd * 0.90, 0);
  v_raw_loss := v_pl / nullif(v_pw + v_pl + v_pd * 0.90, 0);

  v_conf := least(0.88, v_n::numeric / (v_n + 3.0));
  v_win := v_conf * v_raw_win + (1 - v_conf) * 0.65;
  v_draw := v_conf * v_raw_draw + (1 - v_conf) * 0.12;
  v_loss := v_conf * v_raw_loss + (1 - v_conf) * 0.23;

  v_win := greatest(0.08, least(0.85, v_win));
  v_draw := greatest(0.06, least(0.30, v_draw));
  v_loss := greatest(0.06, least(0.85, v_loss));

  v_pw := v_win + v_draw + v_loss;
  v_win := v_win / v_pw;
  v_draw := v_draw / v_pw;
  v_loss := v_loss / v_pw;

  return jsonb_build_object(
    'win', round((1 / v_win)::numeric, 2),
    'draw', round((1 / v_draw)::numeric, 2),
    'loss', round((1 / v_loss)::numeric, 2),
    'probability_win', round(v_win, 6),
    'probability_draw', round(v_draw, 6),
    'probability_loss', round(v_loss, 6),
    'expected_goals_as_grinta', round(v_lambda_for, 3),
    'expected_goals_adverse', round(v_lambda_against, 3),
    'confidence', round(v_conf, 3),
    'opponent_matches', v_n,
    'model_version', 'dynamic_v3'
  );
end;
$$;

revoke execute on function public.calculate_match_odds_v3(uuid, text)
from public, anon, authenticated;

create or replace function public.preview_match_odds(
  p_opponent_id uuid,
  p_location text
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public.calculate_match_odds_v3(p_opponent_id, p_location);
$$;

revoke execute on function public.preview_match_odds(uuid, text) from public, anon;
grant execute on function public.preview_match_odds(uuid, text) to authenticated;

create or replace function public.recalculate_upcoming_match_odds_v3()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match record;
  v_result jsonb;
  v_count integer := 0;
begin
  for v_match in
    select id, opponent_id, location
    from public.matches
    where status = 'a_venir'
  loop
    v_result := public.calculate_match_odds_v3(v_match.opponent_id, v_match.location);

    insert into public.match_odds(
      match_id,
      odds_victoire_as_grinta,
      odds_nul,
      odds_victoire_adverse,
      probability_win,
      probability_draw,
      probability_loss,
      expected_goals_as_grinta,
      expected_goals_adverse,
      confidence,
      model_version,
      computed_at
    ) values (
      v_match.id,
      (v_result->>'win')::numeric,
      (v_result->>'draw')::numeric,
      (v_result->>'loss')::numeric,
      (v_result->>'probability_win')::numeric,
      (v_result->>'probability_draw')::numeric,
      (v_result->>'probability_loss')::numeric,
      (v_result->>'expected_goals_as_grinta')::numeric,
      (v_result->>'expected_goals_adverse')::numeric,
      (v_result->>'confidence')::numeric,
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
        expected_goals_as_grinta = excluded.expected_goals_as_grinta,
        expected_goals_adverse = excluded.expected_goals_adverse,
        confidence = excluded.confidence,
        model_version = excluded.model_version,
        computed_at = excluded.computed_at;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke execute on function public.recalculate_upcoming_match_odds_v3()
from public, anon, authenticated;

create or replace function public.trigger_recalculate_upcoming_odds_v3()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('termine', 'archive')
     and new.score_as_grinta is not null
     and new.score_adverse is not null
     and (
       old.status is distinct from new.status
       or old.score_as_grinta is distinct from new.score_as_grinta
       or old.score_adverse is distinct from new.score_adverse
     ) then
    perform public.recalculate_upcoming_match_odds_v3();
  end if;
  return new;
end;
$$;

revoke execute on function public.trigger_recalculate_upcoming_odds_v3()
from public, anon, authenticated;

drop trigger if exists trg_recalculate_upcoming_odds_v3 on public.matches;
create trigger trg_recalculate_upcoming_odds_v3
after update of status, score_as_grinta, score_adverse
on public.matches
for each row
execute function public.trigger_recalculate_upcoming_odds_v3();

select public.recalculate_upcoming_match_odds_v3();