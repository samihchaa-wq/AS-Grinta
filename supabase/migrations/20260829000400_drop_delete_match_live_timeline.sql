begin;

-- Retrait de « Supprimer les faits du match ».
--
-- Cette action existait parce que le bloc « Faits du match » de la fiche
-- affichait le brouillon saisi en direct, sans aucun moyen de le corriger :
-- quand il était faux, seul l'effacement permettait de ne pas publier une
-- chronologie fausse.
--
-- Le compte rendu est désormais la source des buts affichés sur la fiche, et
-- il est corrigeable pendant toute la fenêtre de correction. Effacer n'a donc
-- plus lieu d'être : on corrige.
--
-- Le journal du direct reste en place, intact. Il n'alimente plus que les
-- remplacements, que le compte rendu ne modélise pas.

drop function if exists public.admin_delete_match_live_timeline(uuid, text);
drop function if exists private.delete_match_live_timeline(uuid, text);

commit;
