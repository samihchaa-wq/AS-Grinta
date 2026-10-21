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
-- par son compte, ou par son nom complet et son poste, sur la ligne Carrière
-- de la vue. Ses saisons sont celles des deux composantes de cette ligne, et
-- d'elles seules : la somme des saisons retombe ainsi sur la ligne, même si
-- un effectif change de poste, d'orthographe ou de majuscules (la vue en
-- fait alors une autre ligne).
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

-- La fusion de deux identités (rattachement d'un compte à sa fiche d'archive)
-- déplace tout l'historique de l'identité perdante avant de la supprimer :
-- elle déplace aussi ces lignes. Corps en service en production, plus le
-- contrôle et le déplacement de cette table, et le refus de réunir deux
-- lignes de carrière importées.
create or replace function private.merge_player_identities(
  p_source_player_id uuid,
  p_target_player_id uuid
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if p_source_player_id is null
     or p_target_player_id is null
     or p_source_player_id = p_target_player_id then
    return;
  end if;

  if not exists (
    select 1 from public.players p where p.id = p_source_player_id
  ) or not exists (
    select 1 from public.players p where p.id = p_target_player_id
  ) then
    raise exception 'Canonical player identity not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.profiles p where p.player_id = p_source_player_id
  ) then
    raise exception 'Cannot merge two account-backed player identities'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.historical_match_players source_row
    join public.historical_match_players target_row
      on target_row.match_id = source_row.match_id
     and target_row.player_id = p_target_player_id
    where source_row.player_id = p_source_player_id
  ) then
    raise exception 'Archived match contains both player identities; manual resolution required'
      using errcode = '23514';
  end if;

  -- Deux lignes de carrière importées sur une même identité mêleraient leurs
  -- archives match par match, que rien ne permet plus de séparer : c'est le
  -- cas d'un compte rattaché à une fiche d'archive puis à une autre.
  if exists (
    select 1 from public.historical_player_statistics h
    where h.scope = 'all_time' and h.player_id = p_source_player_id
  ) and exists (
    select 1 from public.historical_player_statistics h
    where h.scope = 'all_time' and h.player_id = p_target_player_id
  ) then
    raise exception 'Both player identities have an archived career line; manual resolution required'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.historical_unscored_match_contributions source_row
    join public.historical_unscored_match_contributions target_row
      on target_row.match_date = source_row.match_date
     and target_row.player_id = p_target_player_id
    where source_row.player_id = p_source_player_id
  ) then
    raise exception 'Unscored match contains both player identities; manual resolution required'
      using errcode = '23514';
  end if;

  delete from public.player_aliases source_alias
  using public.player_aliases target_alias
  where source_alias.player_id = p_source_player_id
    and target_alias.player_id = p_target_player_id
    and private.normalize_player_name(source_alias.alias)
      = private.normalize_player_name(target_alias.alias);

  update public.player_aliases
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.historical_match_players
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.historical_unscored_match_contributions
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.historical_player_name_links
  set player_id = p_target_player_id, updated_at = now()
  where player_id = p_source_player_id;

  update public.historical_player_statistics
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.guest_players
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.season_players
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  delete from public.players
  where id = p_source_player_id;
end;
$function$;

