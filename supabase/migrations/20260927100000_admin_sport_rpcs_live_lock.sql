begin;

-- Verrou du Live sur les huit actions sportives d'administration.
--
-- En production, ces huit fonctions refusent toute modification dès
-- l'ouverture du Live (T-15) : le contrôle `private.assert_match_admin_edit_open`
-- suit immédiatement celui du rôle administrateur. Ce verrou avait été posé
-- directement sur la base, hors migration : le dépôt gardait les anciennes
-- versions, sans verrou. Une reconstruction de la base ou la prochaine
-- modification d'une de ces fonctions depuis le dépôt l'aurait donc fait
-- disparaître sans bruit.
--
-- Les définitions ci-dessous sont celles relevées en production le
-- 27 septembre 2026 avec `pg_get_functiondef` : mêmes signatures, mêmes
-- valeurs par défaut, `security definer`, `search_path` vide et mêmes droits.
-- En production, cette migration ne change donc rien.
--
-- `admin_save_match_effectif` ne pose pas le verrou elle-même : elle délègue à
-- `admin_publish_match_effectif`, qui le porte déjà.

create or replace function public.admin_add_or_reuse_match_guest(
  p_match_id uuid,
  p_guest_player_id uuid default null,
  p_first_name text default null,
  p_last_name text default null,
  p_is_goalkeeper boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);

  if p_guest_player_id is null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        lower(btrim(coalesce(p_first_name, ''))) || '|' ||
        lower(btrim(coalesce(p_last_name, ''))) || '|' ||
        coalesce(p_is_goalkeeper, false)::text,
        0
      )
    );
  end if;

  return private.add_or_reuse_match_guest(
    p_match_id, p_guest_player_id, p_first_name, p_last_name,
    p_is_goalkeeper, p_reason
  );
end;
$function$;

create or replace function public.admin_configure_match_sport_workflow(
  p_match_id uuid,
  p_squad_size_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.configure_match_sport_workflow(p_match_id, p_squad_size_limit);
end;
$function$;

create or replace function public.admin_override_match_availability(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_private_comment text default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.override_match_availability(
    p_match_id, p_season_player_id, p_status, p_private_comment, p_reason
  );
end;
$function$;

create or replace function public.admin_publish_match_convocations(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.publish_match_convocations(p_match_id, p_reason);
end;
$function$;

create or replace function public.admin_recompute_match_convocations(
  p_match_id uuid,
  p_reset_overrides boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.recompute_match_convocations_internal(p_match_id, p_reset_overrides);
end;
$function$;

create or replace function public.admin_save_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return public.admin_publish_match_effectif(
    p_match_id,
    p_squad_size_limit,
    p_decisions,
    p_reason
  );
end;
$function$;

create or replace function public.admin_set_match_convocation(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_turn_should_consume boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.set_match_convocation(
    p_match_id, p_season_player_id, p_status, p_turn_should_consume, p_reason
  );
end;
$function$;

create or replace function public.admin_sync_match_sport_workflow(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.sync_match_sport_workflow(p_match_id);
end;
$function$;

revoke all on function public.admin_add_or_reuse_match_guest(uuid, uuid, text, text, boolean, text) from public, anon;
grant execute on function public.admin_add_or_reuse_match_guest(uuid, uuid, text, text, boolean, text) to authenticated, service_role;
revoke all on function public.admin_configure_match_sport_workflow(uuid, integer) from public, anon;
grant execute on function public.admin_configure_match_sport_workflow(uuid, integer) to authenticated, service_role;
revoke all on function public.admin_override_match_availability(uuid, uuid, text, text, text) from public, anon;
grant execute on function public.admin_override_match_availability(uuid, uuid, text, text, text) to authenticated, service_role;
revoke all on function public.admin_publish_match_convocations(uuid, text) from public, anon;
grant execute on function public.admin_publish_match_convocations(uuid, text) to authenticated, service_role;
revoke all on function public.admin_recompute_match_convocations(uuid, boolean) from public, anon;
grant execute on function public.admin_recompute_match_convocations(uuid, boolean) to authenticated, service_role;
revoke all on function public.admin_save_match_effectif(uuid, integer, jsonb, text) from public, anon;
grant execute on function public.admin_save_match_effectif(uuid, integer, jsonb, text) to authenticated, service_role;
revoke all on function public.admin_set_match_convocation(uuid, uuid, text, boolean, text) from public, anon;
grant execute on function public.admin_set_match_convocation(uuid, uuid, text, boolean, text) to authenticated, service_role;
revoke all on function public.admin_sync_match_sport_workflow(uuid) from public, anon;
grant execute on function public.admin_sync_match_sport_workflow(uuid) to authenticated, service_role;

commit;
