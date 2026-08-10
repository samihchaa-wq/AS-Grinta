-- Fix x2 validation timezone, profile spoofing and concurrent spending.

create or replace function public.enforce_match_prediction_x2()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match public.matches%rowtype;
  v_actor_id uuid;
  v_kickoff timestamptz;
  v_earned integer;
  v_spent integer;
begin
  -- Client requests must always consume the signed-in user's wallet, regardless
  -- of the profile_id supplied in the payload or trigger execution order.
  v_actor_id := coalesce((select auth.uid()), new.profile_id);
  if v_actor_id is null then
    raise exception 'Utilisateur non authentifié.' using errcode = '42501';
  end if;
  new.profile_id := v_actor_id;

  if tg_op = 'UPDATE' and new.use_x2 = old.use_x2 then
    return new;
  end if;

  select *
  into v_match
  from public.matches
  where id = new.match_id;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  v_kickoff := (
    v_match.match_date + coalesce(v_match.match_time, time '00:00')
  ) at time zone 'Europe/Paris';

  if v_match.status <> 'a_venir'
     or now() >= v_kickoff - interval '5 minutes'
     or (
       v_match.predictions_closed_at is not null
       and now() >= v_match.predictions_closed_at
     ) then
    raise exception
      'Le bonus x2 ne peut être modifié que tant que le pronostic est ouvert.'
      using errcode = '22023';
  end if;

  if new.use_x2 and (tg_op = 'INSERT' or not old.use_x2) then
    -- Serialize wallet consumption for the same profile so two concurrent
    -- requests cannot spend the same available token.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_actor_id::text, 0)
    );

    select count(*)::integer
    into v_earned
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id
    where mp.profile_id = v_actor_id
      and mp.is_filled
      and m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
      and mp.predicted_score_as_grinta = m.score_as_grinta
      and mp.predicted_score_adverse = m.score_adverse;

    select count(*)::integer
    into v_spent
    from public.match_predictions mp
    where mp.profile_id = v_actor_id
      and mp.use_x2
      and (tg_op <> 'UPDATE' or mp.id <> old.id);

    if coalesce(v_earned, 0) - coalesce(v_spent, 0) < 1 then
      raise exception 'Aucun bonus x2 disponible.' using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.enforce_match_prediction_x2()
  from public, anon, authenticated;
grant execute on function public.enforce_match_prediction_x2()
  to service_role;
