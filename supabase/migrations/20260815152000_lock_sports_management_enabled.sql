-- Sports management is now a permanent product capability.
-- Keep the existing RPC signature and response shape for compatibility with
-- older clients, but reject every application attempt to disable the module.
-- The private flag table remains inaccessible for direct authenticated writes.

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

create or replace function private.set_sports_management_enabled(
  p_enabled boolean,
  p_justification text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_config jsonb;
  v_updated_at timestamptz;
  v_justification text := nullif(btrim(p_justification), '');
begin
  if p_enabled is null then
    raise exception 'Feature flag value is required' using errcode = '22023';
  end if;

  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if v_justification is not null and char_length(v_justification) > 500 then
    raise exception 'Justification cannot exceed 500 characters'
      using errcode = '22023';
  end if;

  if p_enabled is not true then
    raise exception 'Sports-management module is permanently enabled'
      using errcode = '22023';
  end if;

  select f.config, f.updated_at
    into v_config, v_updated_at
  from private.app_feature_flags f
  where f.key = 'sports_management';

  if not found then
    raise exception 'Sports-management feature flag is missing'
      using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'sports_management',
    jsonb_build_object(
      'enabled', true,
      'config', v_config,
      'updated_at', v_updated_at,
      'changed', false
    )
  );
end;
$function$;
