-- Le prénom choisi sur son compte l'emporte sur celui saisi dans l'effectif.
--
-- L'admin crée les joueurs de l'effectif avec le prénom qu'il connaît
-- (« Stéphane »), puis rattache le compte du joueur. Si celui-ci s'est inscrit
-- sous « Steph », c'est ce nom-là qu'il veut voir partout — or l'application
-- continuait d'afficher « Stéphane » : le nom affiché ne consultait que le
-- surnom du compte, jamais son prénom.
--
-- L'ordre de priorité devient donc, pour un joueur rattaché à un compte :
--
--   1. le surnom du compte, s'il en a mis un ;
--   2. le prénom du compte ;              <- ajouté ici
--   3. le prénom saisi dans l'effectif ;
--   4. prénom + nom en dernier recours.
--
-- Les fonctions concernées sont longues et ont déjà divergé du dépôt par le
-- passé : on insère la nouvelle priorité par remplacement ciblé, sans toucher
-- au reste de leur corps. Le tri par nom suit la même règle, pour qu'un joueur
-- ne soit pas classé sous un prénom qui ne s'affiche nulle part.

do $patch$
declare
  v_signature text;
  v_oid regprocedure;
  v_def text;
  v_new text;
  -- Présent uniquement après correction : deux nullif(btrim(...)) collés sur
  -- la même ligne, ce que le code d'origine n'écrit jamais.
  v_marker constant text := '.surnom), ''''), nullif(btrim(';
begin
  foreach v_signature in array array[
    'private.composition_snapshot(uuid)',
    'private.get_match_availability_board(uuid)',
    'private.get_match_convocations(uuid)',
    'private.get_match_motm_vote(uuid)',
    'private.get_published_match_composition(uuid)',
    'private.get_sport_waitlist(uuid)',
    'private.get_sport_waitlist_readonly(uuid)',
    'private.match_live_snapshot(uuid)',
    'private.match_sport_finalization_snapshot(uuid)',
    'public.admin_get_internal_composition(uuid)'
  ]
  loop
    -- Le schéma minimal rejoué par les tests métier n'installe pas toutes ces
    -- fonctions : on passe au lieu d'échouer.
    v_oid := to_regprocedure(v_signature);
    if v_oid is null then
      continue;
    end if;

    v_def := pg_get_functiondef(v_oid);
    if position(v_marker in v_def) > 0 then
      continue; -- déjà corrigée
    end if;

    -- Nom affiché : le prénom du compte s'intercale juste après le surnom.
    -- L'alias du profil change d'une fonction à l'autre (profile, in_profile,
    -- scorer_profile…), il est donc capturé puis réutilisé.
    v_new := regexp_replace(
      v_def,
      'nullif\(btrim\((\w+)\.surnom\), ''''\)',
      'nullif(btrim(\1.surnom), ''''), nullif(btrim(\1.first_name), '''')',
      'g'
    );

    -- Tri par nom : même priorité, pour que l'ordre suive l'affichage.
    v_new := replace(
      v_new,
      'lower(coalesce(profile.surnom, player.first_name',
      'lower(coalesce(profile.surnom, profile.first_name, player.first_name'
    );

    if v_new = v_def then
      raise exception '%: motif de nom introuvable, correction manuelle requise',
        v_signature;
    end if;

    execute v_new;
  end loop;
end
$patch$;
