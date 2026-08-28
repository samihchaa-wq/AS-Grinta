begin;

-- Reprise de l'historique : reconstruire les faits du match des comptes rendus
-- déjà validés.
--
-- Deux sources, dans cet ordre :
--   1. le journal du Live, quand il existe **et** qu'il concorde exactement
--      avec le score retenu : le lien but -> buteur -> passeur est alors réel ;
--   2. sinon les compteurs agrégés : on sait combien de buts et qui les a
--      marqués, jamais quel passeur allait avec quel but.
--
-- Rien n'est inventé : un lien qu'on ne peut pas reconstruire reste « non
-- attribué ». Les matchs importés sans validation moderne ne sont pas repris :
-- leurs statistiques restent dans les compteurs, et leur fenêtre de correction
-- est de toute façon fermée.

do $backfill$
declare
  v_match record;
  v_live_us integer;
  v_live_them integer;
  v_ordinal integer;
begin
  for v_match in
    select
      finalization.match_id,
      finalization.score_as_grinta,
      finalization.score_adverse
    from public.match_sport_finalizations finalization
    where not exists (
      select 1
      from public.match_sport_goal_actions action
      where action.match_id = finalization.match_id
    )
  loop
    select
      count(*) filter (where event.event_type = 'goal_us'),
      count(*) filter (where event.event_type = 'goal_them')
    into v_live_us, v_live_them
    from public.match_live_events event
    where event.match_id = v_match.match_id;

    if v_live_us = v_match.score_as_grinta
       and v_live_them = v_match.score_adverse
       and (v_live_us + v_live_them) > 0 then
      -- Source 1 : le journal du Live porte le lien exact.
      insert into public.match_sport_goal_actions(
        match_id, ordinal, minute, team_side, scorer_participant_id,
        assist_participant_id, assist_kind, is_own_goal, source, source_live_event_id
      )
      select
        v_match.match_id,
        (row_number() over (order by event.created_at, event.id) - 1)::integer,
        -- Les arrêts de jeu ne sont pas modélisés : une 93ᵉ minute suivie en
        -- direct est ramenée à 90.
        least(greatest(event.minute, 0), 90)::smallint,
        case when event.event_type = 'goal_us' then 'as_grinta' else 'opponent' end,
        case
          when event.event_type <> 'goal_us' then null
          when coalesce(scorer.final_presence_status, 'pending') <> 'present' then null
          else event.scorer_participant_id
        end,
        case
          when event.event_type <> 'goal_us' then null
          when coalesce(scorer.final_presence_status, 'pending') <> 'present' then null
          when coalesce(assist.final_presence_status, 'pending') <> 'present' then null
          else event.assist_participant_id
        end,
        case
          when event.event_type <> 'goal_us'
            or coalesce(event.is_opponent_own_goal, false) then 'none'
          when coalesce(scorer.final_presence_status, 'pending') <> 'present' then 'unknown'
          when coalesce(assist.final_presence_status, 'pending') <> 'present' then 'unknown'
          when event.assist_participant_id is not null then 'player'
          -- Le Live ne distinguait pas « aucune passe » de « passe oubliée » :
          -- on ne tranche pas à sa place.
          else 'unknown'
        end,
        event.event_type = 'goal_us' and coalesce(event.is_opponent_own_goal, false),
        'live',
        event.id
      from public.match_live_events event
      left join public.match_sport_participants scorer
        on scorer.id = event.scorer_participant_id
      left join public.match_sport_participants assist
        on assist.id = event.assist_participant_id
      where event.match_id = v_match.match_id
        and event.event_type in ('goal_us', 'goal_them');
      continue;
    end if;

    if v_match.score_as_grinta + v_match.score_adverse = 0 then
      continue;
    end if;

    -- Source 2 : compteurs agrégés. Le buteur est reconstructible, le passeur
    -- non : il reste « non attribué » plutôt que rattaché au hasard.
    v_ordinal := 0;

    insert into public.match_sport_goal_actions(
      match_id, ordinal, minute, team_side, scorer_participant_id,
      assist_participant_id, assist_kind, is_own_goal, source
    )
    select
      v_match.match_id,
      (row_number() over (order by scored.participant_id, scored.goal_index) - 1)::integer,
      null,
      'as_grinta',
      scored.participant_id,
      null,
      'unknown',
      false,
      'legacy'
    from (
      select participant.id as participant_id, goal_index
      from public.match_sport_participants participant
      cross join lateral generate_series(1, participant.final_goals) as goal_index
      where participant.match_id = v_match.match_id
        and participant.final_goals > 0
        and participant.final_presence_status = 'present'
    ) scored;

    select coalesce(max(action.ordinal) + 1, 0)
    into v_ordinal
    from public.match_sport_goal_actions action
    where action.match_id = v_match.match_id;

    -- Buts d'AS Grinta que les compteurs n'attribuent à personne.
    insert into public.match_sport_goal_actions(
      match_id, ordinal, minute, team_side, assist_kind, is_own_goal, source
    )
    select v_match.match_id, v_ordinal + offset_index - 1, null, 'as_grinta',
           'unknown', false, 'legacy'
    from generate_series(1, greatest(v_match.score_as_grinta - v_ordinal, 0)) as offset_index;

    select coalesce(max(action.ordinal) + 1, 0)
    into v_ordinal
    from public.match_sport_goal_actions action
    where action.match_id = v_match.match_id;

    insert into public.match_sport_goal_actions(
      match_id, ordinal, minute, team_side, assist_kind, is_own_goal, source
    )
    select v_match.match_id, v_ordinal + offset_index - 1, null, 'opponent',
           'none', false, 'legacy'
    from generate_series(1, v_match.score_adverse) as offset_index;
  end loop;
end;
$backfill$;

commit;
