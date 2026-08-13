-- Réinscrit dans le dépôt un durcissement appliqué directement en production le
-- 10/08/2026, sous la version 20260810123232, sans que son fichier soit commité.
--
-- L'historique distant portait donc une version introuvable en local, ce qui
-- faisait échouer tout `supabase db push` — et bloquait toute migration
-- suivante. L'entrée orpheline est retirée de l'historique de production ; ces
-- instructions, elles, reprennent leur place dans la suite normale des
-- migrations, à la date d'aujourd'hui.
--
-- Les rejouer est sans effet sur la base actuelle, qui les porte déjà :
-- activer une RLS active et valider une contrainte validée sont des opérations
-- idempotentes. Elles restent nécessaires pour reconstruire le schéma de zéro.

alter table private.prediction_reminder_cron_config enable row level security;
alter table private.registration_attempts enable row level security;
alter table public.push_notification_log validate constraint push_notification_log_kind_check;