-- Chaque ligne de la vue dit de quoi elle est faite : l'identité de sa ligne
-- d'archive importée (archive_player_id) et le nom exact de son groupe
-- d'effectifs (app_full_name). La vue réunit les deux sur le nom (casse et
-- espaces extérieurs ignorés) et le poste, mais regroupe les effectifs sur le
-- nom exact : deux saisons saisies avec d'autres majuscules font deux lignes.
-- Le détail par saison reprend exactement ces deux composantes. Définition en
-- service en production (20260831203000), à ces deux colonnes près, ajoutées
-- en fin de liste ; rien d'autre ne change.
create or replace view public.v_statistics_players
with (security_invoker = true)
as
with open_season as (
  select id, name
  from public.seasons
  where status = 'open'
  order by created_at desc
  limit 1
),
prev_ref as (
  select s.id, s.name
  from public.seasons s
  cross join open_season o
  where s.name < o.name
  order by s.name desc
  limit 1
),
app_present as (
  select present.match_id,
         present.season_player_id,
         m.season_id,
         m.score_as_grinta,
         m.score_adverse
  from (
    select match_id, season_player_id from public.match_attendance
    union
    select match_id, season_player_id from public.match_player_stats
    union
    select match_id, season_player_id from public.match_man_of_match
  ) present
  join public.matches m
    on m.id = present.match_id
   and m.status in ('termine', 'archive')
),
app_results as (
  select
    app_present.season_player_id,
    count(*)::integer as matches_played,
    count(*) filter (where app_present.score_as_grinta > app_present.score_adverse)::integer as wins,
    count(*) filter (where app_present.score_as_grinta = app_present.score_adverse)::integer as draws,
    count(*) filter (where app_present.score_as_grinta < app_present.score_adverse)::integer as losses,
    count(*) filter (where app_present.score_adverse = 0)::integer as team_clean_sheets
  from app_present
  group by app_present.season_player_id
),
app_pstats as (
  select
    st.season_player_id,
    coalesce(sum(st.goals), 0::bigint)::integer as goals,
    coalesce(sum(st.assists), 0::bigint)::integer as assists,
    count(*) filter (where st.clean_sheet)::integer as clean_sheets
  from public.match_player_stats st
  join public.matches m
    on m.id = st.match_id
   and m.status in ('termine', 'archive')
  group by st.season_player_id
),
app_mvp as (
  select
    mvp.season_player_id,
    count(distinct mvp.match_id)::integer as hdm
  from public.match_man_of_match mvp
  join public.matches m
    on m.id = mvp.match_id
   and m.status in ('termine', 'archive')
  group by mvp.season_player_id
),
app_season_player as (
  select
    sp.season_id,
    sp.profile_id,
    sp.position as display_order,
    concat_ws(' ', sp.first_name, nullif(sp.last_name, '')) as full_name,
    sp.is_goalkeeper,
    sp.is_active,
    coalesce(r.matches_played, 0) as matches_played,
    coalesce(r.wins, 0) as wins,
    coalesce(r.draws, 0) as draws,
    coalesce(r.losses, 0) as losses,
    coalesce(g.goals, 0) as goals,
    coalesce(g.assists, 0) as assists,
    coalesce(mv.hdm, 0) as hdm,
    coalesce(g.clean_sheets, 0) as clean_sheets,
    coalesce(r.team_clean_sheets, 0) as team_clean_sheets,
    case
      when sp.is_goalkeeper then coalesce(g.clean_sheets, 0)
      else coalesce(g.goals, 0)
    end as ranking_metric
  from public.season_players sp
  left join app_results r on r.season_player_id = sp.id
  left join app_pstats g on g.season_player_id = sp.id
  left join app_mvp mv on mv.season_player_id = sp.id
  where not sp.is_coach
),
prev_has_app as (
  select exists (
    select 1
    from app_season_player asp
    join prev_ref pr on pr.id = asp.season_id
  ) as has_app
),
current_ranked as (
  select
    'current'::text as period_key,
    os.name as period_label,
    rank() over (
      partition by asp.is_goalkeeper
      order by asp.ranking_metric desc
    )::integer as display_rank,
    coalesce(asp.display_order, 9999) as display_order,
    asp.full_name as player_name,
    asp.is_goalkeeper,
    asp.matches_played,
    asp.wins,
    asp.draws,
    asp.losses,
    asp.goals,
    asp.assists,
    asp.hdm,
    asp.clean_sheets,
    asp.profile_id,
    asp.team_clean_sheets,
    null::uuid as archive_player_id,
    asp.full_name as app_full_name
  from app_season_player asp
  join open_season os on os.id = asp.season_id
  where asp.is_active
),
previous_from_app as (
  select
    'previous'::text as period_key,
    pr.name as period_label,
    rank() over (
      partition by asp.is_goalkeeper
      order by asp.ranking_metric desc
    )::integer as display_rank,
    coalesce(asp.display_order, 9999) as display_order,
    asp.full_name as player_name,
    asp.is_goalkeeper,
    asp.matches_played,
    asp.wins,
    asp.draws,
    asp.losses,
    asp.goals,
    asp.assists,
    asp.hdm,
    asp.clean_sheets,
    asp.profile_id,
    asp.team_clean_sheets,
    null::uuid as archive_player_id,
    asp.full_name as app_full_name
  from app_season_player asp
  join prev_ref pr on pr.id = asp.season_id
  cross join prev_has_app ph
  where ph.has_app
),
previous_from_import as (
  select
    'previous'::text as period_key,
    h.season_name as period_label,
    h.display_rank,
    h.display_rank as display_order,
    h.player_name,
    h.is_goalkeeper,
    h.matches_played,
    h.wins,
    h.draws,
    h.losses,
    h.goals,
    0 as assists,
    h.hdm,
    coalesce(h.clean_sheets, 0) as clean_sheets,
    h.profile_id,
    coalesce(h.team_clean_sheets, 0) as team_clean_sheets,
    h.player_id as archive_player_id,
    null::text as app_full_name
  from public.historical_player_statistics h
  cross join prev_has_app ph
  where h.scope = 'previous'
    and not ph.has_app
),
historical_all_time as (
  select
    h.player_id,
    h.player_name,
    h.profile_id,
    h.is_goalkeeper,
    h.matches_played,
    h.wins,
    h.draws,
    h.losses,
    h.goals,
    h.hdm,
    coalesce(h.clean_sheets, 0) as clean_sheets,
    coalesce(h.team_clean_sheets, 0) as team_clean_sheets
  from public.historical_player_statistics h
  where h.scope = 'all_time'
),
app_all as (
  select
    app_season_player.full_name,
    app_season_player.is_goalkeeper,
    max(app_season_player.profile_id::text)::uuid as profile_id,
    sum(app_season_player.matches_played)::integer as matches_played,
    sum(app_season_player.wins)::integer as wins,
    sum(app_season_player.draws)::integer as draws,
    sum(app_season_player.losses)::integer as losses,
    sum(app_season_player.goals)::integer as goals,
    sum(app_season_player.assists)::integer as assists,
    sum(app_season_player.hdm)::integer as hdm,
    sum(app_season_player.clean_sheets)::integer as clean_sheets,
    sum(app_season_player.team_clean_sheets)::integer as team_clean_sheets
  from app_season_player
  group by app_season_player.full_name, app_season_player.is_goalkeeper
  having sum(app_season_player.matches_played) > 0
),
all_time_combined as (
  select
    coalesce(history.player_name, app.full_name) as player_name,
    coalesce(history.profile_id, app.profile_id) as profile_id,
    coalesce(history.is_goalkeeper, app.is_goalkeeper) as is_goalkeeper,
    coalesce(history.matches_played, 0) + coalesce(app.matches_played, 0) as matches_played,
    coalesce(history.wins, 0) + coalesce(app.wins, 0) as wins,
    coalesce(history.draws, 0) + coalesce(app.draws, 0) as draws,
    coalesce(history.losses, 0) + coalesce(app.losses, 0) as losses,
    coalesce(history.goals, 0) + coalesce(app.goals, 0) as goals,
    coalesce(app.assists, 0) as assists,
    coalesce(history.hdm, 0) + coalesce(app.hdm, 0) as hdm,
    coalesce(history.clean_sheets, 0) + coalesce(app.clean_sheets, 0) as clean_sheets,
    coalesce(history.team_clean_sheets, 0) + coalesce(app.team_clean_sheets, 0) as team_clean_sheets,
    history.player_id as archive_player_id,
    app.full_name as app_full_name
  from historical_all_time history
  full join app_all app
    on lower(btrim(history.player_name)) = lower(btrim(app.full_name))
   and history.is_goalkeeper = app.is_goalkeeper
),
all_time_ranked as (
  select
    'all_time'::text as period_key,
    'Toutes saisons'::text as period_label,
    rank() over (
      partition by all_time_combined.is_goalkeeper
      order by all_time_combined.matches_played desc,
               all_time_combined.goals desc,
               all_time_combined.player_name
    )::integer as display_rank,
    rank() over (
      partition by all_time_combined.is_goalkeeper
      order by all_time_combined.matches_played desc,
               all_time_combined.goals desc,
               all_time_combined.player_name
    )::integer as display_order,
    all_time_combined.player_name,
    all_time_combined.is_goalkeeper,
    all_time_combined.matches_played,
    all_time_combined.wins,
    all_time_combined.draws,
    all_time_combined.losses,
    all_time_combined.goals,
    all_time_combined.assists,
    all_time_combined.hdm,
    all_time_combined.clean_sheets,
    all_time_combined.profile_id,
    all_time_combined.team_clean_sheets,
    all_time_combined.archive_player_id,
    all_time_combined.app_full_name
  from all_time_combined
)
select
  current_ranked.period_key,
  current_ranked.period_label,
  current_ranked.display_rank,
  current_ranked.display_order,
  current_ranked.player_name,
  current_ranked.is_goalkeeper,
  current_ranked.matches_played,
  current_ranked.wins,
  current_ranked.draws,
  current_ranked.losses,
  current_ranked.goals,
  current_ranked.hdm,
  current_ranked.clean_sheets,
  current_ranked.profile_id,
  current_ranked.team_clean_sheets,
  current_ranked.assists,
  current_ranked.archive_player_id,
  current_ranked.app_full_name
