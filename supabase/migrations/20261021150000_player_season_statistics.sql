begin;

-- Fiche joueur : l'évolution de ses statistiques, saison par saison.
--
-- L'onglet Carrière additionne deux sources : le classement importé de
-- l'archive (un total par joueur) et les matchs joués dans l'application.
-- Le graphique d'évolution a besoin du détail par saison : il le refait à
-- partir de l'archive match par match (présence, buts, homme du match) et des
-- matchs de l'application, avec les mêmes règles que la vue des statistiques
-- (match joué = présent, auteur d'une ligne de stats ou élu homme du match ;
-- matchs terminés ou archivés, tous types confondus ; coachs exclus).
--
-- La saison ouverte est signalée comme en cours, comme dans la vue.
--
-- Un match archivé appartient à la saison qui commence le 1er juillet, comme
-- dans le calendrier des archives. Le joueur est retrouvé comme sur sa fiche :
-- par son compte, ou par son nom complet et son poste ; son identité
-- canonique relie ensuite toutes ses saisons et ses lignes d'archive.
--
-- L'archive se lit uniquement par cette fonction, comme le détail d'un match
-- archivé : les tables historiques restent fermées au client.

create function private.get_player_season_statistics(
  p_full_name text,
  p_is_goalkeeper boolean,
  p_profile_id uuid default null
)
returns table(
  season_name text,
  is_current boolean,
  matches_played integer,
  wins integer,
  draws integer,
  losses integer,
  goals integer,
  hdm integer
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_name text := lower(regexp_replace(btrim(coalesce(p_full_name, '')), '\s+', ' ', 'g'));
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  return query
  with open_season as (
    select se.name
    from public.seasons se
    where se.status = 'open'
    order by se.created_at desc
    limit 1
  ),
  ids as (
    select h.player_id
    from public.historical_player_statistics h
    where h.scope = 'all_time'
      and (
        (p_profile_id is not null and h.profile_id = p_profile_id)
        or (
          v_name <> ''
          and h.is_goalkeeper = p_is_goalkeeper
          and lower(regexp_replace(btrim(h.player_name), '\s+', ' ', 'g')) = v_name
        )
      )
    union
    select sp.player_id
    from public.season_players sp
    where not sp.is_coach
      and (
        (p_profile_id is not null and sp.profile_id = p_profile_id)
        or (
          v_name <> ''
          and sp.is_goalkeeper = p_is_goalkeeper
          and lower(regexp_replace(
            btrim(concat_ws(' ', sp.first_name, nullif(sp.last_name, ''))),
            '\s+', ' ', 'g'
          )) = v_name
        )
      )
    union
    select pr.player_id
    from public.profiles pr
    where p_profile_id is not null
      and pr.id = p_profile_id
      and pr.player_id is not null
  ),
  archive_matches as (
    select
      case
        when extract(month from s.match_date) >= 7
          then extract(year from s.match_date)::integer
        else extract(year from s.match_date)::integer - 1
      end as start_year,
      bool_or(hmp.is_present) as is_present,
      max(s.score_as_grinta) as goals_for,
      max(s.score_adverse) as goals_against,
      sum(hmp.goals)::integer as goals,
      bool_or(hmp.is_motm) as is_motm
    from public.historical_match_players hmp
    join public.historical_match_scores s on s.id = hmp.match_id
    where hmp.player_id in (select ids.player_id from ids)
    group by hmp.match_id, s.match_date
  ),
  archive_seasons as (
    select
      am.start_year::text || '-' || (am.start_year + 1)::text as season_name,
      count(*) filter (where am.is_present)::integer as matches_played,
      count(*) filter (
        where am.is_present and am.goals_for > am.goals_against
      )::integer as wins,
      count(*) filter (
        where am.is_present and am.goals_for = am.goals_against
      )::integer as draws,
      count(*) filter (
        where am.is_present and am.goals_for < am.goals_against
      )::integer as losses,
      coalesce(sum(am.goals), 0)::integer as goals,
      count(*) filter (where am.is_motm)::integer as hdm
    from archive_matches am
    group by am.start_year
  ),
  app_rows as (
    select sp.id, sp.season_id
    from public.season_players sp
    where not sp.is_coach
      and sp.player_id in (select ids.player_id from ids)
  ),
  app_present as (
    select distinct present.match_id, m.season_id, m.score_as_grinta, m.score_adverse
    from (
      select ma.match_id, ma.season_player_id from public.match_attendance ma
      union
      select st.match_id, st.season_player_id from public.match_player_stats st
      union
      select mvp.match_id, mvp.season_player_id from public.match_man_of_match mvp
    ) present
    join app_rows r on r.id = present.season_player_id
    join public.matches m
      on m.id = present.match_id
     and m.status in ('termine', 'archive')
  ),
  app_results as (
    select
      ap.season_id,
      count(*)::integer as matches_played,
      count(*) filter (where ap.score_as_grinta > ap.score_adverse)::integer as wins,
      count(*) filter (where ap.score_as_grinta = ap.score_adverse)::integer as draws,
      count(*) filter (where ap.score_as_grinta < ap.score_adverse)::integer as losses
    from app_present ap
    group by ap.season_id
  ),
  app_goals as (
    select r.season_id, coalesce(sum(st.goals), 0)::integer as goals
    from public.match_player_stats st
    join app_rows r on r.id = st.season_player_id
    join public.matches m
      on m.id = st.match_id
     and m.status in ('termine', 'archive')
    group by r.season_id
  ),
  app_mvp as (
    select r.season_id, count(distinct mvp.match_id)::integer as hdm
    from public.match_man_of_match mvp
    join app_rows r on r.id = mvp.season_player_id
    join public.matches m
      on m.id = mvp.match_id
     and m.status in ('termine', 'archive')
    group by r.season_id
  ),
  app_seasons as (
    select
      se.name as season_name,
      ar.matches_played,
      ar.wins,
      ar.draws,
      ar.losses,
      coalesce(g.goals, 0) as goals,
      coalesce(mv.hdm, 0) as hdm
    from app_results ar
    join public.seasons se on se.id = ar.season_id
    left join app_goals g on g.season_id = ar.season_id
    left join app_mvp mv on mv.season_id = ar.season_id
  )
  select
    u.season_name,
    coalesce(u.season_name = (select os.name from open_season os), false),
    sum(u.matches_played)::integer,
    sum(u.wins)::integer,
    sum(u.draws)::integer,
    sum(u.losses)::integer,
    sum(u.goals)::integer,
    sum(u.hdm)::integer
  from (
    select * from archive_seasons
    union all
    select * from app_seasons
  ) u
  group by u.season_name
  order by u.season_name;
end;
$function$;

alter function private.get_player_season_statistics(text, boolean, uuid) owner to postgres;

comment on function private.get_player_season_statistics(text, boolean, uuid) is
  'Statistiques d''un joueur saison par saison (matchs, V/N/D, buts, hommes du match) : archive match par match et matchs de l''application, mêmes règles que v_statistics_players. Joueur retrouvé par son compte, ou par son nom complet et son poste.';

revoke all on function private.get_player_season_statistics(text, boolean, uuid) from public, anon;
grant execute on function private.get_player_season_statistics(text, boolean, uuid) to authenticated, service_role;

create function public.get_player_season_statistics(
  p_full_name text,
  p_is_goalkeeper boolean,
  p_profile_id uuid default null
)
returns table(
  season_name text,
  is_current boolean,
  matches_played integer,
  wins integer,
  draws integer,
  losses integer,
  goals integer,
  hdm integer
)
language sql
stable
set search_path to ''
as $function$
  select *
  from private.get_player_season_statistics(p_full_name, p_is_goalkeeper, p_profile_id);
$function$;

alter function public.get_player_season_statistics(text, boolean, uuid) owner to postgres;

comment on function public.get_player_season_statistics(text, boolean, uuid) is
  'Statistiques d''un joueur saison par saison, pour le graphique d''évolution de sa fiche ; l''autorisation est vérifiée par la fonction privée.';

revoke all on function public.get_player_season_statistics(text, boolean, uuid) from public, anon;
grant execute on function public.get_player_season_statistics(text, boolean, uuid) to authenticated, service_role;

commit;
