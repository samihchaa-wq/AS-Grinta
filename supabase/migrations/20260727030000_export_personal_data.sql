begin;

create or replace function public.export_my_personal_data()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_profile_id uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_profile_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.profiles where id = v_profile_id) then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'exported_at', now(),
    'profile', (
      select jsonb_build_object(
        'id', profile.id,
        'username', profile.username,
        'first_name', profile.first_name,
        'last_name', profile.last_name,
        'surnom', profile.surnom,
        'photo_url', profile.photo_url,
        'role', profile.role,
        'status', profile.status,
        'is_goalkeeper', profile.is_goalkeeper,
        'notify_match_reminders', profile.notify_match_reminders,
        'notify_prediction_reminders', profile.notify_prediction_reminders,
        'notify_prediction_open', profile.notify_prediction_open,
        'created_at', profile.created_at,
        'updated_at', profile.updated_at
      )
      from public.profiles profile
      where profile.id = v_profile_id
    ),
    'roster_memberships', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', player.id,
          'season_id', player.season_id,
          'first_name', player.first_name,
          'last_name', player.last_name,
          'is_goalkeeper', player.is_goalkeeper,
          'is_coach', player.is_coach,
          'is_active', player.is_active,
          'joined_at', player.joined_at
        ) order by player.joined_at, player.id
      )
      from public.season_players player
      where player.profile_id = v_profile_id
    ), '[]'::jsonb),
    'match_predictions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', prediction.id,
          'match_id', prediction.match_id,
          'predicted_score_as_grinta', prediction.predicted_score_as_grinta,
          'predicted_score_adverse', prediction.predicted_score_adverse,
          'is_filled', prediction.is_filled,
          'use_x2', prediction.use_x2,
          'created_at', prediction.created_at,
          'updated_at', prediction.updated_at
        ) order by prediction.created_at, prediction.id
      )
      from public.match_predictions prediction
      where prediction.profile_id = v_profile_id
    ), '[]'::jsonb),
    'season_predictions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', prediction.id,
          'season_id', prediction.season_id,
          'season_player_id', prediction.season_player_id,
          'category', prediction.category,
          'predicted_value_30', prediction.predicted_value_30,
          'is_filled', prediction.is_filled,
          'created_at', prediction.created_at,
          'updated_at', prediction.updated_at
        ) order by prediction.created_at, prediction.id
      )
      from public.season_predictions prediction
      where prediction.predictor_profile_id = v_profile_id
    ), '[]'::jsonb),
    'badges', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'badge_id', profile_badge.badge_id,
          'source', profile_badge.source,
          'featured', profile_badge.featured,
          'awarded_at', profile_badge.awarded_at
        ) order by profile_badge.awarded_at, profile_badge.badge_id
      )
      from public.profile_badges profile_badge
      where profile_badge.profile_id = v_profile_id
    ), '[]'::jsonb),
    'attendance', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'match_id', attendance.match_id,
          'season_player_id', attendance.season_player_id,
          'created_at', attendance.created_at
        ) order by attendance.created_at, attendance.match_id
      )
      from public.match_attendance attendance
      join public.season_players player on player.id = attendance.season_player_id
      where player.profile_id = v_profile_id
    ), '[]'::jsonb),
    'man_of_match_awards', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'match_id', award.match_id,
          'season_player_id', award.season_player_id,
          'created_at', award.created_at
        ) order by award.created_at, award.match_id
      )
      from public.match_man_of_match award
      join public.season_players player on player.id = award.season_player_id
      where player.profile_id = v_profile_id
    ), '[]'::jsonb),
    'motm_ballots', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'match_id', vote.match_id,
          'candidate_participant_id', vote.candidate_participant_id,
          'finalization_version', vote.finalization_version,
          'cast_at', vote.cast_at
        ) order by vote.cast_at, vote.match_id
      )
      from public.match_sport_motm_votes vote
      where vote.voter_profile_id = v_profile_id
    ), '[]'::jsonb),
    'notification_devices', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', subscription.id,
          'user_agent', subscription.user_agent,
          'created_at', subscription.created_at,
          'updated_at', subscription.updated_at
        ) order by subscription.created_at, subscription.id
      )
      from public.push_subscriptions subscription
      where subscription.profile_id = v_profile_id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

revoke all on function public.export_my_personal_data() from public, anon;
grant execute on function public.export_my_personal_data()
  to authenticated, service_role;

comment on function public.export_my_personal_data() is
  'Exporte les données personnelles du profil authentifié sans secret de notification ni donnée d’un autre utilisateur.';

commit;