from current_ranked
union all
select
  previous_from_app.period_key,
  previous_from_app.period_label,
  previous_from_app.display_rank,
  previous_from_app.display_order,
  previous_from_app.player_name,
  previous_from_app.is_goalkeeper,
  previous_from_app.matches_played,
  previous_from_app.wins,
  previous_from_app.draws,
  previous_from_app.losses,
  previous_from_app.goals,
  previous_from_app.hdm,
  previous_from_app.clean_sheets,
  previous_from_app.profile_id,
  previous_from_app.team_clean_sheets,
  previous_from_app.assists,
  previous_from_app.archive_player_id,
  previous_from_app.app_full_name
from previous_from_app
union all
select
  previous_from_import.period_key,
  previous_from_import.period_label,
  previous_from_import.display_rank,
  previous_from_import.display_order,
  previous_from_import.player_name,
  previous_from_import.is_goalkeeper,
  previous_from_import.matches_played,
  previous_from_import.wins,
  previous_from_import.draws,
  previous_from_import.losses,
  previous_from_import.goals,
  previous_from_import.hdm,
  previous_from_import.clean_sheets,
  previous_from_import.profile_id,
  previous_from_import.team_clean_sheets,
  previous_from_import.assists,
  previous_from_import.archive_player_id,
  previous_from_import.app_full_name
