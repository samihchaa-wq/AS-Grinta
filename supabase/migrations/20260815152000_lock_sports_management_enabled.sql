-- Sports management is now a permanent product capability.
-- Keep the existing RPC signature for compatibility with older clients,
-- but reject every attempt to disable the module.

insert into private.app_feature_flags (
  key,
  enabled,
  config,
  updated_at,
  updated_by
)
values (
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
)
on conflict (key) do nothing;

update private.app_feature_flags
set enabled = true,
    updated_at = now()
where key = 'sports_management'
  and enabled is distinct from true;

alter table private.app_feature_flags
  drop constraint if exists app_feature_flags_sports_management_always_enabled;

alter table private.app_feature_flags
  add constraint app_feature_flags_sports_management_always_enabled
  check (key <> 'sports_management' or enabled is true);

create or replace function private.set_sports_management_enabled(
  p_enabled boolean,
  p_justification text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'private', 'public', 'pg_temp'
as $function$
declare
  v_config jsonb;
  v_updated_at timestamptz;
  v_updated_by uuid;
begin
  perform private.assert_admin();

  if p_enabled is not true then
    raise exception 'Sports-management module is permanently enabled'
      using errcode = '22023';
  end if;

  select aff.config, aff.updated_at, aff.updated_by
    into v_config, v_updated_at, v_updated_by
  from private.app_feature_flags aff
  where aff.key = 'sports_management';

  if not found then
    raise exception 'Sports-management feature flag is missing';
  end if;

  return jsonb_build_object(
    'key', 'sports_management',
    'enabled', true,
    'config', v_config,
    'updated_at', v_updated_at,
    'updated_by', v_updated_by,
    'changed', false
  );
end;
$function$;
