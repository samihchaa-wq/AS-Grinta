-- Bug 38 : cette migration etait APPLIQUEE EN PRODUCTION mais absente du
-- depot (436 migrations appliquees contre 435 fichiers). Tout environnement
-- reconstruit depuis le depot etait donc moins verrouille que la production.
-- Le contenu constate en production est reintroduit ici. Le fichier porte un
-- horodatage posterieur a l'historique du depot (et non le 20260810123232
-- d'origine), car la CI exige que toute migration ajoutee soit strictement
-- posterieure a la derniere migration de la branche de base :
--   * validation de la contrainte de type sur push_notification_log ;
--   * activation de RLS sur les deux tables `private` qui en etaient encore
--     depourvues.
--
-- Les instructions sont idempotentes : la production, ou elle est deja
-- appliquee, n'en subit aucun effet.

begin;

-- La contrainte etait posee NOT VALID : les lignes anterieures n'avaient
-- jamais ete verifiees.
alter table public.push_notification_log
  validate constraint push_notification_log_kind_check;

-- Les tables du schema `private` ne sont jamais exposees par PostgREST, mais
-- RLS active sans policy vaut refus par defaut : c'est la posture retenue pour
-- tout le schema.
alter table private.prediction_reminder_cron_config enable row level security;
alter table private.registration_attempts enable row level security;

commit;
