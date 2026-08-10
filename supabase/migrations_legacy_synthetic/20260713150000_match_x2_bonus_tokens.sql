begin;

alter table public.match_predictions
  add column if not exists use_x2 boolean not null default false;

comment on column public.match_predictions.use_x2 is
  'Consomme un bonus x2 et double les points obtenus sur ce match.';

create or replace view public.v_x2_wallet
with (security_invoker = true) as
with earned as (
  select mp.profile_id, count(*)::integer as earned_count
  from public.match_predictions mp
  join public.matches m on m.id = mp.match_id
  where mp.is_filled
    and m.status in ('termine', 'archive')
    and m.score_as_grinta is not null
    and m.score_adverse is not null
    and mp.predicted_score_as_grinta = m.score_as_grinta
    and mp.predicted_score_adverse = m.score_adverse
  group by mp.profile_id
), spent as (
  select profile_id, count(*)::integer as spent_count
  from public.match_predictions
  where use_x2
  group by profile_id
)
select
  p.id as profile_id,
  coalesce(e.earned_count, 0) as earned_count,
  coalesce(s.spent_count, 0) as spent_count,
  greatest(coalesce(e.earned_count, 0) - coalesce(s.spent_count, 0), 0) as available_count
from public.profiles p
left join earned e on e.profile_id = p.id
left join spent s on s.profile_id = p.id
where p.status = 'active';

create or replace function public.enforce_match_prediction_x2()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match public.matches%rowtype;
  v_earned integer;
  v_spent integer;
begin
  if tg_op = 'UPDATE' and new.use_x2 = old.use_x2 then
    return new;
  end if;

  select * into v_match from public.matches where id = new.match_id;
  if v_match.id is null then raise exception 'Match introuvable.'; end if;

  if v_match.status <> 'a_venir'
     or now() >= ((v_match.match_date + coalesce(v_match.match_time, time '00:00')) - interval '5 minutes') then
    raise exception 'Le bonus x2 ne peut être modifié que tant que le pronostic est ouvert.';
  end if;

  if new.use_x2 and (tg_op = 'INSERT' or not old.use_x2) then
    select count(*)::integer into v_earned
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id
    where mp.profile_id = new.profile_id
      and mp.is_filled
      and m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
      and mp.predicted_score_as_grinta = m.score_as_grinta
      and mp.predicted_score_adverse = m.score_adverse;

    select count(*)::integer into v_spent
    from public.match_predictions mp
    where mp.profile_id = new.profile_id
      and mp.use_x2
      and (tg_op <> 'UPDATE' or mp.id <> old.id);

    if coalesce(v_earned, 0) - coalesce(v_spent, 0) < 1 then
      raise exception 'Aucun bonus x2 disponible.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_match_prediction_x2 on public.match_predictions;
create trigger trg_enforce_match_prediction_x2
before insert or update of use_x2 on public.match_predictions
for each row execute function public.enforce_match_prediction_x2();

create or replace view public.v_match_prediction_points
with (security_invoker = true) as
select
  mp.id,
  mp.match_id,
  mp.profile_id,
  case
    when not mp.is_filled then 0::numeric
    when sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
         <> sign((m.score_as_grinta - m.score_adverse)::numeric) then 0::numeric
    else
      (case
         when m.score_as_grinta > m.score_adverse then mo.odds_victoire_as_grinta
         when m.score_as_grinta = m.score_adverse then mo.odds_nul
         else mo.odds_victoire_adverse
       end
       * case
           when mp.predicted_score_as_grinta = m.score_as_grinta
                and mp.predicted_score_adverse = m.score_adverse then 2
           when (mp.predicted_score_as_grinta - mp.predicted_score_adverse)
                = (m.score_as_grinta - m.score_adverse) then 1.5
           when mp.predicted_score_as_grinta = m.score_as_grinta
                or mp.predicted_score_adverse = m.score_adverse then 1.5
           else 1
         end::numeric
       * case when mp.use_x2 then 2 else 1 end::numeric)
  end as points
from public.match_predictions mp
join public.matches m on m.id = mp.match_id
  and m.status in ('termine', 'archive')
join public.match_odds mo on mo.match_id = m.id;

grant select on public.v_x2_wallet to authenticated;
grant select on public.v_match_prediction_points to anon, authenticated;

commit;
