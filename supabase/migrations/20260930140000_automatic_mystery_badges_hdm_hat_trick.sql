begin;

-- Deux badges mystère de plus décernés automatiquement.
--
-- * motm_back_to_back — « Doublé HDM » : être homme du match sur deux matchs
--   de suite parmi ceux que la personne a joués. Un match où elle était
--   absente ne casse pas la série ; un co-homme du match compte.
-- * season_hat_trick — « Coup du chapeau » : gagner trois trophées de fin de
--   saison dans la même saison. « Saison complète » récompense la présence et
--   ne compte pas comme trophée.
--
-- Comme pour les trois premières règles, rien n'est retiré et l'attribution
-- manuelle reste possible. Le recalcul existant (validation d'un match, vote
-- homme du match, remise des trophées de fin de saison) décerne ces badges
-- sans autre changement : seule la liste des faits réalisés s'allonge.

-- ---------------------------------------------------------------------------
-- 1. Nouvelles règles autorisées et badges concernés
-- ---------------------------------------------------------------------------

alter table public.badges
  drop constraint if exists badges_auto_rule_check;
alter table public.badges
  add constraint badges_auto_rule_check
  check (
    auto_rule is null
    or auto_rule in (
      'goal_and_assist', 'remontada', 'clutch',
      'motm_back_to_back', 'season_hat_trick'
    )
  );

comment on column public.badges.auto_rule is
  'Fait qui décerne ce badge automatiquement (goal_and_assist, remontada, clutch, motm_back_to_back, season_hat_trick). Nul pour un badge seulement manuel ou à barème.';

update public.badges
set auto_rule = 'motm_back_to_back'
where code = 'custom_doubl_hdm_1790772063214';

update public.badges
set auto_rule = 'season_hat_trick'
where code = 'custom_coup_du_chapeau_1790725592200';

-- ---------------------------------------------------------------------------
-- 2. Faits réalisés par une personne
-- ---------------------------------------------------------------------------
--
-- Corps identique à 20260923230000 pour les trois premières règles. Le
-- « Coup du chapeau » ne se rattache à aucun match : match_id est nul et la
-- date retenue est celle de la remise du troisième trophée.

