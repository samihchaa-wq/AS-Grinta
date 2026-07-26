-- Ouvre chaque pronostic de match pendant les six jours qui précèdent le
-- coup d'envoi. Plusieurs matchs peuvent donc être pronostiqués en parallèle.
-- La fermeture à H-5 et la fermeture manuelle restent prioritaires.

drop policy if exists match_predictions_owner_insert
  on public.match_predictions;
create policy match_predictions_owner_insert
on public.match_predictions
for insert
to authenticated
with check (
  profile_id = (select auth.uid())
  and (select private.is_active_profile())
  and (
    not is_filled
    or exists (
      select 1
      from public.matches m
      where m.id = match_id
        and m.status = 'a_venir'
        and m.kickoff_at is not null
        and now() >= m.kickoff_at - interval '6 days'
        and now() < m.kickoff_at - interval '5 minutes'
        and (
          m.predictions_closed_at is null
          or now() < m.predictions_closed_at
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
using (profile_id = (select auth.uid()))
with check (
  profile_id = (select auth.uid())
  and (select private.is_active_profile())
  and (
    not is_filled
    or exists (
      select 1
      from public.matches m
      where m.id = match_id
        and m.status = 'a_venir'
        and m.kickoff_at is not null
        and now() >= m.kickoff_at - interval '6 days'
        and now() < m.kickoff_at - interval '5 minutes'
        and (
          m.predictions_closed_at is null
          or now() < m.predictions_closed_at
        )
    )
  )
);

create or replace function public.guard_match_prediction_window()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
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

  -- Les lignes vides précréées à l’ajout d’un match restent autorisées. Les
  -- contraintes temporelles s’appliquent dès qu’un vrai pronostic ou un x2 est
  -- enregistré.
  if new.is_filled or new.use_x2 then
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
$function$;

revoke execute on function public.guard_match_prediction_window()
  from public, anon, authenticated;

create or replace function public.enforce_match_prediction_x2()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match public.matches%rowtype;
  v_actor_id uuid;
  v_earned integer;
  v_spent integer;
begin
  v_actor_id := coalesce((select auth.uid()), new.profile_id);
  if v_actor_id is null then
    raise exception 'Utilisateur non authentifié.' using errcode = '42501';
  end if;
  new.profile_id := v_actor_id;

  if tg_op = 'INSERT' and not coalesce(new.use_x2, false) then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.use_x2 is not distinct from old.use_x2 then
    return new;
  end if;

  select * into v_match
  from public.matches
  where id = new.match_id;

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
    raise exception
      'Le bonus x2 ne peut être modifié que tant que le pronostic est ouvert.'
      using errcode = '22023';
  end if;

  if new.use_x2 then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_actor_id::text, 0)
    );

    select count(*)::integer into v_earned
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id
    where mp.profile_id = v_actor_id
      and mp.is_filled
      and m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
      and mp.predicted_score_as_grinta = m.score_as_grinta
      and mp.predicted_score_adverse = m.score_adverse;

    select count(*)::integer into v_spent
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
$function$;

revoke execute on function public.enforce_match_prediction_x2()
  from public, anon, authenticated;

create or replace function public.save_match_prediction(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_use_x2 boolean default false
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor_id::text, 0)
  );

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
    use_x2,
    updated_at
  ) values (
    p_match_id,
    v_actor_id,
    p_score_as_grinta,
    p_score_adverse,
    true,
    coalesce(p_use_x2, false),
    now()
  )
  on conflict (match_id, profile_id) do update
  set predicted_score_as_grinta = excluded.predicted_score_as_grinta,
      predicted_score_adverse = excluded.predicted_score_adverse,
      is_filled = true,
      use_x2 = excluded.use_x2,
      updated_at = now();

  return true;
end;
$function$;

revoke execute on function public.save_match_prediction(
  uuid, integer, integer, boolean
) from public, anon;
grant execute on function public.save_match_prediction(
  uuid, integer, integer, boolean
) to authenticated, service_role;
