-- Defense in depth for the last private tables that were still relying only
-- on schema/table privilege revocations. No client policy is added: these
-- tables remain inaccessible to anon/authenticated roles.
alter table private.prediction_reminder_cron_config enable row level security;
alter table private.registration_attempts enable row level security;

-- The notification-kind constraint already protects every new row. Validate
-- the historical table too so the database can certify the full invariant.
alter table public.push_notification_log
  validate constraint push_notification_log_kind_check;
