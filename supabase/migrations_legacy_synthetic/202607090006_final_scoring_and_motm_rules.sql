drop function if exists public.finalize_match(uuid, integer, integer, uuid);

create function public.finalize_match(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_motm_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin role required';
  end if;

  if p_motm_profile_id is null then
    raise exception 'MOTM is required';
  end if;

  if p_score_as_grinta < 0 or p_score_as_grinta > 99
     or p_score_adverse < 0 or p_score_adverse > 99 then
    raise exception 'Invalid score';
  end if;

  if not exists (
    select 1
    from public.match_participants
    where match_id = p_match_id
      and profile_id = p_motm_profile_id
  ) then
    raise exception 'MOTM must be a match participant';
  end if;

  if p_score_as_grinta <> (
       select count(*) from public.goals
       where match_id = p_match_id and team = 'as_grinta'
     )
     or p_score_adverse <> (
       select count(*) from public.goals
       where match_id = p_match_id and team = 'adverse'
     ) then
    raise exception 'Score does not match recorded goals';
  end if;

  update public.matches
  set score_as_grinta = p_score_as_grinta,
      score_adverse = p_score_adverse,
      status = 'termine',
      updated_at = now()
  where id = p_match_id
    and status <> 'archive';

  if not found then return false; end if;

  update public.live_sessions
  set status = 'finished',
      controller_profile_id = null,
      controller_session_id = null,
      controller_disconnected_at = null,
      clock_started_at = null,
      updated_at = now()
  where match_id = p_match_id;

  delete from public.match_motm where match_id = p_match_id;

  insert into public.match_motm(match_id, profile_id, created_by)
  values (p_match_id, p_motm_profile_id, auth.uid());

  return true;
end;
$$;

grant execute on function public.finalize_match(uuid, integer, integer, uuid)
to authenticated;

create or replace view public.v_season_prediction_points as
select
  sp.id,
  sp.season_id,
  sp.predictor_profile_id,
  sp.player_profile_id,
  sp.category,
  case
    when not sp.is_filled then 0
    when stats.matches_played = 0 then 0
    when s.status = 'archived' and stats.matches_played < 3 then 0
    else round(
      greatest(
        0,
        1 - abs(
          case sp.category
            when 'buts' then stats.goals
            when 'passes' then stats.assists
            when 'hommes_du_match' then stats.motm
            when 'clean_sheets' then stats.clean_sheets
            else 0
          end
          - (sp.predicted_value_20 * stats.matches_played / 20.0)
        ) / greatest(sp.predicted_value_20 * stats.matches_played / 20.0, 1)
      ) * 20
    )::integer
  end as points
from public.season_predictions sp
join public.v_player_season_stats stats
  on stats.season_id = sp.season_id
 and stats.profile_id = sp.player_profile_id
join public.seasons s on s.id = sp.season_id;

grant select on public.v_season_prediction_points to authenticated;
