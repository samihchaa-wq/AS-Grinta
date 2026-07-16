-- Rattacher l'historique importé à un compte PAR IDENTIFIANT (plus par nom).
-- Une fois la ligne d'historique assignée à un compte, « lier le compte »
-- suffit : le nom n'a plus d'importance. Repli sur le nom tant qu'aucune
-- assignation n'existe (rien ne casse pour l'existant).

alter table public.historical_player_statistics
  add column if not exists profile_id uuid references public.profiles(id) on delete set null;

create index if not exists idx_hps_profile_id
  on public.historical_player_statistics(profile_id);

-- Rattachement automatique des historiques dont le nom correspond déjà à un
-- compte lié à l'effectif (rend le lien durable, indépendant du nom ensuite).
update public.historical_player_statistics h
set profile_id = m.profile_id, updated_at = now()
from (
  select fname, min(profile_id::text)::uuid as profile_id
  from (
    select distinct sp.profile_id,
           lower(btrim(concat_ws(' ', sp.first_name, nullif(sp.last_name, '')))) as fname
    from public.season_players sp
    where sp.profile_id is not null
      and coalesce(btrim(sp.first_name), '') <> ''
  ) x
  group by fname
  having count(distinct profile_id) = 1
) m
where h.profile_id is null
  and lower(btrim(h.player_name)) = m.fname;

-- Le moteur de badges : métriques carrière = historique (par profile_id, ou
-- par nom si non encore assigné) + matchs de l'appli.
create or replace function public.profile_badge_metrics(p_profile_id uuid)
returns table(
  matches_played_season integer, wins_season integer, goals_season integer,
  clean_sheets_season integer, matches_played integer, wins integer,
  goals integer, doubles integer, max_match_goals integer, mvp integer,
  clean_sheets integer, pred_good_result integer, pred_exact_score integer,
  seasons_complete integer, title_most_present integer, title_top_scorer integer,
  title_mvp_king integer, title_best_winrate integer, title_best_pred_player integer,
  title_best_pred_match integer, title_best_pred_overall integer
)
language sql
security definer
set search_path to 'public'
as $function$
  with pm as (
    select m.season_id,
           (m.score_as_grinta > m.score_adverse) as win,
           coalesce(st.goals, 0) as g,
           coalesce(st.clean_sheet, false) as cs,
           (mv.season_player_id is not null) as is_mvp
    from public.season_players sp
    join public.matches m
      on m.season_id = sp.season_id and m.status in ('termine', 'archive')
    left join public.match_player_stats st
      on st.season_player_id = sp.id and st.match_id = m.id
    left join public.match_attendance att
      on att.season_player_id = sp.id and att.match_id = m.id
    left join public.match_man_of_match mv
      on mv.season_player_id = sp.id and mv.match_id = m.id
    where sp.profile_id = p_profile_id
      and (st.match_id is not null or att.match_id is not null or mv.match_id is not null)
  ), ps as (
    select season_id,
           count(*) as mp,
           count(*) filter (where win) as w,
           sum(g) as gg,
           count(*) filter (where cs) as csn,
           count(*) filter (where is_mvp) as mvpn,
           count(*) filter (where g = 2) as dbl
    from pm group by season_id
  ), player as (
    select
      coalesce(max(mp), 0)::int as matches_played_season,
      coalesce(max(w), 0)::int as wins_season,
      coalesce(max(gg), 0)::int as goals_season,
      coalesce(max(csn), 0)::int as clean_sheets_season,
      coalesce(sum(mp), 0)::int as matches_played,
      coalesce(sum(w), 0)::int as wins,
      coalesce(sum(gg), 0)::int as goals,
      coalesce(sum(dbl), 0)::int as doubles,
      coalesce(sum(mvpn), 0)::int as mvp,
      coalesce(sum(csn), 0)::int as clean_sheets
    from ps
  ), hist as (
    -- Historique importé rattaché au compte : par profile_id si assigné,
    -- sinon repli sur le nom complet de la fiche effectif.
    select
      coalesce(sum(h.matches_played), 0)::int as h_mp,
      coalesce(sum(h.wins), 0)::int as h_w,
      coalesce(sum(h.goals), 0)::int as h_g,
      coalesce(sum(h.clean_sheets), 0)::int as h_cs,
      coalesce(sum(h.hdm), 0)::int as h_mvp
    from public.historical_player_statistics h
    where h.scope = 'all_time'
      and (
        h.profile_id = p_profile_id
        or (
          h.profile_id is null
          and lower(btrim(h.player_name)) in (
            select distinct lower(btrim(concat_ws(' ', sp.first_name, nullif(sp.last_name, ''))))
            from public.season_players sp
            where sp.profile_id = p_profile_id
              and coalesce(btrim(sp.first_name), '') <> ''
          )
        )
      )
  ), pmax as (
    select coalesce(max(g), 0)::int as max_match_goals from pm
  ), mpred as (
    select
      (mp.is_filled and sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
        = sign((m.score_as_grinta - m.score_adverse)::numeric))::int as bon,
      (mp.is_filled and mp.predicted_score_as_grinta = m.score_as_grinta
        and mp.predicted_score_adverse = m.score_adverse)::int as ex
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id and m.status in ('termine', 'archive')
    where mp.profile_id = p_profile_id
  ), mpred_a as (
    select coalesce(sum(bon), 0)::int as pred_good_result,
           coalesce(sum(ex), 0)::int as pred_exact_score
    from mpred
  ), aw as (
    select
      count(*) filter (where award_type = 'season_complete')::int as seasons_complete,
      count(*) filter (where award_type = 'most_present')::int as title_most_present,
      count(*) filter (where award_type = 'top_scorer')::int as title_top_scorer,
      count(*) filter (where award_type = 'mvp_king')::int as title_mvp_king,
      count(*) filter (where award_type = 'best_winrate')::int as title_best_winrate,
      count(*) filter (where award_type = 'best_pred_player')::int as title_best_pred_player,
      count(*) filter (where award_type = 'best_pred_match')::int as title_best_pred_match,
      count(*) filter (where award_type = 'best_pred_overall')::int as title_best_pred_overall
    from public.season_awards where profile_id = p_profile_id
  )
  select
    player.matches_played_season, player.wins_season, player.goals_season,
    player.clean_sheets_season,
    (player.matches_played + hist.h_mp)::int as matches_played,
    (player.wins + hist.h_w)::int as wins,
    (player.goals + hist.h_g)::int as goals,
    player.doubles, pmax.max_match_goals,
    (player.mvp + hist.h_mvp)::int as mvp,
    (player.clean_sheets + hist.h_cs)::int as clean_sheets,
    mpred_a.pred_good_result, mpred_a.pred_exact_score,
    aw.seasons_complete, aw.title_most_present, aw.title_top_scorer,
    aw.title_mvp_king, aw.title_best_winrate,
    aw.title_best_pred_player, aw.title_best_pred_match, aw.title_best_pred_overall
  from player, hist, pmax, mpred_a, aw;
