-- Bug 3 : le declencheur trg_validate_profile_names s'execute en SECURITY
-- INVOKER, or le role `authenticated` n'avait pas le droit d'executer
-- public.is_valid_person_name(). Toute modification de prenom / nom / surnom
-- par un membre echouait donc en 403 « permission denied for function ».
--
-- Bug 5 : public.profile_badge_metrics() etait la seule fonction SECURITY
-- DEFINER exposee a `authenticated` sans controle d'identite. N'importe quel
-- membre pouvait lire le bilan complet d'un autre membre, y compris la
-- metrique `bet_against_grinta` qui alimente le badge secret « Traitre ».
-- L'implementation part dans le schema private ; le point d'entree public
-- devient un garde-fou. Les consommateurs internes (etoiles de badges,
-- recalcul) attaquent directement l'implementation privee, car ils doivent
-- continuer a calculer pour n'importe quel profil.

begin;

-- ---------------------------------------------------------------------------
-- Bug 3 — validation des noms de profil
-- ---------------------------------------------------------------------------

revoke all on function public.is_valid_person_name(text) from public, anon;
grant execute on function public.is_valid_person_name(text)
  to authenticated, service_role;

comment on function public.is_valid_person_name(text) is
  'Verifie qu''un nom de personne ne contient que des lettres. Executable par authenticated : trg_validate_profile_names l''appelle en SECURITY INVOKER.';

-- ---------------------------------------------------------------------------
-- Bug 5 — cloisonnement des metriques de badges
-- ---------------------------------------------------------------------------

-- L'implementation complete quitte `public` sans etre recopiee.
alter function public.profile_badge_metrics(uuid) set schema private;

revoke all on function private.profile_badge_metrics(uuid)
  from public, anon, authenticated;

comment on function private.profile_badge_metrics(uuid) is
  'Implementation reelle des metriques de badges. Reservee aux appelants internes : passer par public.profile_badge_metrics() qui controle l''identite.';

