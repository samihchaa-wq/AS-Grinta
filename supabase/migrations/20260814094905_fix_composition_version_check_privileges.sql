-- Regression : « Tu n'as pas les droits pour cette action » a chaque
-- enregistrement de composition depuis l'application.
--
-- Le controle de concurrence ajoute le 13/08 (migration
-- 20260813210400_composition_optimistic_locking) lit `public.match_compositions`
-- directement depuis la RPC publique. Cette RPC est SECURITY INVOKER : elle
-- s'execute avec les droits du compte connecte. Or le role `authenticated` n'a
-- aucun privilege sur cette table (`revoke all` + policy restrictive
-- `deny_client_access`) : seules les fonctions `private` SECURITY DEFINER y
-- touchent.
--
-- Postgres refuse donc la lecture avec « permission denied for table
-- match_compositions » (42501), que l'application traduit par « Tu n'as pas les
-- droits pour cette action. ». L'application envoyant toujours
-- `p_expected_version`, plus aucun administrateur ne pouvait enregistrer une
-- composition — verifie sur la base de production, ou la migration fautive est
-- appliquee et ou le role `authenticated` n'a ni SELECT ni UPDATE sur la table.
--
-- Le test livre avec la migration d'origine ne verifiait que la presence de la
-- signature a six parametres, jamais un appel reel sous le role
-- `authenticated` : la regression est passee.
--
-- Correctif : la lecture et le verrou de version passent dans une fonction
-- `private` SECURITY DEFINER, comme tous les autres acces a ces tables. Le
-- verrou `for update` reste pris dans la transaction de la RPC, donc la
-- protection contre deux enregistrements simultanes est conservee a
-- l'identique.

begin;

create or replace function private.lock_match_composition_version(
  p_match_id uuid,
  p_expected_version integer
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_current_version integer;
begin
  if p_expected_version is null then
    return;
  end if;

  -- Meme garde que `private.save_match_composition` : la fonction est
  -- executable par le role `authenticated`, elle doit donc refuser d'elle-meme
  -- un appelant qui n'est pas administrateur actif.
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  -- La ligne est verrouillee jusqu'a la fin de la transaction appelante :
  -- deux enregistrements simultanes sont serialises, et le second voit bien
  -- la version ecrite par le premier.
  select composition.version
  into v_current_version
  from public.match_compositions composition
  where composition.match_id = p_match_id
  for update;

  if found and v_current_version is distinct from p_expected_version then
    raise exception
      'Un autre administrateur a modifié cette composition. Recharge l’écran avant d’enregistrer.'
      using errcode = '40001';
  end if;
end;
$function$;

comment on function private.lock_match_composition_version(uuid, integer) is
  'Verrouille la composition d un match et refuse (40001) si sa version a change depuis le chargement de l ecran. SECURITY DEFINER : le role authenticated n a aucun privilege direct sur match_compositions.';

revoke all on function private.lock_match_composition_version(uuid, integer)
  from public, anon;
grant execute on function private.lock_match_composition_version(uuid, integer)
  to authenticated, service_role;

create or replace function public.admin_save_match_composition(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_allow_squad_size_exception boolean,
  p_reason text,
  p_expected_version integer
)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  select match.status, match.kickoff_at
  into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status = 'a_venir'
     and v_kickoff_at is not null
     and now() >= v_kickoff_at - interval '15 minutes' then
    raise exception 'La composition est figée depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  perform private.lock_match_composition_version(p_match_id, p_expected_version);

  perform private.save_match_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    p_allow_squad_size_exception,
    p_reason
  );
  return private.publish_match_composition(
    p_match_id,
    p_allow_squad_size_exception,
    p_reason
  );
end;
$function$;

comment on function public.admin_save_match_composition(uuid, text, jsonb, boolean, text, integer) is
  'Enregistre puis publie la composition d un match. p_expected_version active le controle de concurrence optimiste : l ecriture est refusee (40001) si la composition a change depuis son chargement.';

revoke all on function
  public.admin_save_match_composition(uuid, text, jsonb, boolean, text, integer)
  from public, anon;
grant execute on function
  public.admin_save_match_composition(uuid, text, jsonb, boolean, text, integer)
  to authenticated, service_role;

commit;
