-- Remplacement du système de rappels FCM (jamais opérationnel : aucun client
-- Flutter n'enregistrait d'appareil et aucun compte de service Firebase n'a
-- été fourni) par les notifications Web Push VAPID autonomes
-- (20260711080000_web_push_notifications.sql).

do $$
begin
  if exists (select 1 from cron.job where jobname = 'send-prediction-reminders') then
    perform cron.unschedule('send-prediction-reminders');
  end if;
end $$;

do $$
declare v_fn record;
begin
  for v_fn in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'register_push_device',
        'deactivate_push_device',
        'due_prediction_reminders',
        'record_prediction_reminder_delivery',
        'validate_prediction_reminder_cron_secret'
      )
  loop
    execute format('drop function %s cascade', v_fn.signature);
  end loop;
end $$;

drop table if exists public.prediction_reminder_deliveries;
drop table if exists public.push_devices;

delete from vault.secrets where name = 'prediction_reminder_cron_secret';
