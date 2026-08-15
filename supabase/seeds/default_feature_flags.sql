-- Canonical application settings for fresh/local installations only.
-- Keep operational production state out of this file: these are safe defaults.

insert into private.app_feature_flags (
  key,
  enabled,
  config,
  updated_at,
  updated_by
)
values
  (
    'sports_management',
    true,
    jsonb_build_object(
      'availability_open_hours_before', 144,
      'reminder_hours_before', jsonb_build_array(72, 24),
      'usual_squad_size', 14,
      'vote_duration_hours', 24,
      'timezone', 'Europe/Paris'
    ),
    now(),
    null
  ),
  (
    'notifications_paused',
    false,
    '{}'::jsonb,
    now(),
    null
  )
on conflict (key) do update
set config = excluded.config;
