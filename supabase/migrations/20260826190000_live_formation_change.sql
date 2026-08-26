-- Permet au coach de changer de dispositif pendant un Live sans fabriquer de
-- remplacement. Les positions et le formation_code sont écrits dans la même
-- transaction, sous le verrou optimiste déjà utilisé par le lineup Live.

begin;

create or replace function public.coach_change_match_live_formation(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_expected_lineup_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_formation_code text := nullif(btrim(p_formation_code), '');
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if v_formation_code is null or char_length(v_formation_code) > 32 then
    raise exception 'Invalid formation code' using errcode = '22023';
  end if;

  -- Ce helper verrouille match_live_sessions, vérifie coach/admin, refuse une
  -- révision obsolète et garantit qu'aucun passage terrain/banc non déclaré ne
  -- puisse être enregistré. Avec p_substitution = null, un changement de
  -- dispositif ne peut donc jamais créer un événement de remplacement.
  perform private.save_match_live_lineup_versioned(
    p_match_id,
    p_entries,
    null::jsonb,
    p_expected_lineup_revision
  );

  update public.match_compositions
  set formation_code = v_formation_code,
      last_modified_at = now(),
      last_modified_by = v_actor
  where match_id = p_match_id;

  if not found then
    raise exception 'Match composition not found' using errcode = 'P0002';
  end if;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

revoke all on function
  public.coach_change_match_live_formation(uuid, text, jsonb, integer)
  from public, anon;
grant execute on function
  public.coach_change_match_live_formation(uuid, text, jsonb, integer)
  to authenticated, service_role;

comment on function
  public.coach_change_match_live_formation(uuid, text, jsonb, integer)
is
  'Change atomiquement le dispositif et les positions du Live, sans événement de remplacement, avec contrôle de lineup_revision.';

commit;
