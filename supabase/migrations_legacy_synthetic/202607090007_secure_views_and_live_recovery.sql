create or replace view public.v_match_prediction_points
with (security_invoker = true)
as
select
  mp.id,
  mp.match_id,
  mp.profile_id,
  case
    when not mp.is_filled then 0::numeric
    when sign(mp.predicted_score_as_grinta - mp.predicted_score_adverse)
       <> sign(m.score_as_grinta - m.score_adverse) then 0::numeric
    else
      case
        when m.score_as_grinta > m.score_adverse
          then mo.odds_victoire_as_grinta
        when m.score_as_grinta = m.score_adverse
          then mo.odds_nul
        else mo.odds_victoire_adverse
      end
      * case
          when mp.predicted_score_as_grinta = m.score_as_grinta
           and mp.predicted_score_adverse = m.score_adverse then 15
          else 10
        end
  end as points
from public.match_predictions mp
join public.matches m
  on m.id = mp.match_id
 and m.status in ('termine', 'archive')
join public.match_odds mo on mo.match_id = m.id;

alter view public.v_player_season_stats set (security_invoker = true);
alter view public.v_player_career_stats set (security_invoker = true);
alter view public.v_season_prediction_points set (security_invoker = true);
alter view public.v_classement_general set (security_invoker = true);

create or replace function public.mark_live_disconnected(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  update public.live_sessions
  set controller_disconnected_at = now(),
      updated_at = now()
  where match_id = p_match_id
    and controller_profile_id = auth.uid()
    and controller_session_id = p_controller_session_id;

  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

grant execute on function public.mark_live_disconnected(uuid, text)
to authenticated;
