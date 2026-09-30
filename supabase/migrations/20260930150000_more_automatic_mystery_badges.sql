begin;

-- Sept badges mystère de plus décernés automatiquement.
--
-- Comme « Au four et au moulin », « Remontada » et « Clutch », ils décrivent
-- un fait que l'application enregistre déjà (buteurs, passeurs, minute des
-- buts, score, homme du match). Rien n'est retiré : un badge gagné le reste,
-- et l'attribution manuelle reste possible.
--
-- * one_two — « Une-deux » : dans un même match, servir un coéquipier sur un
--   but et être servi par lui sur un autre.
-- * first_and_last_goal — « La boucle est bouclée » : marquer le premier et
--   le dernier but du match (au moins deux buts dans le match, toutes
--   équipes confondues).
-- * hat_trick_in_defeat — « Prêcher dans le désert » : marquer au moins trois
--   buts et perdre.
-- * lone_winning_goal — « Minimum syndical » : gagner 1-0 en marquant ce but.
-- * comeback_after_first_goal — « Rira bien qui rira le dernier » : encaisser
--   le premier but, n'en encaisser aucun autre et gagner ; tous les joueurs
--   présents le reçoivent.
-- * three_match_scoring_streak — « Jamais 2 sans 3 » : marquer lors de trois
--   matchs consécutifs d'AS Grinta.
-- * back_to_back_motm — « Doublé HDM » : être homme du match lors de deux
--   matchs consécutifs d'AS Grinta.
--
-- Les règles qui dépendent de l'ordre des buts exigent, comme la Remontada,
-- que chaque but du match soit saisi avec sa minute et que les buts saisis
-- correspondent au score final (toujours le cas avec le Live).
--
-- Les matchs « entre nous » n'ont pas de score adverse : seules les règles
-- goal_and_assist et one_two s'y appliquent. Pour les séries (trois matchs,
-- deux HDM), « consécutifs » compte les matchs terminés d'AS Grinta hors
-- matchs entre nous, toutes saisons confondues : un match manqué casse la
-- série, un match entre nous ne la casse pas.

-- ---------------------------------------------------------------------------
-- 1. Règles autorisées
-- ---------------------------------------------------------------------------

alter table public.badges
  drop constraint if exists badges_auto_rule_check;
alter table public.badges
  add constraint badges_auto_rule_check
  check (auto_rule is null or auto_rule in (
    'goal_and_assist', 'remontada', 'clutch',
    'one_two', 'first_and_last_goal', 'hat_trick_in_defeat',
    'lone_winning_goal', 'comeback_after_first_goal',
    'three_match_scoring_streak', 'back_to_back_motm'
  ));

comment on column public.badges.auto_rule is
  'Fait de match qui décerne ce badge automatiquement (voir private.profile_match_exploits). Nul pour un badge seulement manuel ou à barème.';

-- Les badges mystère existants, repérés par leur code de création. Une règle
-- déjà posée n'est pas écrasée.
update public.badges set auto_rule = 'one_two'
where code = 'custom_une_deux_1790776876558' and auto_rule is null;

update public.badges set auto_rule = 'first_and_last_goal'
where code = 'custom_la_boucle_est_boucl_e_1790777176295' and auto_rule is null;

update public.badges set auto_rule = 'hat_trick_in_defeat'
where code = 'custom_pr_cher_dans_le_d_sert_1790777232253' and auto_rule is null;

update public.badges set auto_rule = 'lone_winning_goal'
where code = 'custom_minimum_syndical_1790777345623' and auto_rule is null;

update public.badges set auto_rule = 'comeback_after_first_goal'
where code = 'custom_rira_bien_qui_rira_le_dernier_1790778180908' and auto_rule is null;

update public.badges set auto_rule = 'three_match_scoring_streak'
where code = 'custom_jamais_2_sans_3_1790777301116' and auto_rule is null;

update public.badges set auto_rule = 'back_to_back_motm'
where code = 'custom_doubl_hdm_1790772063214' and auto_rule is null;

