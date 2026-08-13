-- Bug 14 : aucun controle de concurrence entre deux administrateurs.
--
-- Deux coachs ouvrent la composition un jour de match ; le premier enregistre,
-- le second — qui avait charge l'ecran avant — enregistre a son tour. Le
-- travail du premier disparaissait sans conflit, sans avertissement, et etait
-- publie a tout le club dans la foulee.
--
-- `public.match_compositions.version` existait deja mais n'etait jamais
-- comparee. Une surcharge a six parametres accepte desormais la version que
-- l'appelant croit modifier et refuse l'ecriture si elle a bouge entre-temps.
--
-- La signature historique a cinq parametres est CONSERVEE et delegue sans
-- controle de version : plusieurs contrats la referencent explicitement
-- (simplified_match_workflows, sports_management_composition_server), et la
-- retirer casserait des appelants hors de ce depot. `p_expected_version` n'a
-- volontairement pas de valeur par defaut, afin qu'un appel a cinq arguments
-- reste non ambigu entre les deux surcharges.

begin;

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
  v_current_version integer;
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

  if p_expected_version is not null then
    -- La ligne est verrouillee jusqu'a la fin de la transaction : deux
    -- enregistrements simultanes sont serialises, et le second voit bien la
    -- version ecrite par le premier.
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
  end if;

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

-- Surcharge historique : comportement inchange, sans controle de version.
-- `create or replace` preserve les privileges deja accordes.
create or replace function public.admin_save_match_composition(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_allow_squad_size_exception boolean default false,
  p_reason text default null
)
returns jsonb
language sql
set search_path to ''
as $function$
  select public.admin_save_match_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    p_allow_squad_size_exception,
    p_reason,
    null::integer
  );
$function$;

comment on function public.admin_save_match_composition(uuid, text, jsonb, boolean, text) is
  'Signature historique conservee pour les appelants existants : delegue a la version a six parametres sans controle de concurrence.';

commit;
