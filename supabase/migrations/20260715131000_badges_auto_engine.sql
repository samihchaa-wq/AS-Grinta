-- Moteur d'attribution automatique des badges.
-- Les badges auto sont recalculés à la source (résultat validé, présence, but,
-- pronostic). Le moteur fait autorité pour les badges `auto` : il les ajoute
-- quand le seuil est atteint et les retire s'ils ne le sont plus (correction).
-- Les badges manuels ne sont jamais touchés.

create or replace function public.recalculate_profile_badges(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_goals integer := 0;
  v_cs integer := 0;
  v_apps integer := 0;
  v_maxmatch integer := 0;
  v_preds integer := 0;
  v_exacts integer := 0;
  v_bets integer := 0;
  b record;
  v_earned boolean;
begin
  if p_profile_id is null then
    return;
  end if;

  -- Stats joueur : via les entrées d'effectif liées à ce profil, sur les
  -- matchs terminés/archivés.
  with sp as (
    select id from public.season_players where profile_id = p_profile_id
  ), mps as (
    select s.match_id, s.goals, s.clean_sheet, s.played
    from public.match_player_stats s
    join sp on sp.id = s.season_player_id
    join public.matches m on m.id = s.match_id
      and m.status in ('termine', 'archive')
  )
  select
    coalesce(sum(goals), 0),
    coalesce(count(*) filter (where clean_sheet), 0),
    coalesce(count(distinct match_id) filter (where played), 0),
    coalesce(max(goals), 0)
  into v_goals, v_cs, v_apps, v_maxmatch
  from mps;

  -- Stats pronostiqueur.
  select coalesce(count(*) filter (where is_filled), 0)
  into v_preds
  from public.match_predictions where profile_id = p_profile_id;

  select coalesce(sum(bon_pari), 0), coalesce(sum(exact), 0)
  into v_bets, v_exacts
  from public.v_match_prediction_flags where profile_id = p_profile_id;

  for b in select id, metric, threshold from public.badges where auto loop
    v_earned := case b.metric
      when 'goals'        then v_goals >= b.threshold
      when 'clean_sheets' then v_cs >= b.threshold
      when 'appearances'  then v_apps >= b.threshold
      when 'match_goals'  then v_maxmatch >= b.threshold
      when 'predictions'  then v_preds >= b.threshold
      when 'exact_scores' then v_exacts >= b.threshold
      when 'good_bets'    then v_bets >= b.threshold
      else false
    end;

    if v_earned then
      insert into public.profile_badges(profile_id, badge_id, source)
      values (p_profile_id, b.id, 'auto')
      on conflict (profile_id, badge_id) do nothing;
    else
      delete from public.profile_badges
      where profile_id = p_profile_id and badge_id = b.id and source = 'auto';
    end if;
  end loop;
end;
$function$;

create or replace function public.recalculate_all_badges()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r record;
begin
  for r in select id from public.profiles where status = 'active' loop
    perform public.recalculate_profile_badges(r.id);
  end loop;
end;
$function$;

-- Déclencheur : édition des stats joueur (buts/clean sheet/présence).
create or replace function public.trg_badges_on_player_stats()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_profile uuid;
begin
  select sp.profile_id into v_profile
  from public.season_players sp
  where sp.id = coalesce(new.season_player_id, old.season_player_id);
  if v_profile is not null then
    perform public.recalculate_profile_badges(v_profile);
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_badges_player_stats on public.match_player_stats;
create trigger trg_badges_player_stats
  after insert or update or delete on public.match_player_stats
  for each row execute function public.trg_badges_on_player_stats();

-- Déclencheur : un pronostic rempli/modifié (badge « Premier prono »…).
create or replace function public.trg_badges_on_prediction()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform public.recalculate_profile_badges(new.profile_id);
  return null;
end;
$function$;

drop trigger if exists trg_badges_prediction on public.match_predictions;
create trigger trg_badges_prediction
  after insert or update on public.match_predictions
  for each row execute function public.trg_badges_on_prediction();

-- Déclencheur : un résultat validé change les exacts/bons paris de TOUS les
-- pronostiqueurs de ce match -> recalcul global (échelle club, peu coûteux).
create or replace function public.trg_badges_on_match_result()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.status in ('termine', 'archive')
     and (tg_op = 'INSERT' or new.status is distinct from old.status
          or new.score_as_grinta is distinct from old.score_as_grinta
          or new.score_adverse is distinct from old.score_adverse) then
    perform public.recalculate_all_badges();
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_badges_match_result on public.matches;
create trigger trg_badges_match_result
  after insert or update on public.matches
  for each row execute function public.trg_badges_on_match_result();

-- Backfill initial.
select public.recalculate_all_badges();
