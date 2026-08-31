-- Make the shared pre-match admin guard fail closed and use it for effectif publication.

create or replace function private.assert_match_admin_edit_open(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select
    m.status,
    coalesce(
      m.kickoff_at,
      ((m.match_date + m.match_time) at time zone 'Europe/Paris')
    )
  into v_status, v_kickoff_at
  from public.matches m
  where m.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'Un match passé ou annulé ne se modifie plus.' using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Horaire du match introuvable : modification refusée.' using errcode = '22023';
  end if;
  if now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'Le match est verrouillé depuis l’ouverture du Live.' using errcode = '22023';
  end if;
end;
$function$;

create or replace function public.admin_publish_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null::text
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
  return private.publish_match_effectif(
    p_match_id,
    p_squad_size_limit,
    p_decisions,
    p_reason
  );
end;
$function$;
