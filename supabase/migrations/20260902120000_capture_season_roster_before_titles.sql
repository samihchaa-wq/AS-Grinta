-- Freeze the season-prediction roster BEFORE the season titles are computed.
--
-- public.seasons carries two AFTER ROW triggers that both matter when a season
-- is archived:
--   * trg_award_titles                            -> public.award_season_titles()
--   * trg_sync_season_prediction_roster_snapshot  -> roster capture
-- PostgreSQL fires AFTER ROW triggers in alphabetical order, so the titles were
-- always computed first. When a season was archived without ever being
-- prediction-locked (the "Finir la saison" button, and the implicit archive done
-- by set_season_status/open_or_create_season when another season is opened) no
-- roster capture existed yet at that point.
--
-- v_season_prediction_points and v_season_prediction_bonus then fell back to the
-- raw public.season_players list, which still contains coaches and inactive
-- players, while save_my_season_predictions only ever accepts the active
-- non-coach roster. expected_count was therefore strictly greater than any
-- predictor's filled_count, no predictor was eligible, and both
-- 'best_pred_player' and 'best_pred_overall' were awarded on an empty season
-- prediction ranking. The capture created microseconds later by the second
-- trigger made the leaderboard show a winner that never received the title, and
-- public.season_awards is insert-once so the miss was permanent.
--
-- The capture is now an idempotent helper called by the title trigger itself,
-- so the outcome no longer depends on trigger naming.

create or replace function private.capture_season_prediction_roster(
  p_season_id uuid,
  p_reason text,
  p_captured_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
begin
  insert into public.season_prediction_roster_captures(
    season_id,
    captured_at,
    capture_reason
  ) values (
    p_season_id,
    coalesce(p_captured_at, now()),
    p_reason
  )
  on conflict (season_id) do nothing;

  -- A capture already existed: the historical contract wins, never recapture.
  if not found then
    return false;
  end if;

  insert into public.season_prediction_roster_members(
    season_id,
    season_player_id,
    category
  )
  select
    player.season_id,
    player.id,
    case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
  from public.season_players player
  where player.season_id = p_season_id
    and player.is_active
    and not player.is_coach
  on conflict (season_id, season_player_id) do nothing;

  return true;
end;
$function$;

revoke execute on function private.capture_season_prediction_roster(
  uuid, text, timestamptz
) from public, anon, authenticated;

create or replace function private.sync_season_prediction_roster_snapshot()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if old.season_predictions_locked_at is not null
     and new.season_predictions_locked_at is null then
    if private.season_prediction_lock_is_committed(new.id) then
      raise exception 'Les pronostics de saison révélés sont définitivement figés.'
        using errcode = '22023';
    end if;
    delete from public.season_prediction_roster_captures
    where season_id = new.id;
    return new;
  end if;

  if old.season_predictions_locked_at is null
     and new.season_predictions_locked_at is not null then
    perform private.capture_season_prediction_roster(
      new.id,
      'lock',
      new.season_predictions_locked_at
    );
    return new;
  end if;

  if old.status is distinct from 'archived'
     and new.status = 'archived' then
    perform private.capture_season_prediction_roster(new.id, 'archive', now());
  end if;

  return new;
end;
$function$;

create or replace function public.trg_award_titles_on_season_close()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.status = 'archived'
     and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    -- Idempotent: a season locked before archiving keeps its 'lock' capture.
    perform private.capture_season_prediction_roster(
      new.id,
      case
        when new.season_predictions_locked_at is not null then 'lock'
        else 'archive'
      end,
      coalesce(new.season_predictions_locked_at, now())
    );
    perform public.award_season_titles(new.id);
  end if;
  return null;
end;
$function$;

revoke execute on function public.trg_award_titles_on_season_close()
  from public, anon, authenticated;
