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
--
-- Matchs sans score. Le classement importé compte aussi les buts et les
-- hommes du match de matchs officiels (amical, championnat) joués sans score
-- saisi dans SportEasy, sans les compter comme matchs joués. Ces matchs ne
-- sont pas dans l'archive, qui exige un score. D'après le relevé SportEasy du
-- 2026-08-26 (tool/sporteasy), seuls trois matchs officiels sans score ont
-- des buts ou des hommes du match, et leurs lignes ci-dessous font exactement
-- les écarts entre le classement et l'archive : cinq hommes du match, trois
-- buts. Les matchs « entre nous » et le tournoi sans score, eux, ne sont pas
-- comptés par le classement. Le détail par saison ajoute ces lignes sans en
-- faire des matchs joués : chaque saison retombe ainsi sur le classement.
-- Philippe Couzin, élu le 2026-05-04, n'a pas de ligne au classement : il
-- n'est pas repris.

create table public.historical_unscored_match_contributions (
  match_date date not null,
  opponent_name text not null,
  match_type text not null
    check (match_type in ('amical', 'championnat')),
  player_id uuid not null
    references public.players(id) on delete restrict,
  goals integer not null default 0 check (goals >= 0),
  is_motm boolean not null default false,
  primary key (player_id, match_date),
  check (goals > 0 or is_motm)
);

comment on table public.historical_unscored_match_contributions is
  'Buts et hommes du match de matchs officiels joués sans score saisi : comptés par le classement importé (historical_player_statistics), mais pas comme matchs joués. Lecture uniquement via get_player_season_statistics.';

alter table public.historical_unscored_match_contributions enable row level security;

create policy active_authenticated_profile_only
  on public.historical_unscored_match_contributions
  as restrictive
  to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));

create policy deny_client_access
  on public.historical_unscored_match_contributions
  as restrictive
  to anon, authenticated
  using (false)
  with check (false);

revoke all on table public.historical_unscored_match_contributions from public, anon, authenticated;
grant all on table public.historical_unscored_match_contributions to service_role;

insert into public.historical_unscored_match_contributions(
  match_date, opponent_name, match_type, player_id, goals, is_motm
)
select v.match_date, v.opponent_name, v.match_type, h.player_id, v.goals, v.is_motm
from (
  values
    (date '2016-06-28', 'Amicale Football CG31', 'amical', 'Romain Spigolon', 0, true),
    (date '2024-05-17', 'AS Clinique Pasteur', 'amical', 'Yoann Canal', 2, true),
    (date '2024-05-17', 'AS Clinique Pasteur', 'amical', 'Milan Couzin', 1, false),
    (date '2026-05-04', 'FC Boehringer Toulouse', 'championnat', 'Milan Couzin', 0, true),
    (date '2026-05-04', 'FC Boehringer Toulouse', 'championnat', 'Samuel Granier', 0, true),
    (date '2026-05-04', 'FC Boehringer Toulouse', 'championnat', 'Samih Châa', 0, true)
) as v(match_date, opponent_name, match_type, player_name, goals, is_motm)
join public.historical_player_statistics h
  on h.scope = 'all_time'
 and h.player_name = v.player_name;

-- Une base sans archive (installation de test) n'a aucun de ces joueurs. Une
-- base qui les a doit recevoir les six lignes : un nom changé entre-temps
-- laisserait sinon un écart silencieux.
do $$
begin
  if exists (
    select 1
    from public.historical_player_statistics h
    where h.scope = 'all_time'
      and h.player_name in (
        'Romain Spigolon', 'Yoann Canal', 'Milan Couzin',
        'Samuel Granier', 'Samih Châa'
      )
  ) and (
    select count(*) from public.historical_unscored_match_contributions
  ) <> 6 then
    raise exception 'historical_unscored_match_contributions: 6 lignes attendues';
  end if;
end;
$$;

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
  unscored_seasons as (
    select
      us.start_year::text || '-' || (us.start_year + 1)::text as season_name,
      0 as matches_played,
      0 as wins,
      0 as draws,
      0 as losses,
      coalesce(sum(us.goals), 0)::integer as goals,
      count(*) filter (where us.is_motm)::integer as hdm
    from (
      select
        case
          when extract(month from c.match_date) >= 7
            then extract(year from c.match_date)::integer
          else extract(year from c.match_date)::integer - 1
        end as start_year,
        c.goals,
        c.is_motm
      from public.historical_unscored_match_contributions c
      where c.player_id in (select ids.player_id from ids)
    ) us
    group by us.start_year
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
    select * from unscored_seasons
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
