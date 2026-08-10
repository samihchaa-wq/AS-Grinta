-- Passe 2 : une source temporelle serveur, règle du premier match côté base,
-- soumission de pronostic et mise à jour match+cotes atomiques.

alter table public.matches
  add column if not exists kickoff_at timestamptz;

comment on column public.matches.kickoff_at is
  'Instant absolu du coup d’envoi, dérivé de match_date/match_time en Europe/Paris.';

update public.matches
set kickoff_at = case
  when match_time is null then null
  else (match_date + match_time) at time zone 'Europe/Paris'
end
where kickoff_at is distinct from case
  when match_time is null then null
  else (match_date + match_time) at time zone 'Europe/Paris'
end;

create or replace function public.sync_match_kickoff_at()
returns trigger
language plpgsql
security invoker
set search_path to ''
as $function$
begin
  new.kickoff_at := case
    when new.match_time is null then null
    else (new.match_date + new.match_time) at time zone 'Europe/Paris'
  end;
  return new;
end;
$function$;

revoke execute on function public.sync_match_kickoff_at()
  from public, anon, authenticated;

drop trigger if exists trg_sync_match_kickoff_at on public.matches;
create trigger trg_sync_match_kickoff_at
before insert or update of match_date, match_time, kickoff_at
on public.matches
for each row execute function public.sync_match_kickoff_at();

create index if not exists matches_upcoming_kickoff_idx
  on public.matches (kickoff_at, id)
  where status = 'a_venir';

