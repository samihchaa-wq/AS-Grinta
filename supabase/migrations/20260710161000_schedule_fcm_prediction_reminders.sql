begin;

create schema if not exists private;
revoke all on schema private from public,anon,authenticated;

create table if not exists private.prediction_reminder_cron_config (
  singleton boolean primary key default true check (singleton),
  secret_hash text not null,
  created_at timestamptz not null default now()
);

revoke all on private.prediction_reminder_cron_config from public,anon,authenticated;

do $$
declare
  raw_secret text;
begin
  if not exists (
    select 1 from vault.decrypted_secrets
    where name='prediction_reminder_cron_secret'
  ) then
    raw_secret := encode(extensions.gen_random_bytes(32),'hex');
    perform vault.create_secret(
      raw_secret,
      'prediction_reminder_cron_secret',
      'Internal authentication secret for the prediction reminder cron job'
    );
    insert into private.prediction_reminder_cron_config(singleton,secret_hash)
    values(
      true,
      extensions.crypt(raw_secret,extensions.gen_salt('bf'))
    )
    on conflict(singleton) do update set secret_hash=excluded.secret_hash;
  end if;
end;
$$;

create or replace function public.validate_prediction_reminder_cron_secret(
  p_secret text
)
returns boolean
language sql
stable
security definer
set search_path='private,extensions'
as $$
  select exists (
    select 1
    from private.prediction_reminder_cron_config
    where extensions.crypt(coalesce(p_secret,''),secret_hash)=secret_hash
  );
$$;

revoke all on function public.validate_prediction_reminder_cron_secret(text)
  from public,anon,authenticated;
grant execute on function public.validate_prediction_reminder_cron_secret(text)
  to service_role;

select cron.schedule(
  'send-prediction-reminders',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-prediction-reminders',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-cron-secret',(
        select decrypted_secret from vault.decrypted_secrets
        where name='prediction_reminder_cron_secret'
      )
    ),
    body := jsonb_build_object('scheduled_at',now()),
    timeout_milliseconds := 20000
  );
  $$
);

commit;
