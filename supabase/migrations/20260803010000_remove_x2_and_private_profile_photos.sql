-- Remove the match-prediction x2 system and make profile photos private.
-- The legacy four-argument prediction RPC is kept as a compatibility shim,
-- but its x2 argument is ignored.

-- Keep this migration self-contained for both production and isolated CI.
create schema if not exists private;

create or replace function private.is_active_profile()
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1
    from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.status = 'active'
  );
$$;

-- Legacy score view from the former x2 implementation. Current scoring is
-- provided by v_match_prediction_points below.
drop view if exists public.v_predictions_score;

-- ---------------------------------------------------------------------------
-- Private profile photos
-- ---------------------------------------------------------------------------

update storage.buckets
set public = false
where id = 'profile-photos';

drop policy if exists profile_photos_active_read on storage.objects;
create policy profile_photos_active_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'profile-photos'
  and private.is_active_profile()
);

-- ---------------------------------------------------------------------------
-- Predictions without x2
-- ---------------------------------------------------------------------------

drop trigger if exists trg_enforce_match_prediction_x2
on public.match_predictions;

drop function if exists public.enforce_match_prediction_x2();

create or replace function public.guard_match_prediction_window()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_kickoff timestamptz;
  v_match_status text;
  v_closed_at timestamptz;
begin
  if (select auth.uid()) is not null and pg_trigger_depth() <= 1 then
    if tg_op = 'UPDATE' and new.match_id is distinct from old.match_id then
      raise exception 'Le match d’un pronostic ne peut pas être modifié.'
        using errcode = '22023';
    end if;
    new.profile_id := (select auth.uid());
  end if;

  -- Empty pre-created rows remain allowed. The time window is enforced as
  -- soon as the user fills an actual prediction.
  if new.is_filled then
    select m.kickoff_at, m.status, m.predictions_closed_at
    into v_kickoff, v_match_status, v_closed_at
    from public.matches m
    where m.id = new.match_id;

    if v_kickoff is null
       or v_match_status <> 'a_venir'
       or now() < v_kickoff - interval '6 days'
       or now() >= v_kickoff - interval '5 minutes'
       or (v_closed_at is not null and now() >= v_closed_at) then
      raise exception 'Pronostic fermé' using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.seed_match_predictions()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.opponent_id is null then
    return new;
  end if;

  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled
  )
  select new.id, p.id, 0, 0, false
  from public.profiles p
  where p.status = 'active'
  on conflict (match_id, profile_id) do nothing;

  return new;
end;
$$;

create or replace function public.seed_predictions_for_active_profile()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.status <> 'active' then
    return new;
  end if;

  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled
  )
  select m.id, new.id, 0, 0, false
  from public.matches m
  where m.status = 'a_venir'
  on conflict (match_id, profile_id) do nothing;

  insert into public.season_predictions (
    season_id,
    predictor_profile_id,
    season_player_id,
    category,
    predicted_value_30,
    is_filled
  )
  select
    sp.season_id,
    new.id,
    sp.id,
    case when sp.is_goalkeeper then 'clean_sheets' else 'buts' end,
    0,
    false
  from public.season_players sp
  join public.seasons s
    on s.id = sp.season_id
   and s.status = 'open'
  where sp.is_active
  on conflict (
    season_id,
    predictor_profile_id,
    season_player_id,
    category
  ) do nothing;

  return new;
end;
$$;

-- Replace the score view before dropping the old column so no dependent
-- business calculation can still apply the x2 multiplier.
create or replace view public.v_match_prediction_points
with (security_invoker = true)
as
select
  mp.id,
  mp.match_id,
  mp.profile_id,
  case
    when not mp.is_filled then 0::numeric
    when sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
       <> sign((m.score_as_grinta - m.score_adverse)::numeric)
      then 0::numeric
    else
      case
        when m.score_as_grinta > m.score_adverse
          then mo.odds_victoire_as_grinta
        when m.score_as_grinta = m.score_adverse
          then mo.odds_nul
        else mo.odds_victoire_adverse
      end
      * case
          when mp.predicted_score_as_grinta = m.score_as_grinta
           and mp.predicted_score_adverse = m.score_adverse
            then 2::numeric
          when mp.predicted_score_as_grinta - mp.predicted_score_adverse
             = m.score_as_grinta - m.score_adverse
            then 1.5::numeric
          when mp.predicted_score_as_grinta = m.score_as_grinta
            or mp.predicted_score_adverse = m.score_adverse
            then 1.5::numeric
          else 1::numeric
        end
  end as points
from public.match_predictions mp
join public.matches m
  on m.id = mp.match_id
 and m.status in ('termine', 'archive')
join public.match_odds mo
  on mo.match_id = m.id;

revoke all on public.v_match_prediction_points from anon, authenticated;
grant select on public.v_match_prediction_points to authenticated;

drop view if exists public.v_x2_wallet;

-- Existing historical selections no longer have any effect from this point.
update public.match_predictions
set use_x2 = false
where use_x2;

-- The new RPC used by the application.
drop function if exists public.save_match_prediction(uuid, integer, integer, boolean);

create or replace function public.save_match_prediction(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_match public.matches%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Utilisateur non authentifié.' using errcode = '42501';
  end if;
  if not private.is_active_profile() then
    raise exception 'Compte inactif.' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match requis.' using errcode = '22023';
  end if;
  if p_score_as_grinta is null or p_score_adverse is null
     or p_score_as_grinta not between 0 and 99
     or p_score_adverse not between 0 and 99 then
    raise exception 'Les scores doivent être compris entre 0 et 99.'
      using errcode = '22023';
  end if;

  select *
  into v_match
  from public.matches
  where id = p_match_id
  for share;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  if v_match.kickoff_at is null
     or v_match.status <> 'a_venir'
     or now() < v_match.kickoff_at - interval '6 days'
     or now() >= v_match.kickoff_at - interval '5 minutes'
     or (
       v_match.predictions_closed_at is not null
       and now() >= v_match.predictions_closed_at
     ) then
    raise exception 'Ce match n’est pas ouvert aux pronostics.'
      using errcode = '22023';
  end if;

  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled,
    updated_at
  ) values (
    p_match_id,
    v_actor_id,
    p_score_as_grinta,
    p_score_adverse,
    true,
    now()
  )
  on conflict (match_id, profile_id) do update
  set predicted_score_as_grinta = excluded.predicted_score_as_grinta,
      predicted_score_adverse = excluded.predicted_score_adverse,
      is_filled = true,
      updated_at = now();

  return true;
end;
$$;

-- Compatibility for a stale client that still sends p_use_x2. The argument is
-- deliberately ignored and cannot influence points.
create or replace function public.save_match_prediction(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_use_x2 boolean
)
returns boolean
language sql
set search_path to ''
as $$
  select public.save_match_prediction(
    p_match_id,
    p_score_as_grinta,
    p_score_adverse
  );
$$;

revoke all on function public.save_match_prediction(uuid, integer, integer)
from public, anon;
revoke all on function public.save_match_prediction(uuid, integer, integer, boolean)
from public, anon;
grant execute on function public.save_match_prediction(uuid, integer, integer)
to authenticated;
grant execute on function public.save_match_prediction(uuid, integer, integer, boolean)
to authenticated;

alter table public.match_predictions
drop column if exists use_x2;