from previous_from_import
union all
select
  all_time_ranked.period_key,
  all_time_ranked.period_label,
  all_time_ranked.display_rank,
  all_time_ranked.display_order,
  all_time_ranked.player_name,
  all_time_ranked.is_goalkeeper,
  all_time_ranked.matches_played,
  all_time_ranked.wins,
  all_time_ranked.draws,
  all_time_ranked.losses,
  all_time_ranked.goals,
  all_time_ranked.hdm,
  all_time_ranked.clean_sheets,
  all_time_ranked.profile_id,
  all_time_ranked.team_clean_sheets,
  all_time_ranked.assists,
  all_time_ranked.archive_player_id,
  all_time_ranked.app_full_name
from all_time_ranked;

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
  -- La ligne Carrière que la fiche affiche : même choix que l'application
  -- (compte, ou nom complet et poste ; la plus fournie en matchs d'abord).
  card as (
    select v.archive_player_id, v.app_full_name, v.is_goalkeeper
    from public.v_statistics_players v
    where v.period_key = 'all_time'
      and (
        (p_profile_id is not null and v.profile_id = p_profile_id)
        or (
          v_name <> ''
          and v.is_goalkeeper = p_is_goalkeeper
          and lower(regexp_replace(btrim(v.player_name), '\s+', ' ', 'g')) = v_name
        )
      )
    order by v.matches_played desc, v.goals desc, lower(v.player_name)
    limit 1
  ),
  -- Ses deux composantes, et elles seules : l'identité de sa ligne d'archive,
  -- dont l'archive match par match suit les matchs, et son groupe
  -- d'effectifs (nom exact et poste).
  ids as (
    select card.archive_player_id as player_id
    from card
    where card.archive_player_id is not null
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
    join card
      on concat_ws(' ', sp.first_name, nullif(sp.last_name, '')) = card.app_full_name
     and sp.is_goalkeeper = card.is_goalkeeper
    where not sp.is_coach
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
