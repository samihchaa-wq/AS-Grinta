-- Ensure season-prediction awards are always computed from the same final
-- roster snapshot that backs the archived leaderboards.
--
-- PostgreSQL fires same-kind triggers in name order. Historically
-- trg_award_titles ran before trg_sync_season_prediction_roster_snapshot on an
-- archive update, so award_season_titles() could temporarily see the legacy
-- fallback roster and permanently award the wrong predictor before the final
-- active roster was captured.
--
-- Make the award path self-sufficient instead of relying on trigger ordering:
-- the archive transition now guarantees the snapshot exists in the same
-- transaction before any title calculation starts.

create or replace function private.ensure_season_prediction_roster_snapshot(
  p_season_id uuid,
  p_reason text,
  p_captured_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_created boolean;
begin
  if p_reason not in ('lock', 'archive') then
    raise exception 'Invalid season prediction roster capture reason'
      using errcode = '22023';
  end if;

  insert into public.season_prediction_roster_captures(
    season_id,
    captured_at,
    capture_reason
  )
  values (
    p_season_id,
    coalesce(p_captured_at, now()),
    p_reason
  )
  on conflict (season_id) do nothing
  returning true into v_created;

  if coalesce(v_created, false) then
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
      and player.is_active;
  end if;
end;
$function$;

revoke execute on function private.ensure_season_prediction_roster_snapshot(
  uuid,
  text,
  timestamptz
) from public, anon, authenticated;

create or replace function public.trg_award_titles_on_season_close()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $function$
begin
  if new.status = 'archived'
     and (
       tg_op = 'INSERT'
       or new.status is distinct from old.status
     )
  then
    perform private.ensure_season_prediction_roster_snapshot(
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
