-- Réinscrit dans le dépôt le durcissement RLS appliqué directement en
-- production le 10/08/2026, sous la version 20260810123232, sans que son
-- fichier soit commité.
--
-- L'historique distant portait donc une version introuvable en local, ce qui
-- faisait échouer tout `supabase db push` — et bloquait toute migration
-- suivante. L'entrée orpheline est retirée de l'historique de production ; ces
-- instructions reprennent leur place dans la suite normale des migrations.
--
-- Les rejouer est sans effet sur la base actuelle, qui les porte déjà :
-- activer une RLS active est idempotent. Elles restent nécessaires pour
-- reconstruire le schéma de zéro.
--
-- La migration d'origine validait aussi push_notification_log_kind_check. Cette
-- instruction n'est délibérément pas reprise ici : le contrat de durcissement
-- (notifications_motm_hardening_contract) exige que cette contrainte reste NOT
-- VALID, afin que le journal conserve ses anciens types tout en les refusant à
-- l'avenir. La production l'a validée le 10/08 hors du dépôt ; l'écart est
-- signalé pour arbitrage, mais reproduire cette validation ici reviendrait à
-- casser un contrat explicite sans décision préalable.

alter table private.prediction_reminder_cron_config enable row level security;
alter table private.registration_attempts enable row level security;
