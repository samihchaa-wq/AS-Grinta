-- Correctif du controle de concurrence pose par 20260813210400.
--
-- La surcharge a six parametres de admin_save_match_composition n'est pas
-- SECURITY DEFINER : elle s'execute avec les droits de l'appelant. Or le role
-- authenticated n'a aucun privilege direct sur public.match_compositions, si
-- bien que le « select ... for update » ajoute pour comparer la version
-- echouait en refus de privilege des qu'un administrateur enregistrait une
-- composition avec p_expected_version renseigne.
--
-- La lecture verrouillante part donc dans un helper prive SECURITY DEFINER,
-- dont l'execution est reservee a authenticated et service_role. Le
-- comportement fonctionnel est inchange : version absente = aucun controle,
-- version differente = refus 40001.
--
-- Cette migration a ete appliquee en production le 14/08/2026 avant d'etre
-- versionnee ici ; son fichier est ajoute au depot pour que les installations
-- neuves reproduisent le meme etat.

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
