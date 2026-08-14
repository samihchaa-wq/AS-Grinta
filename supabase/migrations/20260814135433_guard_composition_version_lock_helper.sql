-- Garde manquante sur le helper introduit par 20260814094905.
--
-- `private.lock_match_composition_version` est SECURITY DEFINER et son
-- execution est accordee au role `authenticated` : n'importe quel compte
-- connecte pouvait donc l'appeler directement, prendre le verrou de la ligne
-- et sonder la version d'une composition, sans passer par la RPC publique.
--
-- Elle applique desormais les memes gardes que `private.save_match_composition`
-- (module sports_management actif + administrateur actif). Consequence voulue :
-- un appelant non administrateur recoit `42501 / Active administrator role
-- required` sur la surcharge a six parametres, exactement comme sur la
-- surcharge historique a cinq parametres, au lieu du refus de version `40001`.
--
-- Le reste est inchange : version absente = aucun controle, version differente
-- = refus 40001, verrou `for update` toujours pris dans la transaction de la
-- RPC appelante.

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

  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
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

commit;
