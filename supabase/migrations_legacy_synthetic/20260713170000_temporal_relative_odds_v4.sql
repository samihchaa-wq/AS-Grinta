-- Moteur V4 fondé uniquement sur les résultats de l'AS Grinta.
-- La récence est continue : demi-vie de 150 jours pour la forme générale et
-- de 365 jours pour les confrontations directes.
-- Toute nouvelle affiche ou modification d'adversaire/lieu recalcule les cotes.

create or replace function public.calculate_match_odds_v4(p_opponent_id uuid, p_location text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_global_form numeric := 0;
  v_global_weight numeric := 0;
  v_venue_effect numeric := 0;
  v_venue_weight numeric := 0;
  v_h2h_effect numeric := 0;
  v_h2h_weight numeric := 0;
  v_confidence numeric := 0;
  v_score numeric := 0;
  v_decisive_win numeric := 0.5;
  v_win_odds numeric;
  v_loss_odds numeric;
  v_draw_odds numeric;
  v_inv_sum numeric;
  v_probability_win numeric;
  v_probability_draw numeric;
  v_probability_loss numeric;
  v_expected_for numeric;
  v_expected_against numeric;
begin
  if p_location not in ('domicile', 'exterieur') then
    raise exception 'Lieu invalide';
  end if;

  if not exists (select 1 from public.opponents where id = p_opponent_id) then
    raise exception 'Adversaire introuvable';
  end if;

  with completed as (
    select
      m.id,
      m.match_date,
      m.location,
      m.opponent_id,
      m.score_as_grinta::numeric as gf,
      m.score_adverse::numeric as ga,
      (
        0.75 * case
          when m.score_as_grinta > m.score_adverse then 1
          when m.score_as_grinta = m.score_adverse then 0
          else -1
        end
        + 0.25 * tanh(((m.score_as_grinta - m.score_adverse)::numeric / 3.0)::double precision)::numeric
      ) as performance,
      power(0.5::numeric, greatest(0, current_date - m.match_date)::numeric / 150.0) as recent_weight
    from public.matches m
    where m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  )
  select
    coalesce(sum(performance * recent_weight) / nullif(sum(recent_weight), 0), 0),
    coalesce(sum(recent_weight), 0),
    coalesce(sum(gf * recent_weight) / nullif(sum(recent_weight), 0), 2.5),
    coalesce(sum(ga * recent_weight) / nullif(sum(recent_weight), 0), 2.5)
  into v_global_form, v_global_weight, v_expected_for, v_expected_against
  from completed;

  with completed as (
    select
      m.location,
      (
        0.75 * case
          when m.score_as_grinta > m.score_adverse then 1
          when m.score_as_grinta = m.score_adverse then 0
          else -1
        end
        + 0.25 * tanh(((m.score_as_grinta - m.score_adverse)::numeric / 3.0)::double precision)::numeric
      ) as performance,
      power(0.5::numeric, greatest(0, current_date - m.match_date)::numeric / 150.0) as recent_weight
    from public.matches m
    where m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  ), venue as (
    select
      coalesce(sum(performance * recent_weight) / nullif(sum(recent_weight), 0), v_global_form) as venue_form,
      coalesce(sum(recent_weight), 0) as venue_weight
    from completed
    where location = p_location
  )
  select
    greatest(-0.18, least(0.18,
      (venue_form - v_global_form) * venue_weight / (venue_weight + 4.0)
    )),
    venue_weight
  into v_venue_effect, v_venue_weight
  from venue;

  with h2h as (
    select
      h.match_date,
      (
        0.75 * case
          when h.score_as_grinta > h.score_adverse then 1
          when h.score_as_grinta = h.score_adverse then 0
          else -1
        end
        + 0.25 * tanh(((h.score_as_grinta - h.score_adverse)::numeric / 3.0)::double precision)::numeric
      ) as performance,
      power(0.5::numeric, greatest(0, current_date - h.match_date)::numeric / 365.0) as time_weight,
      coalesce((
        select
          sum(
            (
              0.75 * case
                when b.score_as_grinta > b.score_adverse then 1
                when b.score_as_grinta = b.score_adverse then 0
                else -1
              end
              + 0.25 * tanh(((b.score_as_grinta - b.score_adverse)::numeric / 3.0)::double precision)::numeric
            )
            * power(0.5::numeric, greatest(0, h.match_date - b.match_date)::numeric / 150.0)
          )
          / nullif(sum(power(0.5::numeric, greatest(0, h.match_date - b.match_date)::numeric / 150.0)), 0)
        from public.matches b
        where b.status in ('termine', 'archive')
          and b.score_as_grinta is not null
          and b.score_adverse is not null
          and b.match_date < h.match_date
      ), 0) as grinta_form_at_that_date
    from public.matches h
    where h.opponent_id = p_opponent_id
      and h.status in ('termine', 'archive')
      and h.score_as_grinta is not null
      and h.score_adverse is not null
  )
  select
    coalesce(sum((performance - grinta_form_at_that_date) * time_weight) / (sum(time_weight) + 2.0), 0),
    coalesce(sum(time_weight), 0)
  into v_h2h_effect, v_h2h_weight
  from h2h;

  v_confidence := v_h2h_weight / (v_h2h_weight + 2.0);
  v_score := greatest(-1.35, least(1.35,
    0.70 * v_global_form + v_venue_effect + v_h2h_effect
  ));

  v_decisive_win := 1.0 / (1.0 + exp((-2.20 * v_score)::double precision));

  v_win_odds := greatest(1.20, least(15.00, 1.0 / greatest(0.0001, v_decisive_win)));
  v_loss_odds := greatest(1.20, least(15.00, 1.0 / greatest(0.0001, 1.0 - v_decisive_win)));
  v_draw_odds := greatest(1.20, least(15.00, ((v_win_odds + v_loss_odds) / 2.0) * 1.20));

  v_inv_sum := (1.0 / v_win_odds) + (1.0 / v_draw_odds) + (1.0 / v_loss_odds);
  v_probability_win := (1.0 / v_win_odds) / v_inv_sum;
  v_probability_draw := (1.0 / v_draw_odds) / v_inv_sum;
  v_probability_loss := (1.0 / v_loss_odds) / v_inv_sum;

  return jsonb_build_object(
    'win', round(v_win_odds, 2),
    'draw', round(v_draw_odds, 2),
    'loss', round(v_loss_odds, 2),
    'probability_win', round(v_probability_win, 6),
    'probability_draw', round(v_probability_draw, 6),
    'probability_loss', round(v_probability_loss, 6),
    'expected_goals_as_grinta', round(v_expected_for, 3),
    'expected_goals_adverse', round(v_expected_against, 3),
    'confidence', round(v_confidence, 3),
    'effective_h2h_weight', round(v_h2h_weight, 3),
    'global_form', round(v_global_form, 4),
    'venue_effect', round(v_venue_effect, 4),
    'matchup_effect', round(v_h2h_effect, 4),
    'score', round(v_score, 4),
    'model_version', 'temporal_relative_v4'
  );
end;
$function$;

create or replace function public.preview_match_odds(p_opponent_id uuid, p_location text)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select public.calculate_match_odds_v4(p_opponent_id, p_location);
$function$;

create or replace function public.upsert_match_odds_v4(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_match record;
  v_result jsonb;
begin
  select id, opponent_id, location, status
  into v_match
  from public.matches
  where id = p_match_id;

  if not found or v_match.status <> 'a_venir' then
    return;
  end if;

  v_result := public.calculate_match_odds_v4(v_match.opponent_id, v_match.location);

  insert into public.match_odds(
    match_id, odds_victoire_as_grinta, odds_nul, odds_victoire_adverse,
    probability_win, probability_draw, probability_loss,
    expected_goals_as_grinta, expected_goals_adverse,
    confidence, model_version, computed_at
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
end;
$function$;

create or replace function public.recalculate_upcoming_match_odds_v4()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_match record;
  v_count integer := 0;
begin
  for v_match in select id from public.matches where status = 'a_venir'
  loop
    perform public.upsert_match_odds_v4(v_match.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

create or replace function public.trigger_match_odds_v4()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if tg_op = 'INSERT' then
    if new.status = 'a_venir' then
      perform public.upsert_match_odds_v4(new.id);
    end if;
  elsif new.status = 'a_venir' and (
    old.opponent_id is distinct from new.opponent_id
    or old.location is distinct from new.location
    or old.status is distinct from new.status
  ) then
    perform public.upsert_match_odds_v4(new.id);
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_auto_match_odds_v4 on public.matches;
create trigger trg_auto_match_odds_v4
after insert or update of opponent_id, location, status on public.matches
for each row execute function public.trigger_match_odds_v4();

create or replace function public.trigger_recalculate_upcoming_odds_v3()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.status in ('termine', 'archive')
     and new.score_as_grinta is not null
     and new.score_adverse is not null
     and (
       old.status is distinct from new.status
       or old.score_as_grinta is distinct from new.score_as_grinta
       or old.score_adverse is distinct from new.score_adverse
     ) then
    perform public.recalculate_upcoming_match_odds_v4();
  end if;
  return new;
end;
$function$;

create or replace function public.create_match_with_odds(
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  new_id uuid;
begin
  if not public.is_match_staff() then raise exception 'Staff role required'; end if;
  if p_location not in ('domicile','exterieur') then raise exception 'Invalid location'; end if;

  insert into public.matches(
    season_id, opponent_id, match_date, match_time, location,
    planned_duration_minutes, status, created_by
  ) values (
    p_season_id, p_opponent_id, p_match_date, p_match_time, p_location,
    90, 'a_venir', auth.uid()
  ) returning id into new_id;

  perform public.upsert_match_odds_v4(new_id);
  return new_id;
end;
$function$;

select public.recalculate_upcoming_match_odds_v4();