-- Point d'entree public : un membre ne lit que son propre bilan, le staff lit
-- celui de tout le monde.
CREATE OR REPLACE FUNCTION "public"."profile_badge_metrics"("p_profile_id" "uuid") RETURNS TABLE("matches_played_season" integer, "wins_season" integer, "goals_season" integer, "clean_sheets_season" integer, "matches_played" integer, "wins" integer, "goals" integer, "doubles" integer, "max_match_goals" integer, "mvp" integer, "clean_sheets" integer, "pred_good_result" integer, "pred_exact_score" integer, "bet_against_grinta" integer, "perfect_own_goals_prediction" integer, "seasons_complete" integer, "title_most_present" integer, "title_top_scorer" integer, "title_mvp_king" integer, "title_best_winrate" integer, "title_best_pred_player" integer, "title_best_pred_match" integer, "title_best_pred_overall" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $function$
begin
  if p_profile_id is null then
    return;
  end if;

  if p_profile_id is distinct from (select auth.uid())
     and not public.is_match_staff() then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  return query select * from private.profile_badge_metrics(p_profile_id);
end;
$function$;

ALTER FUNCTION "public"."profile_badge_metrics"("p_profile_id" "uuid") OWNER TO "postgres";

revoke all on function public.profile_badge_metrics(uuid) from public, anon;
grant execute on function public.profile_badge_metrics(uuid)
  to authenticated, service_role;

comment on function public.profile_badge_metrics(uuid) is
  'Metriques de badges d''un profil : reservees au profil appelant, sauf pour le staff (is_match_staff).';

-- ---------------------------------------------------------------------------
-- Etoiles de badges : meme decoupage implementation privee / entree gardee.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "private"."profile_badge_stars"("p_profile_id" "uuid") RETURNS TABLE("badge_code" "text", "stars" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with metrics as (
    select to_jsonb(t) as v from private.profile_badge_metrics(p_profile_id) t
  ), pm as (
    select m.season_id,
           (m.score_as_grinta > m.score_adverse) as win,
           coalesce(st.goals, 0) as g,
           coalesce(st.clean_sheet, false) as cs
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
           count(*) filter (where cs) as csn
    from pm group by season_id
  ), seasonal as (
    select b.code as badge_code, count(*)::int as stars
    from public.badges b
    join ps on (
         (b.metric = 'goals_season' and ps.gg >= b.threshold)
      or (b.metric = 'wins_season' and ps.w >= b.threshold)
      or (b.metric = 'matches_played_season' and ps.mp >= b.threshold)
      or (b.metric = 'clean_sheets_season' and ps.csn >= b.threshold)
    )
    where b.has_star and b.category = 'joueur_saison'
    group by b.code
  ), palmares as (
    select b.code as badge_code, count(sa.*)::int as stars
    from public.badges b
    join public.season_awards sa
      on sa.profile_id = p_profile_id
     and sa.award_type = case
           when b.metric = 'seasons_complete' then 'season_complete'
           else substring(b.metric from 7)
         end
    where b.has_star and b.category = 'palmares'
    group by b.code
  ), career as (
    select b.code as badge_code,
           (coalesce((m.v ->> b.metric)::int, 0) / b.threshold)::int as stars
    from public.badges b
    cross join metrics m
    where b.has_star
      and b.category in ('joueur_all_time', 'pronos_all_time')
      and b.metric is not null
      and b.threshold is not null and b.threshold > 0
      and coalesce((m.v ->> b.metric)::int, 0) >= b.threshold
  )
  select badge_code, stars from seasonal
  union all
  select badge_code, stars from palmares
  union all
  select badge_code, stars from career;
$$;

ALTER FUNCTION "private"."profile_badge_stars"("p_profile_id" "uuid") OWNER TO "postgres";

revoke all on function private.profile_badge_stars(uuid) from public, anon;
-- `private` n'est pas exposee par PostgREST : ce grant sert uniquement aux
-- fonctions SECURITY INVOKER du schema public, comme featured_badges().
grant execute on function private.profile_badge_stars(uuid)
  to authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."profile_badge_stars"("p_profile_id" "uuid") RETURNS TABLE("badge_code" "text", "stars" integer)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $function$
begin
  if p_profile_id is null then
    return;
  end if;

  if p_profile_id is distinct from (select auth.uid())
     and not public.is_match_staff() then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  return query select * from private.profile_badge_stars(p_profile_id);
end;
$function$;

ALTER FUNCTION "public"."profile_badge_stars"("p_profile_id" "uuid") OWNER TO "postgres";

revoke all on function public.profile_badge_stars(uuid) from public, anon;
grant execute on function public.profile_badge_stars(uuid)
  to authenticated, service_role;

comment on function public.profile_badge_stars(uuid) is
  'Etoiles de badges d''un profil : reservees au profil appelant, sauf pour le staff (is_match_staff).';

-- ---------------------------------------------------------------------------
-- Consommateurs internes repointes sur l'implementation privee.
-- ---------------------------------------------------------------------------

-- featured_badges() reste SECURITY INVOKER : seul le nom de la fonction
-- d'etoiles appelee change, les badges affiches restent filtres par la RLS de
-- profile_badges.

CREATE OR REPLACE FUNCTION "public"."featured_badges"() RETURNS TABLE("profile_id" "uuid", "code" "text", "emoji" "text", "image_url" "text", "color" "text", "metric" "text", "threshold" integer, "has_star" boolean, "stars" integer, "category" "text", "sort_order" integer)
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  with starred_featured as materialized (
    select distinct
      profile_badge.profile_id,
      badge.code
    from public.profile_badges profile_badge
    join public.badges badge on badge.id = profile_badge.badge_id
    where profile_badge.featured
      and badge.has_star
  ),
  starred_profiles as materialized (
    select distinct starred_featured.profile_id
    from starred_featured
  ),
  featured_stars as materialized (
    select
      starred_profile.profile_id,
      badge_star.badge_code,
      badge_star.stars
    from starred_profiles starred_profile
    cross join lateral private.profile_badge_stars(
      starred_profile.profile_id
    ) badge_star
    join starred_featured
      on starred_featured.profile_id = starred_profile.profile_id
     and starred_featured.code = badge_star.badge_code
  )
  select
    profile_badge.profile_id,
    badge.code,
    badge.emoji,
    badge.image_url,
    badge.color,
    badge.metric,
    badge.threshold,
    badge.has_star,
    coalesce(featured_star.stars, 1) as stars,
    badge.category,
    badge.sort_order
  from public.profile_badges profile_badge
  join public.badges badge on badge.id = profile_badge.badge_id
  left join featured_stars featured_star
    on featured_star.profile_id = profile_badge.profile_id
   and featured_star.badge_code = badge.code
  where profile_badge.featured
  order by profile_badge.profile_id, badge.sort_order;
$$;

CREATE OR REPLACE FUNCTION "public"."recalculate_profile_badges"("p_profile_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v jsonb;
  b record;
  val integer;
begin
  if p_profile_id is null then
    return;
  end if;
  select to_jsonb(t) into v from private.profile_badge_metrics(p_profile_id) t;
  if v is null then
    return;
  end if;
  for b in
    select id, metric, threshold from public.badges
    where auto and kind = 'tier' and metric is not null and threshold is not null
  loop
    val := coalesce((v ->> b.metric)::int, 0);
    if val >= b.threshold then
      insert into public.profile_badges(profile_id, badge_id, source)
      values (p_profile_id, b.id, 'auto')
      on conflict (profile_id, badge_id) do nothing;
    else
      delete from public.profile_badges
      where profile_id = p_profile_id and badge_id = b.id and source = 'auto';
    end if;
  end loop;
end;
$$;

commit;
