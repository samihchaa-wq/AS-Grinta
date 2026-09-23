begin;

-- Badges mystère décernés automatiquement.
--
-- Trois badges mystère créés depuis l'administration décrivent un fait que
-- l'application enregistre déjà : ils sont désormais décernés tout seuls, par
-- le même recalcul que les autres badges (à la validation d'un match, à la
-- correction de son compte rendu, etc.). Rien n'est retiré : un badge gagné
-- le reste, et l'attribution manuelle reste possible, par exemple pour un
-- ancien match dont les minutes n'ont jamais été saisies.
--
-- * goal_and_assist — marquer et faire une passe décisive dans le même match.
-- * remontada — gagner un match après avoir été mené de deux buts ; tous les
--   joueurs présents le reçoivent. La chronologie n'est fiable que si chaque
--   but du match a sa minute (c'est toujours le cas avec le Live).
-- * clutch — marquer le but de la victoire à cinq minutes de la fin ou plus
--   tard. Le but de la victoire est celui qui donne à AS Grinta un but de
--   plus que le total final adverse ; il faut connaître la minute de tous les
--   buts d'AS Grinta pour savoir lequel c'est.
--
-- Les matchs « entre nous » n'ont pas de score adverse : seule la règle
-- goal_and_assist s'y applique, comme les triplés.

-- ---------------------------------------------------------------------------
-- 1. Règle automatique portée par le badge
-- ---------------------------------------------------------------------------

alter table public.badges
  add column if not exists auto_rule text;

alter table public.badges
  drop constraint if exists badges_auto_rule_check;
alter table public.badges
  add constraint badges_auto_rule_check
  check (auto_rule is null or auto_rule in ('goal_and_assist', 'remontada', 'clutch'));

comment on column public.badges.auto_rule is
  'Fait de match qui décerne ce badge automatiquement (goal_and_assist, remontada, clutch). Nul pour un badge seulement manuel ou à barème.';

-- Les badges mystère existants, repérés par leur code de création.
update public.badges
set auto_rule = 'goal_and_assist'
where code = 'custom_au_four_et_au_moulin_1790198470375';

update public.badges
set auto_rule = 'remontada'
where code = 'custom_remontada_1790198113800';

update public.badges
set auto_rule = 'clutch'
where code = 'custom_clutch_1790198314443';

-- ---------------------------------------------------------------------------
-- 2. Faits de match réalisés par une personne
-- ---------------------------------------------------------------------------

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
  'Faits de match (goal_and_assist, remontada, clutch) réalisés par une personne, avec le match concerné.';

-- ---------------------------------------------------------------------------
-- 3. Recalcul : les badges à règle s'ajoutent aux badges à barème
-- ---------------------------------------------------------------------------
--
-- Corps identique à 20260817101427 pour les badges à barème ; la seconde
-- boucle décerne les badges portant une règle, avec le premier match qui l'a
-- remplie dans le journal d'audit.

create or replace function public.recalculate_profile_badges(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v jsonb;
  b record;
  val integer;
  v_after jsonb;
begin
  if p_profile_id is null then
    return;
  end if;

  select to_jsonb(t)
  into v
  from private.profile_badge_metrics(p_profile_id) t;

  if v is null then
    return;
  end if;

  for b in
    select id, code, name, metric, threshold
    from public.badges
    where auto
      and kind = 'tier'
      and metric is not null
      and threshold is not null
  loop
    val := coalesce((v ->> b.metric)::int, 0);

    if val >= b.threshold then
      v_after := null;

      insert into public.profile_badges(profile_id, badge_id, source)
      values (p_profile_id, b.id, 'auto')
      on conflict (profile_id, badge_id) do nothing
      returning jsonb_build_object(
        'profile_id', profile_id,
        'badge_id', badge_id,
        'source', source,
        'awarded_by', awarded_by,
        'awarded_at', awarded_at
      ) into v_after;

      if v_after is not null then
        insert into private.profile_badge_audit_log (
          event_type, profile_id, badge_id, badge_code, badge_name,
          actor_profile_id, occurred_at, source, metadata,
          state_before, state_after
        )
        values (
          'award', p_profile_id, b.id, b.code, b.name,
          null, now(), 'auto',
          jsonb_build_object(
            'reason', 'metric_threshold_met',
            'metric', b.metric,
            'threshold', b.threshold,
            'value', val
          ),
          null, v_after
        );
      end if;
    end if;
  end loop;

  for b in
    select distinct on (badge.id)
      badge.id, badge.code, badge.name, badge.auto_rule, exploit.match_id
    from private.profile_match_exploits(p_profile_id) exploit
    join public.badges badge on badge.auto_rule = exploit.rule
    order by badge.id, exploit.kickoff_at, exploit.match_id
  loop
    v_after := null;

    insert into public.profile_badges(profile_id, badge_id, source)
    values (p_profile_id, b.id, 'auto')
    on conflict (profile_id, badge_id) do nothing
    returning jsonb_build_object(
      'profile_id', profile_id,
      'badge_id', badge_id,
      'source', source,
      'awarded_by', awarded_by,
      'awarded_at', awarded_at
    ) into v_after;

    if v_after is not null then
      insert into private.profile_badge_audit_log (
        event_type, profile_id, badge_id, badge_code, badge_name,
        actor_profile_id, occurred_at, source, metadata,
        state_before, state_after
      )
      values (
        'award', p_profile_id, b.id, b.code, b.name,
        null, now(), 'auto',
        jsonb_build_object(
          'reason', 'match_exploit',
          'rule', b.auto_rule,
          'match_id', b.match_id
        ),
        null, v_after
      );
    end if;
  end loop;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Rattrapage des matchs déjà validés
-- ---------------------------------------------------------------------------

select public.recalculate_all_badges();

commit;
