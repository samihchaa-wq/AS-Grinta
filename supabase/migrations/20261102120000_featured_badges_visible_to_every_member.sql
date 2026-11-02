begin;

set local lock_timeout = '5s';

-- Les badges arborés dans Statistiques ne s'affichaient plus que pour les
-- admins.
--
-- Depuis 20260827160200, public.profile_badge_display_metrics() refuse de
-- calculer le bilan d'un autre membre quand l'appelant n'est pas staff.
-- Or featured_badges() l'appelait pour CHAQUE joueur qui arbore un badge :
-- pour un simple membre, la première ligne d'un autre joueur levait
-- « Forbidden », toute la requête échouait et le tableau des statistiques
-- s'affichait sans aucun badge.
--
-- Correction :
--   1. le calcul part dans private.profile_badge_display_metrics(), non
--      appelable par les membres ; le point d'entrée public garde le même
--      contrôle d'identité et le même contrat ;
--   2. featured_badges() lit une fonction dédiée qui ne renvoie que le
--      chiffre des badges ARBORÉS d'un profil — chiffre déjà affiché à tout
--      le club. Le reste du bilan (dont la métrique du badge secret
--      « Traître ») reste cloisonné.
--
-- featured_badges() reste SECURITY INVOKER : elle continue de respecter les
-- règles d'accès des tables (profil actif obligatoire).

-- ---------------------------------------------------------------------------
-- 1. Implémentation privée du bilan affiché
-- ---------------------------------------------------------------------------

create or replace function private.profile_badge_display_metrics(p_profile_id uuid)
returns table(metric text, current_value integer, display_value integer)
language sql
stable
security definer
set search_path to ''
as $function$
  with raw_metrics as (
    select to_jsonb(m) as metrics
    from private.profile_badge_metrics(p_profile_id) m
  ),
  tracked_matches as (
    select
      m.season_id,
      (m.score_as_grinta > m.score_adverse) as win,
      coalesce(st.goals, 0) as goals,
      coalesce(st.assists, 0) as assists,
      (m.score_adverse = 0) as clean_sheet
    from public.season_players sp
    join public.matches m
      on m.season_id = sp.season_id
     and m.status in ('termine', 'archive')
    left join public.match_player_stats st
      on st.season_player_id = sp.id
     and st.match_id = m.id
    left join public.match_attendance att
      on att.season_player_id = sp.id
     and att.match_id = m.id
    left join public.match_man_of_match motm
      on motm.season_player_id = sp.id
     and motm.match_id = m.id
    where sp.profile_id = p_profile_id
      and (
        st.match_id is not null
        or att.match_id is not null
        or motm.match_id is not null
      )
  ),
  tracked_seasons as (
    select
      season_id,
      count(*)::int as matches_played,
      count(*) filter (where win)::int as wins,
      coalesce(sum(goals), 0)::int as goals,
      coalesce(sum(assists), 0)::int as assists,
      count(*) filter (where clean_sheet)::int as clean_sheets
    from tracked_matches
    group by season_id
  ),
  season_best as (
    select
      coalesce(max(matches_played), 0)::int as matches_played_season,
      coalesce(max(wins), 0)::int as wins_season,
      coalesce(max(goals), 0)::int as goals_season,
      coalesce(max(assists), 0)::int as assists_season,
      coalesce(max(clean_sheets), 0)::int as clean_sheets_season
    from tracked_seasons
  ),
  badge_metrics as (
    select distinct b.metric
    from public.badges b
    where b.metric is not null
  )
  select
    bm.metric,
    coalesce((rm.metrics ->> bm.metric)::int, 0) as current_value,
    case bm.metric
      when 'matches_played_season' then sb.matches_played_season
      when 'wins_season' then sb.wins_season
      when 'goals_season' then sb.goals_season
      when 'assists_season' then sb.assists_season
      when 'clean_sheets_season' then sb.clean_sheets_season
      else coalesce((rm.metrics ->> bm.metric)::int, 0)
    end as display_value
  from badge_metrics bm
  cross join raw_metrics rm
  cross join season_best sb;
$function$;

alter function private.profile_badge_display_metrics(uuid) owner to postgres;
revoke all on function private.profile_badge_display_metrics(uuid)
  from public, anon, authenticated;
grant execute on function private.profile_badge_display_metrics(uuid)
  to service_role;

