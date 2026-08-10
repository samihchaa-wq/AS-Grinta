begin;

create index if not exists idx_prediction_reminder_deliveries_device
  on public.prediction_reminder_deliveries(device_id);

create index if not exists idx_prediction_reminder_deliveries_profile
  on public.prediction_reminder_deliveries(profile_id);

create unique index if not exists seasons_single_open_idx
  on public.seasons ((status))
  where status='open';

commit;
