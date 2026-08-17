create or replace function public.save_match_prediction(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer
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
    raise exception 'Les scores doivent être compris entre 0 et 99.' using errcode = '22023';
  end if;

  select * into v_match
  from public.matches
  where id = p_match_id
  for share;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  if v_match.kickoff_at is null
     or v_match.status <> 'a_venir'
     or now() < private.match_features_open_at(v_match.kickoff_at)
     or now() >= private.match_prediction_closes_at(v_match.kickoff_at)
     or (v_match.predictions_closed_at is not null and now() >= v_match.predictions_closed_at) then
    raise exception 'Ce match n’est pas ouvert aux pronostics.' using errcode = '22023';
  end if;

  insert into public.match_predictions as existing (
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
      updated_at = now()
  where (
    existing.predicted_score_as_grinta,
    existing.predicted_score_adverse,
    existing.is_filled
  ) is distinct from (
    excluded.predicted_score_as_grinta,
    excluded.predicted_score_adverse,
    true
  );

  return true;
end;
$function$;
