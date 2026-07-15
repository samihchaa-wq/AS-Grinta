-- Valeurs de stats courantes d'une personne, pour les barres de progression
-- de l'armoire à badges (« en cours »). Lecture seule (membres connectés).
create or replace function public.profile_badge_metrics(p_profile_id uuid)
returns table(
  goals integer,
  appearances integer,
  clean_sheets integer,
  mvp integer,
  exact_scores integer,
  good_bets integer
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  return query
  with sp as (
    select id from public.season_players where profile_id = p_profile_id
  ), mps as (
    select s.match_id, s.goals as g, s.clean_sheet as cs
    from public.match_player_stats s
    join sp on sp.id = s.season_player_id
    join public.matches m on m.id = s.match_id and m.status in ('termine','archive')
  ), mvpm as (
    select v.match_id
    from public.match_man_of_match v
    join sp on sp.id = v.season_player_id
    join public.matches m on m.id = v.match_id and m.status in ('termine','archive')
  ), apps as (
    select distinct match_id from (
      select ma.match_id
      from public.match_attendance ma
      join sp on sp.id = ma.season_player_id
      join public.matches m on m.id = ma.match_id and m.status in ('termine','archive')
      union select match_id from mps
      union select match_id from mvpm
    ) u
  )
  select
    coalesce((select sum(mps.g) from mps), 0)::integer,
    coalesce((select count(*) from apps), 0)::integer,
    coalesce((select count(*) from mps where mps.cs), 0)::integer,
    coalesce((select count(*) from mvpm), 0)::integer,
    coalesce((select sum(f.exact) from public.v_match_prediction_flags f where f.profile_id = p_profile_id), 0)::integer,
    coalesce((select sum(f.bon_pari) from public.v_match_prediction_flags f where f.profile_id = p_profile_id), 0)::integer;
end;
$function$;

grant execute on function public.profile_badge_metrics(uuid) to authenticated;