create or replace function private.profile_match_exploits(p_profile_id uuid)
returns table(rule text, match_id uuid, kickoff_at timestamptz)
language sql
stable
security definer
set search_path to ''
as $function$
  with played as (
    -- Mêmes matchs que « matchs joués » dans les badges à barème : un match
    -- terminé où la personne a une ligne de statistiques, de présence ou
    -- d'homme du match.
    select m.id as match_id, sp.id as season_player_id
    from public.season_players sp
    join public.matches m
      on m.season_id = sp.season_id
     and m.status in ('termine', 'archive')
    where sp.profile_id = p_profile_id
      and (
        exists (
          select 1 from public.match_player_stats st
          where st.match_id = m.id and st.season_player_id = sp.id
        )
        or exists (
          select 1 from public.match_attendance att
          where att.match_id = m.id and att.season_player_id = sp.id
        )
        or exists (
          select 1 from public.match_man_of_match mv
          where mv.match_id = m.id and mv.season_player_id = sp.id
        )
      )
  ),
  scored_matches as (
    -- Matchs gagnés contre un adversaire dont les buts saisis correspondent
    -- exactement au score final.
    select m.id as match_id, m.score_as_grinta, m.score_adverse,
      coalesce(m.planned_duration_minutes, 90) as planned_duration_minutes
    from public.matches m
    where m.id in (select played.match_id from played)
      and m.match_type is distinct from 'entre_nous'
      and m.score_as_grinta > m.score_adverse
      and (
        select count(*) from public.match_sport_goal_actions ga
        where ga.match_id = m.id and ga.team_side = 'as_grinta'
      ) = m.score_as_grinta
      and (
        select count(*) from public.match_sport_goal_actions ga
        where ga.match_id = m.id and ga.team_side = 'opponent'
      ) = m.score_adverse
  ),
  timeline as (
    -- Écart en défaveur d'AS Grinta après chaque but, dans l'ordre des
    -- minutes (l'ordre du compte rendu départage une même minute).
    select ga.match_id, ga.minute,
      sum(case when ga.team_side = 'opponent' then 1 else -1 end) over (
        partition by ga.match_id
        order by ga.minute, ga.ordinal
        rows between unbounded preceding and current row
      ) as deficit
    from public.match_sport_goal_actions ga
    where ga.match_id in (select scored_matches.match_id from scored_matches)
  ),
  remontadas as (
    select timeline.match_id
    from timeline
    group by timeline.match_id
    having count(*) filter (where timeline.minute is null) = 0
       and max(timeline.deficit) >= 2
  ),
  grinta_goals as (
    select ga.match_id, ga.minute, ga.scorer_participant_id,
      row_number() over (
        partition by ga.match_id order by ga.minute, ga.ordinal
      ) as goal_rank,
      count(*) filter (where ga.minute is null) over (
        partition by ga.match_id
      ) as unknown_minutes
    from public.match_sport_goal_actions ga
    where ga.team_side = 'as_grinta'
      and ga.match_id in (select scored_matches.match_id from scored_matches)
  ),
  motm_sequence as (
    -- Les matchs joués dans l'ordre, avec l'élection homme du match de chacun
    -- et celle du match joué juste avant.
    select sequenced.match_id, sequenced.is_motm,
      lag(sequenced.is_motm) over (
        order by sequenced.played_at, sequenced.match_id
      ) as previous_is_motm
    from (
      select played.match_id,
        coalesce(
          m.kickoff_at,
          m.match_date::timestamp at time zone 'Europe/Paris'
        ) as played_at,
        exists (
          select 1 from public.match_man_of_match mv
          where mv.match_id = played.match_id
            and mv.season_player_id = played.season_player_id
        ) as is_motm
      from played
      join public.matches m on m.id = played.match_id
    ) sequenced
  ),
  exploits as (
    select 'goal_and_assist'::text as rule, played.match_id
    from played
    join public.match_player_stats st
      on st.match_id = played.match_id
     and st.season_player_id = played.season_player_id
    where st.goals >= 1
      and st.assists >= 1

    union

    select 'remontada', played.match_id
    from played
    join remontadas on remontadas.match_id = played.match_id

    union

    select 'clutch', goal.match_id
    from grinta_goals goal
    join scored_matches sm on sm.match_id = goal.match_id
    join public.match_sport_participants participant
      on participant.id = goal.scorer_participant_id
    join played
      on played.match_id = goal.match_id
     and played.season_player_id = participant.season_player_id
    where goal.unknown_minutes = 0
      and goal.goal_rank = sm.score_adverse + 1
      and goal.minute >= sm.planned_duration_minutes - 5

    union

    select 'motm_back_to_back', motm_sequence.match_id
    from motm_sequence
    where motm_sequence.is_motm
      and motm_sequence.previous_is_motm
  ),
  hat_tricks as (
    select award.season_id,
      max(award.created_at) as awarded_at
    from public.season_awards award
    where award.profile_id = p_profile_id
      and award.award_type <> 'season_complete'
    group by award.season_id
    having count(distinct award.award_type) >= 3
  )
  select exploits.rule, exploits.match_id, m.kickoff_at
  from exploits
  join public.matches m on m.id = exploits.match_id

  union all

  select 'season_hat_trick', null::uuid, hat_tricks.awarded_at
  from hat_tricks;
$function$;

alter function private.profile_match_exploits(uuid) owner to postgres;
revoke all on function private.profile_match_exploits(uuid)
  from public, anon, authenticated;
grant execute on function private.profile_match_exploits(uuid) to service_role;

comment on function private.profile_match_exploits(uuid) is
  'Faits (goal_and_assist, remontada, clutch, motm_back_to_back, season_hat_trick) réalisés par une personne, avec le match concerné quand il y en a un.';

-- ---------------------------------------------------------------------------
-- 3. Rattrapage : matchs et saisons déjà terminés
-- ---------------------------------------------------------------------------

select public.recalculate_all_badges();

commit;
