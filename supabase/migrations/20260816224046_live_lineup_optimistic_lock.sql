-- Empêche deux coachs de s'écraser silencieusement la composition Live.
--
-- Le snapshot Live expose déjà match_live_sessions.lineup_revision. La
-- nouvelle signature publique exige la révision que l'écran a réellement
-- utilisée pour construire son payload. La ligne de session est verrouillée
-- avant comparaison : deux sauvegardes concurrentes sont sérialisées et la
-- seconde est refusée si la première a déjà avancé la révision.
--
-- La signature historique à trois paramètres est conservée temporairement
-- pour permettre un déploiement sans rupture des PWA encore en cache. Elle
-- sera retirée après validation du Web utilisant la signature versionnée.

begin;

create or replace function private.save_match_live_lineup_versioned(
  p_match_id uuid,
  p_entries jsonb,
  p_substitution jsonb,
  p_expected_lineup_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_revision integer;
begin
  perform private.require_sports_management_enabled();

  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  if p_expected_lineup_revision is null or p_expected_lineup_revision < 0 then
    raise exception 'Expected lineup revision is required' using errcode = '22023';
  end if;

  select session.lineup_revision
  into v_current_revision
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    raise exception 'Live session not found' using errcode = 'P0002';
  end if;

  if v_current_revision is distinct from p_expected_lineup_revision then
    raise exception
      'La composition Live a été modifiée par un autre coach. Recharge l''état avant d''enregistrer.'
      using errcode = '40001';
  end if;

  -- private.save_match_live_lineup verrouille à nouveau la même ligne dans la
  -- même transaction, puis incrémente lineup_revision après l'écriture. Le
  -- verrou pris ci-dessus reste détenu jusqu'à la fin : aucune autre sauvegarde
  -- ne peut s'intercaler entre la comparaison et le remplacement du lineup.
  return private.save_match_live_lineup(
    p_match_id,
    p_entries,
    p_substitution
  );
end;
$function$;

revoke all on function
  private.save_match_live_lineup_versioned(uuid, jsonb, jsonb, integer)
  from public, anon, authenticated;

comment on function
  private.save_match_live_lineup_versioned(uuid, jsonb, jsonb, integer)
is
  'Sauvegarde une composition Live sous verrou et refuse en 40001 toute révision obsolète.';

create or replace function public.coach_save_match_live_lineup(
  p_match_id uuid,
  p_entries jsonb,
  p_substitution jsonb,
  p_expected_lineup_revision integer
)
returns jsonb
language sql
set search_path = ''
as $function$
  select private.save_match_live_lineup_versioned(
    p_match_id,
    p_entries,
    p_substitution,
    p_expected_lineup_revision
  );
$function$;

revoke all on function
  public.coach_save_match_live_lineup(uuid, jsonb, jsonb, integer)
  from public, anon;
grant execute on function
  public.coach_save_match_live_lineup(uuid, jsonb, jsonb, integer)
  to authenticated, service_role;

comment on function
  public.coach_save_match_live_lineup(uuid, jsonb, jsonb, integer)
is
  'Sauvegarde versionnée du lineup Live. Refuse en 40001 si lineup_revision a changé depuis le snapshot utilisé par le coach.';

commit;
