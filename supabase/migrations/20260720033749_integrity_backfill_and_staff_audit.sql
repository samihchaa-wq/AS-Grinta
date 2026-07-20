-- Passe 3 : réparer les préremplissages historiques et rendre les dérives
-- fonctionnelles visibles sans exposer de données métier aux rôles anonymes.

-- Le trigger x2 ne doit intervenir que lorsque la valeur use_x2 change. Une
-- ligne vide créée par les triggers de préremplissage n'utilise aucun jeton et
-- doit rester insérable même si le match attend déjà son résultat.
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

-- Préremplissage lors de la création d'un match. La fonction reste idempotente
-- grâce à la contrainte unique (match_id, profile_id).
create or replace function public.seed_match_predictions()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled,
    use_x2
  )
  select new.id, p.id, 0, 0, false, false
  from public.profiles p
  where p.status = 'active'
  on conflict (match_id, profile_id) do nothing;

  return new;
end;
$function$;

revoke execute on function public.seed_match_predictions()
  from public, anon, authenticated;

-- Préremplissage lors de l'activation d'un profil. Les pronostics de saison
-- sont inclus afin que les deux familles de pronostics aient la même garantie.
create or replace function public.seed_predictions_for_active_profile()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.status <> 'active' then
    return new;
  end if;

  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled,
    use_x2
  )
  select m.id, new.id, 0, 0, false, false
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
$function$;

revoke execute on function public.seed_predictions_for_active_profile()
  from public, anon, authenticated;

-- Réparation idempotente des combinaisons historiques manquantes. Les lignes
-- déjà remplies ou existantes ne sont jamais modifiées.
insert into public.match_predictions (
  match_id,
  profile_id,
  predicted_score_as_grinta,
  predicted_score_adverse,
  is_filled,
  use_x2
)
select m.id, p.id, 0, 0, false, false
from public.matches m
cross join public.profiles p
left join public.match_predictions mp
  on mp.match_id = m.id
 and mp.profile_id = p.id
where m.status = 'a_venir'
  and p.status = 'active'
  and mp.id is null
on conflict (match_id, profile_id) do nothing;

-- Rapport opérationnel réservé au staff. Il ne retourne que des compteurs et
-- aucun identifiant, nom, score individuel ou autre donnée personnelle.
create or replace function public.staff_app_integrity_report()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_checks jsonb;
  v_total bigint;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  with checks as (
    select 'matches_without_odds'::text as check_name, count(*)::bigint as issue_count
    from public.matches m
    left join public.match_odds mo on mo.match_id = m.id
    where mo.match_id is null

    union all

    select 'finished_without_scores', count(*)::bigint
    from public.matches
    where status in ('termine', 'archive')
      and (score_as_grinta is null or score_adverse is null)

    union all

    select 'upcoming_with_scores', count(*)::bigint
    from public.matches
    where status = 'a_venir'
      and (score_as_grinta is not null or score_adverse is not null)

    union all

    select 'duplicate_match_datetime', count(*)::bigint
    from (
      select match_date, match_time
      from public.matches
      group by match_date, match_time
      having count(*) > 1
    ) duplicates

    union all

    select 'multiple_open_seasons', greatest(count(*) - 1, 0)::bigint
    from public.seasons
    where status = 'open'

    union all

    select 'orphan_match_predictions', count(*)::bigint
    from public.match_predictions mp
    left join public.matches m on m.id = mp.match_id
    left join public.profiles p on p.id = mp.profile_id
    where m.id is null or p.id is null

    union all

    select 'filled_predictions_missing_scores', count(*)::bigint
    from public.match_predictions
    where is_filled
      and (
        predicted_score_as_grinta is null
        or predicted_score_adverse is null
      )

    union all

    select 'missing_upcoming_prediction_seeds', count(*)::bigint
    from public.matches m
    cross join public.profiles p
    left join public.match_predictions mp
      on mp.match_id = m.id
     and mp.profile_id = p.id
    where m.status = 'a_venir'
      and p.status = 'active'
      and mp.id is null

    union all

    select 'missing_open_season_prediction_seeds', count(*)::bigint
    from public.seasons s
    join public.season_players sp
      on sp.season_id = s.id
     and sp.is_active
    cross join public.profiles p
    left join public.season_predictions prediction
      on prediction.season_id = s.id
     and prediction.predictor_profile_id = p.id
     and prediction.season_player_id = sp.id
     and prediction.category = case
       when sp.is_goalkeeper then 'clean_sheets'
       else 'buts'
     end
    where s.status = 'open'
      and p.status = 'active'
      and prediction.id is null

    union all

    select 'kickoff_mismatch', count(*)::bigint
    from public.matches m
    where m.match_time is not null
      and m.kickoff_at is distinct from
        ((m.match_date + m.match_time) at time zone 'Europe/Paris')
  ), aggregated as (
    select
      coalesce(sum(issue_count), 0)::bigint as total_issues,
      jsonb_agg(
        jsonb_build_object(
          'check', check_name,
          'issues', issue_count
        )
        order by check_name
      ) as checks
    from checks
  )
  select total_issues, checks
  into v_total, v_checks
  from aggregated;

  return jsonb_build_object(
    'healthy', v_total = 0,
    'total_issues', v_total,
    'checked_at', now(),
    'checks', coalesce(v_checks, '[]'::jsonb)
  );
end;
$function$;

revoke execute on function public.staff_app_integrity_report()
  from public, anon;
grant execute on function public.staff_app_integrity_report()
  to authenticated, service_role;

-- Assertions de fin de migration : la réparation doit produire un état sain et
-- les fonctions internes ne doivent pas devenir des RPC publiques.
do $integrity_assertions$
declare
  v_missing_match_seeds integer;
  v_missing_season_seeds integer;
begin
  select count(*)::integer
  into v_missing_match_seeds
  from public.matches m
  cross join public.profiles p
  left join public.match_predictions mp
    on mp.match_id = m.id
   and mp.profile_id = p.id
  where m.status = 'a_venir'
    and p.status = 'active'
    and mp.id is null;

  if v_missing_match_seeds <> 0 then
    raise exception
      'missing upcoming match prediction seeds after backfill: %',
      v_missing_match_seeds;
  end if;

  select count(*)::integer
  into v_missing_season_seeds
  from public.seasons s
  join public.season_players sp
    on sp.season_id = s.id
   and sp.is_active
  cross join public.profiles p
  left join public.season_predictions prediction
    on prediction.season_id = s.id
   and prediction.predictor_profile_id = p.id
   and prediction.season_player_id = sp.id
   and prediction.category = case
     when sp.is_goalkeeper then 'clean_sheets'
     else 'buts'
   end
  where s.status = 'open'
    and p.status = 'active'
    and prediction.id is null;

  if v_missing_season_seeds <> 0 then
    raise exception
      'missing open season prediction seeds: %',
      v_missing_season_seeds;
  end if;

  if has_function_privilege(
       'anon', 'public.staff_app_integrity_report()', 'EXECUTE'
     ) then
    raise exception 'anonymous access remains on staff integrity report';
  end if;

  if not has_function_privilege(
       'authenticated', 'public.staff_app_integrity_report()', 'EXECUTE'
     ) then
    raise exception 'authenticated access missing on staff integrity report';
  end if;

  if has_function_privilege(
       'authenticated', 'public.seed_match_predictions()', 'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.seed_predictions_for_active_profile()',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated', 'public.enforce_match_prediction_x2()', 'EXECUTE'
     ) then
    raise exception 'a trigger function remains directly executable';
  end if;
end;
$integrity_assertions$;