$function$;

grant execute on function public.profile_badge_metrics(uuid) to authenticated;

-- Liste des joueurs de l'historique (pour le sélecteur admin).
create or replace function public.staff_list_historical_players()
returns table(
  id bigint, player_name text, is_goalkeeper boolean,
  matches_played integer, goals integer, profile_id uuid
)
language sql
stable security definer
set search_path to 'public'
as $function$
  select h.id, h.player_name, h.is_goalkeeper,
         h.matches_played, h.goals, h.profile_id
  from public.historical_player_statistics h
  where h.scope = 'all_time'
    and public.is_match_staff()
  order by lower(btrim(h.player_name));
$function$;

grant execute on function public.staff_list_historical_players() to authenticated;

-- Rattache (ou détache) l'historique d'un joueur à un compte, par identifiant.
create or replace function public.staff_set_historical_profile(
  p_profile_id uuid, p_historical_id bigint
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_name text;
  v jsonb;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_profile_id is null then
    raise exception 'Profile id is required' using errcode = '22023';
  end if;

  -- Détache l'historique actuellement rattaché à ce compte.
  update public.historical_player_statistics
    set profile_id = null, updated_at = now()
    where profile_id = p_profile_id;

  -- Rattache toutes les lignes du joueur choisi (même nom) à ce compte.
  if p_historical_id is not null then
    select player_name into v_name
      from public.historical_player_statistics where id = p_historical_id;
    if v_name is null then
      raise exception 'Historical record not found' using errcode = 'P0002';
    end if;
    update public.historical_player_statistics
      set profile_id = p_profile_id, updated_at = now()
      where lower(btrim(player_name)) = lower(btrim(v_name));
  end if;

  -- Resynchronise les badges de palier automatiques (retire ceux qui ne sont
  -- plus mérités, ajoute les nouveaux).
  select to_jsonb(t) into v from public.profile_badge_metrics(p_profile_id) t;
  delete from public.profile_badges pb
    using public.badges b
    where pb.badge_id = b.id
      and pb.profile_id = p_profile_id
      and pb.source = 'auto'
      and b.kind = 'tier'
      and b.metric is not null
      and coalesce((v ->> b.metric)::int, 0) < b.threshold;
  perform public.recalculate_profile_badges(p_profile_id);
  return true;
end;
$function$;

grant execute on function public.staff_set_historical_profile(uuid, bigint) to authenticated;
