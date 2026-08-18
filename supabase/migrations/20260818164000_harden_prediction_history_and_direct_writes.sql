-- Harden the prediction contract found during the end-to-end audit.
--
-- 1. Keep archived real pronosticators in historical leaderboards once they
--    actually participated in a revealed match or locked/archived season.
-- 2. Keep test accounts excluded.
-- 3. Canonicalize match_predictions ACLs across environments.
-- 4. Align direct Data API writes with the RPC contract: no internal matches,
--    J-6 at 12:00 Europe/Paris opening and T-15 closing.

create or replace view public.v_classement_general
with (security_invoker = true)
as
with eligible_profiles as (
  select
    p.id,
    p.first_name,
    p.surnom
  from public.profiles p
  where not p.is_test_account
    and (
      p.status = 'active'::text
      or (
        p.status = 'archived'::text
        and (
          exists (
            select 1
            from public.match_predictions mp
            join public.matches m on m.id = mp.match_id
            where mp.profile_id = p.id
              and mp.is_filled
              and m.status in ('termine', 'archive')
          )
          or exists (
            select 1
            from public.season_predictions sp
            join public.seasons s on s.id = sp.season_id
            where sp.predictor_profile_id = p.id
              and sp.is_filled
              and (
                s.season_predictions_locked_at is not null
                or s.status = 'archived'::text
              )
          )
        )
      )
    )
),
match_totals as (
  select
    points.profile_id,
    coalesce(sum(points.points), 0::numeric) as match_points
  from public.v_match_prediction_points points
  group by points.profile_id
),
match_flags as (
  select
    flags.profile_id,
    coalesce(sum(flags.bon_pari), 0::bigint) as match_bons,
    coalesce(sum(flags.exact), 0::bigint) as match_exacts
  from public.v_match_prediction_flags flags
  group by flags.profile_id
),
season_totals as (
  select
    points.predictor_profile_id as profile_id,
    coalesce(sum(points.points), 0::bigint)::numeric as season_points
  from public.v_season_prediction_points points
  group by points.predictor_profile_id
),
season_bonus as (
  select
    bonus.predictor_profile_id as profile_id,
    coalesce(sum(bonus.bonus_points), 0::bigint)::numeric as bonus_points
  from public.v_season_prediction_bonus bonus
  group by bonus.predictor_profile_id
),
season_flags as (
  select
    flags.predictor_profile_id as profile_id,
    coalesce(sum(flags.bon_pari), 0::bigint) as season_bons,
    coalesce(sum(flags.exact), 0::bigint) as season_exacts
  from public.v_season_prediction_flags flags
  group by flags.predictor_profile_id
),
totals as (
  select
    p.id as profile_id,
    p.first_name,
    p.surnom,
    coalesce(mt.match_points, 0::numeric) as match_points,
    coalesce(st.season_points, 0::numeric)
      + coalesce(sb.bonus_points, 0::numeric) as season_points,
    coalesce(mf.match_bons, 0::bigint) as match_bons,
    coalesce(mf.match_exacts, 0::bigint) as match_exacts,
    coalesce(sf.season_bons, 0::bigint) as season_bons,
    coalesce(sf.season_exacts, 0::bigint) as season_exacts
  from eligible_profiles p
  left join match_totals mt on mt.profile_id = p.id
  left join match_flags mf on mf.profile_id = p.id
  left join season_totals st on st.profile_id = p.id
  left join season_bonus sb on sb.profile_id = p.id
  left join season_flags sf on sf.profile_id = p.id
)
select
  profile_id,
  first_name,
  surnom,
  match_points,
  season_points,
  match_points * 100::numeric + season_points as total_points,
  match_bons,
  match_exacts,
  season_bons,
  season_exacts
from totals;

-- Staging had drifted to a different table ACL while production still exposed
-- the intended legacy-compatible SELECT/INSERT/UPDATE surface. Make the ACL
-- explicit so replay, staging and production converge again.
revoke all privileges on table public.match_predictions from authenticated;
grant select, insert, update on table public.match_predictions to authenticated;

drop policy if exists match_predictions_owner_insert
on public.match_predictions;
create policy match_predictions_owner_insert
on public.match_predictions
for insert
to authenticated
with check (
  profile_id = (select auth.uid())
  and (select private.is_active_profile())
  and exists (
    select 1
    from public.matches m
    where m.id = match_predictions.match_id
      and coalesce(m.match_type, 'championnat') <> 'entre_nous'
      and (
        not match_predictions.is_filled
        or (
          m.status = 'a_venir'
          and m.kickoff_at is not null
          and now() >= (
            (
              (m.kickoff_at at time zone 'Europe/Paris')::date - 6
            ) + time '12:00'
          ) at time zone 'Europe/Paris'
          and now() < m.kickoff_at - interval '15 minutes'
          and (
            m.predictions_closed_at is null
            or now() < m.predictions_closed_at
          )
        )
      )
  )
);

drop policy if exists match_predictions_owner_update_window
on public.match_predictions;
create policy match_predictions_owner_update_window
on public.match_predictions
for update
to authenticated
using (
  profile_id = (select auth.uid())
)
with check (
  profile_id = (select auth.uid())
  and (select private.is_active_profile())
  and exists (
    select 1
    from public.matches m
    where m.id = match_predictions.match_id
      and coalesce(m.match_type, 'championnat') <> 'entre_nous'
      and (
        not match_predictions.is_filled
        or (
          m.status = 'a_venir'
          and m.kickoff_at is not null
          and now() >= (
            (
              (m.kickoff_at at time zone 'Europe/Paris')::date - 6
            ) + time '12:00'
          ) at time zone 'Europe/Paris'
          and now() < m.kickoff_at - interval '15 minutes'
          and (
            m.predictions_closed_at is null
            or now() < m.predictions_closed_at
          )
        )
      )
  )
);

create or replace function public.guard_match_prediction_window()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_kickoff timestamptz;
  v_match_status text;
  v_closed_at timestamptz;
  v_match_type text;
begin
  if (select auth.uid()) is not null and pg_trigger_depth() <= 1 then
    if tg_op = 'UPDATE' and new.match_id is distinct from old.match_id then
      raise exception 'Le match d’un pronostic ne peut pas être modifié.'
        using errcode = '22023';
    end if;
    new.profile_id := (select auth.uid());
  end if;

  if new.is_filled then
    select
      m.kickoff_at,
      m.status,
      m.predictions_closed_at,
      m.match_type
    into
      v_kickoff,
      v_match_status,
      v_closed_at,
      v_match_type
    from public.matches m
    where m.id = new.match_id;

    if not found then
      raise exception 'Match introuvable.' using errcode = 'P0002';
    end if;

    if coalesce(v_match_type, 'championnat') = 'entre_nous' then
      raise exception 'Les matchs entre nous ne sont pas ouverts aux pronostics.'
        using errcode = '22023';
    end if;

    if v_kickoff is null
       or v_match_status <> 'a_venir'
       or now() < private.match_features_open_at(v_kickoff)
       or now() >= private.match_prediction_closes_at(v_kickoff)
       or (v_closed_at is not null and now() >= v_closed_at) then
      raise exception 'Pronostic fermé' using errcode = '22023';
    end if;
  end if;

  return new;
end;
$function$;
