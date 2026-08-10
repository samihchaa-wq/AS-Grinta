begin;

create table if not exists public.historical_match_scores (
  id uuid primary key,
  opponent_id uuid not null references public.opponents(id) on delete restrict,
  match_date date not null,
  score_as_grinta smallint not null check (score_as_grinta between 0 and 99),
  score_adverse smallint not null check (score_adverse between 0 and 99)
);

comment on table public.historical_match_scores is
  'Minimal historical results retained only for chronological opponent form and odds calculations.';

create index if not exists historical_match_scores_opponent_date_idx
  on public.historical_match_scores(opponent_id, match_date desc, id desc);
create index if not exists historical_match_scores_date_idx
  on public.historical_match_scores(match_date desc, id desc);

alter table public.historical_match_scores enable row level security;
revoke all on public.historical_match_scores from anon, authenticated;

insert into public.historical_match_scores (
  id, opponent_id, match_date, score_as_grinta, score_adverse
)
select id, opponent_id, match_date, score_as_grinta, score_adverse
from public.matches
where status = 'archive'
  and score_as_grinta is not null
  and score_adverse is not null
on conflict (id) do update set
  opponent_id = excluded.opponent_id,
  match_date = excluded.match_date,
  score_as_grinta = excluded.score_as_grinta,
  score_adverse = excluded.score_adverse;

create or replace function public.calculate_match_odds_v5(
  p_opponent_id uuid,
  p_reference_date date
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ref date := coalesce(p_reference_date, current_date);
  v_h_v numeric := 0;
  v_h_d numeric := 0;
  v_form_v numeric := 0;
  v_form_d numeric := 0;
  v_q_forme numeric;
  v_q numeric;
  v_cote_v_prov numeric;
  v_cote_d_prov numeric;
  v_cote_n_prov numeric;
  v_u_v numeric;
  v_u_n numeric;
  v_u_d numeric;
  v_s numeric;
  v_p_v numeric;
  v_p_n numeric;
  v_p_d numeric;
begin
  if not exists (select 1 from public.opponents where id = p_opponent_id) then
    raise exception 'Adversaire introuvable';
  end if;

  with all_results as (
    select m.id, m.opponent_id, m.match_date,
      m.score_as_grinta, m.score_adverse
    from public.matches m
    where m.status = 'termine'
      and m.score_as_grinta is not null
      and m.score_adverse is not null
    union all
    select h.id, h.opponent_id, h.match_date,
      h.score_as_grinta::integer, h.score_adverse::integer
    from public.historical_match_scores h
  ), h2h as (
    select
      case
        when r.score_as_grinta > r.score_adverse then 'V'
        when r.score_as_grinta = r.score_adverse then 'N'
        else 'D'
      end as result,
      row_number() over (
        order by r.match_date desc, r.id desc
      ) as rang,
      greatest(0, (v_ref - r.match_date))::numeric as age
    from all_results r
    where r.opponent_id = p_opponent_id
      and r.match_date < v_ref
  ), weighted as (
    select result,
      case
        when rang <= 5 then
          (array[1.0, 0.95, 0.90, 0.85, 0.80])[rang::int]
            * power(0.5::numeric, age / 900.0)
        else
          0.35 * power(0.75::numeric, (rang - 6)::numeric)
            * power(0.5::numeric, age / 900.0)
      end as poids
    from h2h
  )
  select
    coalesce(sum(poids) filter (where result = 'V'), 0),
    coalesce(sum(poids) filter (where result = 'D'), 0)
  into v_h_v, v_h_d
  from weighted;

  with all_results as (
    select m.id, m.match_date, m.score_as_grinta, m.score_adverse
    from public.matches m
    where m.status = 'termine'
      and m.score_as_grinta is not null
      and m.score_adverse is not null
    union all
    select h.id, h.match_date,
      h.score_as_grinta::integer, h.score_adverse::integer
    from public.historical_match_scores h
  ), form as (
    select
      case
        when r.score_as_grinta > r.score_adverse then 'V'
        when r.score_as_grinta = r.score_adverse then 'N'
        else 'D'
      end as result,
      power(
        0.5::numeric,
        greatest(0, (v_ref - r.match_date))::numeric / 180.0
      ) as poids
    from all_results r
    where r.match_date < v_ref
  )
  select
    coalesce(sum(poids) filter (where result = 'V'), 0),
    coalesce(sum(poids) filter (where result = 'D'), 0)
  into v_form_v, v_form_d
  from form;

  if (v_form_v + v_form_d) = 0 then
    v_q_forme := 0.50;
  else
    v_q_forme := v_form_v / (v_form_v + v_form_d);
  end if;

  v_q := (1.0 * v_q_forme + v_h_v) / (1.0 + v_h_v + v_h_d);
  v_q := least(0.999999, greatest(0.000001, v_q));

  v_cote_v_prov := 1.0 / v_q;
  v_cote_d_prov := 1.0 / (1.0 - v_q);
  v_cote_n_prov := ((v_cote_v_prov + v_cote_d_prov) / 2.0) * 1.50;

  v_u_v := 1.0 / v_cote_v_prov;
  v_u_n := 1.0 / v_cote_n_prov;
  v_u_d := 1.0 / v_cote_d_prov;
  v_s := v_u_v + v_u_n + v_u_d;
  v_p_v := v_u_v / v_s;
  v_p_n := v_u_n / v_s;
  v_p_d := v_u_d / v_s;

  return jsonb_build_object(
    'win', round(1.0 / v_p_v, 2),
    'draw', round(1.0 / v_p_n, 2),
    'loss', round(1.0 / v_p_d, 2),
    'probability_win', round(v_p_v, 6),
    'probability_draw', round(v_p_n, 6),
    'probability_loss', round(v_p_d, 6),
    'q_decisive', round(v_q, 6),
    'q_form', round(v_q_forme, 6),
    'h2h_win_weight', round(v_h_v, 6),
    'h2h_loss_weight', round(v_h_d, 6),
    'model_version', 'compact_history_v6'
  );
end;
$$;

do $$
declare
  v_match_id uuid;
begin
  for v_match_id in
    select id from public.matches where status = 'archive'
  loop
    delete from public.match_sport_motm_votes where match_id = v_match_id;
    delete from public.match_sport_motm_results where match_id = v_match_id;
    delete from public.match_man_of_match where match_id = v_match_id;
    delete from public.match_sport_motm_elections where match_id = v_match_id;
    delete from public.match_composition_entries where match_id = v_match_id;
    delete from public.match_composition_publications where match_id = v_match_id;
    delete from public.match_compositions where match_id = v_match_id;
    delete from public.match_sport_participant_events where match_id = v_match_id;
    delete from public.sport_availability_notification_events where match_id = v_match_id;
    delete from public.match_sport_finalization_versions where match_id = v_match_id;
    delete from public.match_sport_finalizations where match_id = v_match_id;
    delete from public.match_sport_participants where match_id = v_match_id;
    delete from public.match_sport_workflows where match_id = v_match_id;
    delete from public.match_attendance where match_id = v_match_id;
    delete from public.match_player_stats where match_id = v_match_id;
    delete from public.match_predictions where match_id = v_match_id;
    delete from public.match_odds where match_id = v_match_id;
    delete from public.push_delivery_log where match_id = v_match_id;
    delete from public.push_notification_log where match_id = v_match_id;
    delete from private.sport_admin_audit_log where match_id = v_match_id;
    delete from public.matches where id = v_match_id;
  end loop;
end;
$$;

commit;
