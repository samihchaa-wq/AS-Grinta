begin;

-- « Triplé Chrono » est décerné automatiquement.
--
-- Ce badge mystère (« Marquer un triplé en une mi-temps ») était jusqu'ici
-- attribué à la main. Comme les autres badges à règle, il est désormais
-- décerné par le recalcul qui suit la validation d'un match ou la correction
-- de son compte rendu. Rien n'est retiré : un badge gagné le reste, et
-- l'attribution manuelle reste possible.
--
-- * hat_trick_in_half — marquer au moins trois buts dans la même mi-temps.
--
-- La mi-temps de chaque but est celle que le Live a enregistrée. Pour un but
-- saisi à la main dans le compte rendu, dont la minute a été corrigée après le
-- Live ou dont le journal Live a été supprimé, elle se déduit de la minute :
-- jusqu'à la moitié du temps de jeu
-- prévu, c'est la première mi-temps ; les arrêts de jeu de la première
-- mi-temps se saisissent à la minute de la pause (45 pour 90 minutes). Un but
-- sans minute ne peut pas être placé et ne compte pas. Les contre-son-camp
-- adverses ne sont attribués à personne. Comme les triplés, la règle vaut
-- aussi pour les matchs « entre nous ».

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
    'three_match_scoring_streak', 'back_to_back_motm',
    'hat_trick_in_half'
  ));

-- Le badge mystère existant, repéré par son code de création. Une règle déjà
-- posée n'est pas écrasée.
update public.badges set auto_rule = 'hat_trick_in_half'
where code = 'custom_tripl_chrono_1790937793669' and auto_rule is null;

-- ---------------------------------------------------------------------------
-- 2. Faits de match réalisés par une personne
-- ---------------------------------------------------------------------------
--
-- Les dix règles existantes sont reprises à l'identique de 20260930150000.
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
  half_goals as (
    -- Buts d'AS Grinta attribués à un joueur, avec leur mi-temps : celle que
    -- le Live a notée quand le but en vient et que sa minute n'a pas été
    -- corrigée depuis, sinon celle que donne la minute (jusqu'à la moitié du
    -- temps de jeu prévu : première mi-temps). Un but sans minute n'a pas de
    -- mi-temps connue et ne compte pas.
    select ga.match_id, ga.scorer_participant_id,
      coalesce(
        case
          when ga.minute = least(greatest(live_event.minute, 0), 90)
          then live_event.half
        end,
        case
          when ga.minute is null then null
          when ga.minute * 2 <= coalesce(m.planned_duration_minutes, 90) then 1
          else 2
        end
      ) as half
    from public.match_sport_goal_actions ga
    join public.matches m on m.id = ga.match_id
    left join public.match_live_events live_event
      on live_event.id = ga.source_live_event_id
    where ga.team_side = 'as_grinta'
      and not ga.is_own_goal
      and ga.scorer_participant_id is not null
      and ga.match_id in (select played.match_id from played)
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

    union

    -- Triplé Chrono : trois buts ou plus dans la même mi-temps.
    select 'hat_trick_in_half', half_goal.match_id
    from half_goals half_goal
    join public.match_sport_participants participant
      on participant.id = half_goal.scorer_participant_id
    join played
      on played.match_id = half_goal.match_id
     and played.season_player_id = participant.season_player_id
    where half_goal.half is not null
    group by half_goal.match_id, half_goal.scorer_participant_id,
      half_goal.half
    having count(*) >= 3
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
  'Faits de match réalisés par une personne (goal_and_assist, remontada, clutch, one_two, first_and_last_goal, hat_trick_in_defeat, lone_winning_goal, comeback_after_first_goal, three_match_scoring_streak, back_to_back_motm, hat_trick_in_half), avec le match concerné.';

-- ---------------------------------------------------------------------------
-- 3. Rattrapage des matchs déjà validés
-- ---------------------------------------------------------------------------

select public.recalculate_all_badges();

commit;
