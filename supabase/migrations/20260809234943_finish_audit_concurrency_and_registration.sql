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
set search_path = ''
as $function$
begin
  -- Quand on crée/recherche un invité par identité, sérialiser les requêtes
  -- concurrentes portant sur la même personne. La seconde requête attend la
  -- première puis réutilise l'entrée créée au lieu d'échouer sur l'unicité.
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
    p_match_id,
    p_guest_player_id,
    p_first_name,
    p_last_name,
    p_is_goalkeeper,
    p_reason
  );
end;
$function$;

create or replace function public.consume_registration_rate_limit(
  p_origin_hash text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_origin_hour integer;
  v_origin_day integer;
begin
  if p_origin_hash is null or p_origin_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid origin hash' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_origin_hash, 0)
  );

  delete from private.registration_attempts
  where attempted_at < now() - interval '24 hours';

  select count(*)::integer
  into v_origin_hour
  from private.registration_attempts
  where origin_hash = p_origin_hash
    and attempted_at >= now() - interval '1 hour';

  select count(*)::integer
  into v_origin_day
  from private.registration_attempts
  where origin_hash = p_origin_hash
    and attempted_at >= now() - interval '24 hours';

  -- Le plafond reste strict par origine (5/h, 15/j), mais il n'existe plus
  -- de quota global partagé : une attaque distribuée ne peut donc plus
  -- épuiser un compteur commun et bloquer les inscriptions légitimes.
  if v_origin_hour >= 5 or v_origin_day >= 15 then
    return false;
  end if;

  insert into private.registration_attempts(origin_hash)
  values (p_origin_hash);

  return true;
end;
$function$;

revoke execute on function public.admin_add_or_reuse_match_guest(uuid, uuid, text, text, boolean, text)
  from public, anon;
grant execute on function public.admin_add_or_reuse_match_guest(uuid, uuid, text, text, boolean, text)
  to authenticated, service_role;

revoke execute on function public.consume_registration_rate_limit(text)
  from public, anon, authenticated;
grant execute on function public.consume_registration_rate_limit(text)
  to service_role;
