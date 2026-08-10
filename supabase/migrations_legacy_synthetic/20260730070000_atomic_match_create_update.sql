-- La création/modification d'un match enchaînait jusqu'à 4 appels RPC
-- séparés (match+cotes, adresse, type, maillot) sans transaction commune :
-- une coupure réseau entre deux appels laissait un match partiellement
-- enregistré tout en affichant une erreur, exposant à un doublon en cas de
-- nouvelle tentative. Ces deux fonctions regroupent l'ensemble en un seul
-- appel, donc une seule transaction Postgres.
create or replace function public.admin_create_match_complete(
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_squad_size_limit integer default null,
  p_address text default null,
  p_remember_address_as_default boolean default false,
  p_match_type text default 'championnat',
  p_jersey_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match_id uuid;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_squad_size_limit is not null then
    v_match_id := private.create_match_with_sport_limit(
      p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_win, p_draw, p_loss, p_squad_size_limit
    );
  else
    v_match_id := public.create_match_with_odds(
      p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_win, p_draw, p_loss
    );
  end if;

  perform public.admin_set_match_address(
    v_match_id, p_address, p_remember_address_as_default
  );
  perform public.admin_set_match_type(v_match_id, p_match_type);
  perform public.admin_set_match_jersey(v_match_id, p_jersey_note);

  return v_match_id;
end;
$function$;

create or replace function public.admin_update_match_complete(
  p_match_id uuid,
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_status text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_squad_size_limit integer default null,
  p_address text default null,
  p_remember_address_as_default boolean default false,
  p_match_type text default 'championnat',
  p_jersey_note text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_squad_size_limit is not null then
    perform private.update_match_with_sport_limit(
      p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_status, p_win, p_draw, p_loss, p_squad_size_limit
    );
  else
    perform public.update_match_with_odds(
      p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_status, p_win, p_draw, p_loss
    );
  end if;

  perform public.admin_set_match_address(
    p_match_id, p_address, p_remember_address_as_default
  );
  perform public.admin_set_match_type(p_match_id, p_match_type);
  perform public.admin_set_match_jersey(p_match_id, p_jersey_note);

  return true;
end;
$function$;

revoke all on function public.admin_create_match_complete(
  uuid, uuid, date, time without time zone, text, numeric, numeric, numeric,
  integer, text, boolean, text, text
) from public, anon;
revoke all on function public.admin_update_match_complete(
  uuid, uuid, uuid, date, time without time zone, text, text, numeric,
  numeric, numeric, integer, text, boolean, text, text
) from public, anon;

grant execute on function public.admin_create_match_complete(
  uuid, uuid, date, time without time zone, text, numeric, numeric, numeric,
  integer, text, boolean, text, text
) to authenticated;
grant execute on function public.admin_update_match_complete(
  uuid, uuid, uuid, date, time without time zone, text, text, numeric,
  numeric, numeric, integer, text, boolean, text, text
) to authenticated;

comment on function public.admin_create_match_complete(
  uuid, uuid, date, time without time zone, text, numeric, numeric, numeric,
  integer, text, boolean, text, text
) is 'Crée un match, ses cotes, son adresse, son type et son maillot en une seule transaction.';
comment on function public.admin_update_match_complete(
  uuid, uuid, uuid, date, time without time zone, text, text, numeric,
  numeric, numeric, integer, text, boolean, text, text
) is 'Met à jour un match, ses cotes, son adresse, son type et son maillot en une seule transaction.';