comment on function private.profile_badge_display_metrics(uuid) is
  'Implementation du bilan affiche des badges. Reservee aux appelants internes : passer par public.profile_badge_display_metrics() qui controle l''identite.';

-- ---------------------------------------------------------------------------
-- 2. Point d'entrée public : même contrat, même contrôle d'identité
-- ---------------------------------------------------------------------------

create or replace function public.profile_badge_display_metrics(p_profile_id uuid)
returns table(metric text, current_value integer, display_value integer)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if p_profile_id is null then
    return;
  end if;

  if p_profile_id is distinct from (select auth.uid())
     and not public.is_match_staff() then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  return query
  select * from private.profile_badge_display_metrics(p_profile_id);
end;
$function$;

alter function public.profile_badge_display_metrics(uuid) owner to postgres;
revoke all on function public.profile_badge_display_metrics(uuid) from public, anon;
grant execute on function public.profile_badge_display_metrics(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Chiffres des seuls badges arborés, lisibles par tout membre
-- ---------------------------------------------------------------------------

create or replace function private.featured_badge_display_values(p_profile_id uuid)
returns table(metric text, display_value integer)
language sql
stable
security definer
set search_path to ''
as $function$
  select dm.metric, dm.display_value
  from private.profile_badge_display_metrics(p_profile_id) dm
  where dm.metric in (
    select b.metric
    from public.profile_badges pb
    join public.badges b on b.id = pb.badge_id
    where pb.profile_id = p_profile_id
      and pb.featured
      and b.metric is not null
  );
$function$;

alter function private.featured_badge_display_values(uuid) owner to postgres;
revoke all on function private.featured_badge_display_values(uuid) from public, anon;
-- `private` n'est pas exposé par l'API : ce grant sert uniquement à
-- featured_badges(), qui s'exécute avec les droits du membre connecté.
grant execute on function private.featured_badge_display_values(uuid)
  to authenticated, service_role;

comment on function private.featured_badge_display_values(uuid) is
  'Chiffre affiche des badges arbores d''un profil (deja visible de tout le club). Utilise par public.featured_badges().';

-- ---------------------------------------------------------------------------
-- 4. featured_badges() lit les chiffres arborés au lieu du bilan complet
-- ---------------------------------------------------------------------------

create or replace function public.featured_badges()
returns table(
  profile_id uuid,
  code text,
  emoji text,
  image_url text,
  color text,
  metric text,
  threshold integer,
  display_value integer,
  has_star boolean,
  stars integer,
  category text,
  sort_order integer
)
language sql
stable
set search_path to ''
as $function$
  with featured_profiles as materialized (
    select distinct pb.profile_id
    from public.profile_badges pb
    where pb.featured
  ),
  profile_display_metrics as materialized (
    select
      fp.profile_id,
      dm.metric,
      dm.display_value
    from featured_profiles fp
    cross join lateral private.featured_badge_display_values(fp.profile_id) dm
  ),
  starred_featured as materialized (
    select distinct
      pb.profile_id,
      b.code
    from public.profile_badges pb
    join public.badges b on b.id = pb.badge_id
    where pb.featured
      and b.has_star
  ),
  starred_profiles as materialized (
    select distinct sf.profile_id
    from starred_featured sf
  ),
  featured_stars as materialized (
    select
      sp.profile_id,
      bs.badge_code,
      bs.stars
    from starred_profiles sp
    cross join lateral private.profile_badge_stars(sp.profile_id) bs
    join starred_featured sf
      on sf.profile_id = sp.profile_id
     and sf.code = bs.badge_code
  )
  select
    pb.profile_id,
    b.code,
    b.emoji,
    b.image_url,
    b.color,
    b.metric,
    b.threshold,
    case
      when b.metric is null then null
      else coalesce(pdm.display_value, 0)
    end as display_value,
    b.has_star,
    coalesce(fs.stars, 1) as stars,
    b.category,
    b.sort_order
  from public.profile_badges pb
  join public.badges b on b.id = pb.badge_id
  left join profile_display_metrics pdm
    on pdm.profile_id = pb.profile_id
   and pdm.metric = b.metric
  left join featured_stars fs
    on fs.profile_id = pb.profile_id
   and fs.badge_code = b.code
  where pb.featured
  order by pb.profile_id, b.sort_order;
$function$;

revoke all on function public.featured_badges() from public, anon;
grant execute on function public.featured_badges() to authenticated, service_role;

commit;
