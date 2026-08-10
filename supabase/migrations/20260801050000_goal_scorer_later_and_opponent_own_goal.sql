alter table public.match_live_events
  add column if not exists is_opponent_own_goal boolean not null default false;

alter table public.match_live_events
  drop constraint if exists match_live_events_check;

alter table public.match_live_events
  add constraint match_live_events_check check (
    (
      event_type = 'goal_us'
      and score_as_grinta_after is not null
      and score_adverse_after is null
      and player_in_participant_id is null
      and player_out_participant_id is null
      and not (is_opponent_own_goal and scorer_participant_id is not null)
    )
    or (
      event_type = 'goal_them'
      and score_adverse_after is not null
      and score_as_grinta_after is null
      and scorer_participant_id is null
      and player_in_participant_id is null
      and player_out_participant_id is null
      and not is_opponent_own_goal
    )
    or (
      event_type = 'substitution'
      and player_in_participant_id is not null
      and player_out_participant_id is not null
      and scorer_participant_id is null
      and score_as_grinta_after is null
      and score_adverse_after is null
      and not is_opponent_own_goal
    )
  );;
