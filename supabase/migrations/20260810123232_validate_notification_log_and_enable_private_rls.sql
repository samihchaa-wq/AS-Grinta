-- Migration déjà appliquée en production le 10/08/2026, mais absente du dépôt :
-- son fichier n'avait jamais été commité. L'historique distant contenait donc
-- une version introuvable en local, ce qui bloquait tout `supabase db push`.
--
-- Le contenu ci-dessous est repris tel quel depuis
-- supabase_migrations.schema_migrations en production. Rejouer ces
-- instructions est sans effet sur une base qui les porte déjà : activer une RLS
-- active et valider une contrainte validée sont des opérations idempotentes.

alter table private.prediction_reminder_cron_config enable row level security;
alter table private.registration_attempts enable row level security;
alter table public.push_notification_log validate constraint push_notification_log_kind_check;
