-- La gestion des badges passe au seul modérateur.
--
-- Créer un badge, en attribuer un ou le retirer touche au palmarès affiché
-- sur le profil des joueurs : c'est une décision de club, pas une opération
-- de match. Ces trois RPC exigeaient « staff » (donc aussi les admins) ;
-- elles exigent désormais le rôle de modérateur.
--
-- Les fonctions sont patchées par remplacement ciblé de leur garde : leur
-- corps est long, il a déjà divergé du dépôt par le passé, et rien d'autre
-- ne change ici. Le bloc est idempotent et échoue bruyamment si le motif
-- attendu a disparu.
--
-- set_badge_featured n'est pas concernée : c'est le joueur lui-même qui
-- choisit les badges mis en avant sur son profil.

do $patch$
declare
  v_function text;
  v_def text;
  v_old constant text :=
    'if not public.is_match_staff() then'
    || E'\n    raise exception ''Active administrator role required'' using errcode = ''42501'';';
  v_new constant text :=
    'if not public.is_moderator() then'
    || E'\n    raise exception ''Moderator role required'' using errcode = ''42501'';';
begin
  foreach v_function in array array[
    'public.staff_create_badge(text, text, text, text, text, text)',
    'public.staff_award_badge(uuid, text)',
    'public.staff_revoke_badge(uuid, text)'
  ]
  loop
    v_def := pg_get_functiondef(v_function::regprocedure);
    if position('public.is_moderator()' in v_def) > 0 then
      continue; -- déjà restreinte
    end if;
    if position(v_old in v_def) = 0 then
      raise exception '%: garde attendue introuvable, correction manuelle requise', v_function;
    end if;
    execute replace(v_def, v_old, v_new);
  end loop;
end
$patch$;