-- ---------------------------------------------------------------------------
-- 2. Faits de match réalisés par une personne
-- ---------------------------------------------------------------------------
--
-- Les trois premières règles sont reprises à l'identique de 20260923230000.
-- public.recalculate_profile_badges décerne déjà tout badge dont la règle
-- figure ici : il n'a pas besoin d'être modifié.

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
  complete_matches as (
    -- Matchs contre un adversaire dont les buts saisis correspondent
    -- exactement au score final.
    select m.id as match_id, m.score_as_grinta, m.score_adverse,
      coalesce(m.planned_duration_minutes, 90) as planned_duration_minutes
    from public.matches m
    where m.id in (select played.match_id from played)
      and m.match_type is distinct from 'entre_nous'
      and (
        select count(*) from public.match_sport_goal_actions ga
        where ga.match_id = m.id and ga.team_side = 'as_grinta'
      ) = m.score_as_grinta
      and (
        select count(*) from public.match_sport_goal_actions ga
        where ga.match_id = m.id and ga.team_side = 'opponent'
      ) = m.score_adverse
  ),
  scored_matches as (
    -- Matchs complets gagnés.
    select complete_matches.match_id, complete_matches.score_as_grinta,
      complete_matches.score_adverse, complete_matches.planned_duration_minutes
    from complete_matches
    where complete_matches.score_as_grinta > complete_matches.score_adverse
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
  ordered_goals as (
    -- Tous les buts des matchs complets, dans l'ordre chronologique.
    select ga.match_id, ga.team_side, ga.scorer_participant_id,
      row_number() over (
        partition by ga.match_id order by ga.minute, ga.ordinal
      ) as goal_rank,
      count(*) over (partition by ga.match_id) as total_goals,
      count(*) filter (where ga.minute is null) over (
        partition by ga.match_id
      ) as unknown_minutes
    from public.match_sport_goal_actions ga
    where ga.match_id in (select complete_matches.match_id from complete_matches)
  ),
  team_sequence as (
    -- Matchs terminés d'AS Grinta hors matchs entre nous, numérotés dans
    -- l'ordre où ils ont été joués, toutes saisons confondues.
    select m.id as match_id,
      row_number() over (
        order by m.match_date, m.kickoff_at, m.id
      ) as seq
    from public.matches m
    where m.status in ('termine', 'archive')
      and m.match_type is distinct from 'entre_nous'
  ),
  scoring_seq as (
    select distinct team_sequence.seq, team_sequence.match_id
    from played
    join public.match_player_stats st
      on st.match_id = played.match_id
     and st.season_player_id = played.season_player_id
    join team_sequence on team_sequence.match_id = played.match_id
    where st.goals >= 1
  ),
  motm_seq as (
    select distinct team_sequence.seq, team_sequence.match_id
    from played
    join public.match_man_of_match mv
      on mv.match_id = played.match_id
     and mv.season_player_id = played.season_player_id
    join team_sequence on team_sequence.match_id = played.match_id
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

    -- Une-deux : il sert un coéquipier sur un but, ce coéquipier le sert
    -- sur un autre.
    select 'one_two', given.match_id
    from played
    join public.match_sport_participants me
      on me.match_id = played.match_id
     and me.season_player_id = played.season_player_id
    join public.match_sport_goal_actions given
      on given.match_id = played.match_id
     and given.assist_participant_id = me.id
    join public.match_sport_goal_actions received
      on received.match_id = given.match_id
     and received.scorer_participant_id = me.id
     and received.assist_participant_id = given.scorer_participant_id

    union

    -- La boucle est bouclée : premier et dernier buts du match.
    select 'first_and_last_goal', first_goal.match_id
    from ordered_goals first_goal
    join ordered_goals last_goal
      on last_goal.match_id = first_goal.match_id
     and last_goal.goal_rank = last_goal.total_goals
    join public.match_sport_participants participant
      on participant.id = first_goal.scorer_participant_id
    join played
      on played.match_id = first_goal.match_id
     and played.season_player_id = participant.season_player_id
    where first_goal.goal_rank = 1
      and first_goal.total_goals >= 2
      and first_goal.unknown_minutes = 0
      and first_goal.team_side = 'as_grinta'
      and last_goal.team_side = 'as_grinta'
      and last_goal.scorer_participant_id = first_goal.scorer_participant_id

    union

    -- Prêcher dans le désert : triplé et défaite.
    select 'hat_trick_in_defeat', played.match_id
    from played
    join public.match_player_stats st
      on st.match_id = played.match_id
     and st.season_player_id = played.season_player_id
    join public.matches m on m.id = played.match_id
    where st.goals >= 3
      and m.match_type is distinct from 'entre_nous'
      and m.score_as_grinta < m.score_adverse

    union

    -- Minimum syndical : victoire 1-0 et c'est lui qui a marqué.
    select 'lone_winning_goal', played.match_id
    from played
    join public.match_player_stats st
      on st.match_id = played.match_id
     and st.season_player_id = played.season_player_id
    join public.matches m on m.id = played.match_id
    where st.goals >= 1
      and m.match_type is distinct from 'entre_nous'
      and m.score_as_grinta = 1
      and m.score_adverse = 0

    union

    -- Rira bien qui rira le dernier : mené 0-1, seul but encaissé, victoire.
    select 'comeback_after_first_goal', played.match_id
    from played
    join scored_matches sm on sm.match_id = played.match_id
    join ordered_goals first_goal
      on first_goal.match_id = played.match_id
     and first_goal.goal_rank = 1
    where sm.score_adverse = 1
      and first_goal.team_side = 'opponent'
      and first_goal.unknown_minutes = 0

    union

    -- Jamais 2 sans 3 : il marque trois matchs de suite.
    select 'three_match_scoring_streak', streak3.match_id
    from scoring_seq streak1
    join scoring_seq streak2 on streak2.seq = streak1.seq + 1
    join scoring_seq streak3 on streak3.seq = streak1.seq + 2

    union

    -- Doublé HDM : homme du match deux matchs de suite.
    select 'back_to_back_motm', motm2.match_id
    from motm_seq motm1
    join motm_seq motm2 on motm2.seq = motm1.seq + 1
  )
  select exploits.rule, exploits.match_id, m.kickoff_at
  from exploits
  join public.matches m on m.id = exploits.match_id;
$function$;

alter function private.profile_match_exploits(uuid) owner to postgres;
revoke all on function private.profile_match_exploits(uuid)
  from public, anon, authenticated;
grant execute on function private.profile_match_exploits(uuid) to service_role;

comment on function private.profile_match_exploits(uuid) is
  'Faits de match réalisés par une personne (goal_and_assist, remontada, clutch, one_two, first_and_last_goal, hat_trick_in_defeat, lone_winning_goal, comeback_after_first_goal, three_match_scoring_streak, back_to_back_motm), avec le match concerné.';

-- ---------------------------------------------------------------------------
-- 3. Rattrapage des matchs déjà validés
-- ---------------------------------------------------------------------------

select public.recalculate_all_badges();

commit;