-- Défense en profondeur : les écritures directes restent compatibles avec une
-- ancienne version de l’app, mais une ligne remplie doit viser le premier match
-- global dont la fenêtre de pronostic est encore ouverte.
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
    or match_id = (
      select m.id
      from public.matches m
      where m.status = 'a_venir'
        and m.kickoff_at is not null
        and now() < m.kickoff_at - interval '5 minutes'
        and (
          m.predictions_closed_at is null
          or now() < m.predictions_closed_at
        )
      order by m.kickoff_at, m.id
      limit 1
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
    or match_id = (
      select m.id
      from public.matches m
      where m.status = 'a_venir'
        and m.kickoff_at is not null
        and now() < m.kickoff_at - interval '5 minutes'
        and (
          m.predictions_closed_at is null
          or now() < m.predictions_closed_at
        )
      order by m.kickoff_at, m.id
      limit 1
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
  v_first_open_match_id uuid;
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
       or now() >= v_kickoff - interval '5 minutes'
       or (v_closed_at is not null and now() >= v_closed_at) then
      raise exception 'Pronostic fermé' using errcode = '22023';
    end if;

    select m.id
    into v_first_open_match_id
    from public.matches m
    where m.status = 'a_venir'
      and m.kickoff_at is not null
      and now() < m.kickoff_at - interval '5 minutes'
      and (
        m.predictions_closed_at is null
        or now() < m.predictions_closed_at
      )
    order by m.kickoff_at, m.id
    limit 1;

    if v_first_open_match_id is distinct from new.match_id then
      raise exception
        'Ce match n’est pas encore ouvert aux pronostics.'
        using errcode = '22023';
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

  if tg_op = 'UPDATE' and new.use_x2 = old.use_x2 then
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

  if new.use_x2 and (tg_op = 'INSERT' or not old.use_x2) then
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

-- Point d’entrée unique utilisé par Flutter. La sélection du premier match,
-- l’upsert et le contrôle concurrent du portefeuille x2 partagent la même
-- transaction PostgreSQL.
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
  v_first_open_match_id uuid;
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

  select m.id
  into v_first_open_match_id
  from public.matches m
  where m.status = 'a_venir'
    and m.kickoff_at is not null
    and now() < m.kickoff_at - interval '5 minutes'
    and (
      m.predictions_closed_at is null
      or now() < m.predictions_closed_at
    )
  order by m.kickoff_at, m.id
  limit 1
  for share;

  if v_first_open_match_id is null then
    raise exception 'Aucun match n’est ouvert aux pronostics.'
      using errcode = 'P0002';
  end if;
  if v_first_open_match_id <> p_match_id then
    raise exception
      'Ce match n’est pas encore ouvert aux pronostics.'
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

-- L’édition du match et de ses cotes ne peut plus laisser un demi-état si une
-- des deux écritures échoue.
create or replace function public.update_match_with_odds(
  p_match_id uuid,
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_status text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null or p_season_id is null or p_opponent_id is null
     or p_match_date is null or p_match_time is null then
    raise exception 'Match, saison, adversaire, date et heure requis.'
      using errcode = '22023';
  end if;
  if p_location not in ('domicile', 'exterieur') then
    raise exception 'Lieu invalide.' using errcode = '22023';
  end if;
  if p_status not in ('a_venir', 'termine', 'archive') then
    raise exception 'Statut invalide.' using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Date de match hors limites.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.seasons s where s.id = p_season_id) then
    raise exception 'Saison introuvable.' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.opponents o where o.id = p_opponent_id) then
    raise exception 'Adversaire introuvable.' using errcode = 'P0002';
  end if;
  if p_status = 'a_venir' and (
    p_win is null or p_draw is null or p_loss is null
    or p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
    or p_win > 100 or p_draw > 100 or p_loss > 100
  ) then
    raise exception 'Cotes invalides.' using errcode = '22023';
  end if;

  select m.id into v_match_id
  from public.matches m
  where m.id = p_match_id
  for update;

  if v_match_id is null then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  update public.matches
  set season_id = p_season_id,
      opponent_id = p_opponent_id,
      match_date = p_match_date,
      match_time = p_match_time,
      location = p_location,
      status = p_status,
      updated_at = now()
  where id = p_match_id;

  if p_status = 'a_venir' then
    insert into public.match_odds (
      match_id,
      odds_victoire_as_grinta,
      odds_nul,
      odds_victoire_adverse,
      computed_at
    ) values (
      p_match_id,
      round(p_win, 2),
      round(p_draw, 2),
      round(p_loss, 2),
      now()
    )
    on conflict (match_id) do update
    set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
        odds_nul = excluded.odds_nul,
        odds_victoire_adverse = excluded.odds_victoire_adverse,
        computed_at = now();
  end if;

  return true;
end;
$function$;

revoke execute on function public.update_match_with_odds(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric
) from public, anon;
grant execute on function public.update_match_with_odds(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric
) to authenticated, service_role;

-- Le cron de rappel utilise désormais le même instant que les politiques et les
-- triggers de fermeture.
create or replace function public.push_closing_reminders()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match record;
  v_sent integer := 0;
begin
  for v_match in
    select m.id
    from public.matches m
    where m.status = 'a_venir'
      and m.kickoff_at is not null
      and now() >= m.kickoff_at - interval '2 hours'
      and now() < m.kickoff_at - interval '5 minutes'
      and (
        m.predictions_closed_at is null
        or now() < m.predictions_closed_at
      )
  loop
    insert into public.push_notification_log (match_id, kind)
    values (v_match.id, 'closing_soon')
    on conflict do nothing;
    if found then
      perform public.internal_push_notify('closing_soon', v_match.id);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$function$;

-- Assertions sans identifiant ni donnée métier codés en dur.
do $security_assertions$
declare
  v_bad_count integer;
begin
  select count(*) into v_bad_count
  from public.matches m
  where m.match_time is not null
    and m.kickoff_at is distinct from
      ((m.match_date + m.match_time) at time zone 'Europe/Paris');
  if v_bad_count <> 0 then
    raise exception 'kickoff_at mismatch for % match(es)', v_bad_count;
  end if;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.matches'::regclass
      and t.tgname = 'trg_sync_match_kickoff_at'
      and not t.tgisinternal
  ) then
    raise exception 'kickoff synchronization trigger is missing';
  end if;

  if has_function_privilege(
       'anon',
       'public.save_match_prediction(uuid,integer,integer,boolean)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.update_match_with_odds(uuid,uuid,uuid,date,time without time zone,text,text,numeric,numeric,numeric)',
       'EXECUTE'
     ) then
    raise exception 'anonymous EXECUTE remains on an atomic application RPC';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.save_match_prediction(uuid,integer,integer,boolean)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.update_match_with_odds(uuid,uuid,uuid,date,time without time zone,text,text,numeric,numeric,numeric)',
       'EXECUTE'
     ) then
    raise exception 'authenticated EXECUTE missing on an atomic application RPC';
  end if;

  if has_function_privilege(
       'authenticated', 'public.sync_match_kickoff_at()', 'EXECUTE'
     )
     or has_function_privilege(
       'authenticated', 'public.guard_match_prediction_window()', 'EXECUTE'
     )
     or has_function_privilege(
       'authenticated', 'public.enforce_match_prediction_x2()', 'EXECUTE'
     ) then
    raise exception 'a trigger function remains directly executable';
  end if;
end;
$security_assertions$;
