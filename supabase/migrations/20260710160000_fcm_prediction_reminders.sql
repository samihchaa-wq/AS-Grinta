begin;

create extension if not exists pg_net;
create extension if not exists pg_cron;

create table if not exists public.push_devices (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('web','ios','android')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_push_devices_profile_active
  on public.push_devices(profile_id,is_active);

alter table public.push_devices enable row level security;

drop policy if exists push_devices_owner_select on public.push_devices;
create policy push_devices_owner_select
on public.push_devices for select to authenticated
using (profile_id=(select auth.uid()));

drop policy if exists push_devices_owner_insert on public.push_devices;
create policy push_devices_owner_insert
on public.push_devices for insert to authenticated
with check (profile_id=(select auth.uid()));

drop policy if exists push_devices_owner_update on public.push_devices;
create policy push_devices_owner_update
on public.push_devices for update to authenticated
using (profile_id=(select auth.uid()))
with check (profile_id=(select auth.uid()));

drop policy if exists push_devices_owner_delete on public.push_devices;
create policy push_devices_owner_delete
on public.push_devices for delete to authenticated
using (profile_id=(select auth.uid()));

grant select,insert,update,delete on public.push_devices to authenticated;
revoke all on public.push_devices from anon;

create table if not exists public.prediction_reminder_deliveries (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  device_id uuid not null references public.push_devices(id) on delete cascade,
  reminder_type text not null check (reminder_type in ('24h','2h')),
  sent_at timestamptz not null default now(),
  unique(match_id,profile_id,device_id,reminder_type)
);

create index if not exists idx_prediction_reminder_deliveries_match
  on public.prediction_reminder_deliveries(match_id,reminder_type);

alter table public.prediction_reminder_deliveries enable row level security;

drop policy if exists prediction_reminder_deliveries_staff_read
  on public.prediction_reminder_deliveries;
create policy prediction_reminder_deliveries_staff_read
on public.prediction_reminder_deliveries for select to authenticated
using (public.is_match_staff());

grant select on public.prediction_reminder_deliveries to authenticated;
revoke insert,update,delete on public.prediction_reminder_deliveries from authenticated;
revoke all on public.prediction_reminder_deliveries from anon;

create or replace function public.register_push_device(
  p_token text,
  p_platform text
)
returns uuid
language plpgsql
security definer
set search_path='public'
as $$
declare
  result_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if btrim(coalesce(p_token,''))='' then raise exception 'Push token required'; end if;
  if p_platform not in ('web','ios','android') then raise exception 'Invalid platform'; end if;

  insert into public.push_devices(profile_id,token,platform,is_active,updated_at)
  values(auth.uid(),btrim(p_token),p_platform,true,now())
  on conflict(token) do update
    set profile_id=excluded.profile_id,
        platform=excluded.platform,
        is_active=true,
        updated_at=now()
  returning id into result_id;
  return result_id;
end;
$$;

revoke all on function public.register_push_device(text,text) from public,anon;
grant execute on function public.register_push_device(text,text) to authenticated;

create or replace function public.deactivate_push_device(p_token text)
returns boolean
language plpgsql
security definer
set search_path='public'
as $$
begin
  update public.push_devices
  set is_active=false,updated_at=now()
  where profile_id=auth.uid() and token=p_token;
  return found;
end;
$$;

revoke all on function public.deactivate_push_device(text) from public,anon;
grant execute on function public.deactivate_push_device(text) to authenticated;

create or replace function public.due_prediction_reminders()
returns table(
  device_id uuid,
  token text,
  platform text,
  match_id uuid,
  profile_id uuid,
  reminder_type text,
  opponent_name text
)
language sql
security definer
set search_path='public'
as $$
  with due as (
    select
      d.id as device_id,
      d.token,
      d.platform,
      m.id as match_id,
      p.id as profile_id,
      o.name as opponent_name,
      ((m.match_date + coalesce(m.match_time,'00:00:00'::time)) at time zone 'Europe/Paris') as kickoff_at
    from public.matches m
    join public.opponents o on o.id=m.opponent_id
    join public.match_predictions mp on mp.match_id=m.id and mp.is_filled=false
    join public.profiles p on p.id=mp.profile_id
    join public.push_devices d on d.profile_id=p.id and d.is_active=true
    where m.status='a_venir'
      and p.status='active'
      and coalesce(p.notify_prediction_reminders,true)
  ), reminders as (
    select due.*,'24h'::text as reminder_type
    from due
    where now() >= kickoff_at-interval '24 hours'
      and now() < kickoff_at-interval '24 hours'+interval '10 minutes'
    union all
    select due.*,'2h'::text as reminder_type
    from due
    where now() >= kickoff_at-interval '2 hours'
      and now() < kickoff_at-interval '2 hours'+interval '10 minutes'
  )
  select r.device_id,r.token,r.platform,r.match_id,r.profile_id,
         r.reminder_type,r.opponent_name
  from reminders r
  where not exists (
    select 1
    from public.prediction_reminder_deliveries d
    where d.match_id=r.match_id
      and d.profile_id=r.profile_id
      and d.device_id=r.device_id
      and d.reminder_type=r.reminder_type
  );
$$;

revoke all on function public.due_prediction_reminders() from public,anon,authenticated;
grant execute on function public.due_prediction_reminders() to service_role;

create or replace function public.record_prediction_reminder_delivery(
  p_match_id uuid,
  p_profile_id uuid,
  p_device_id uuid,
  p_reminder_type text
)
returns void
language sql
security definer
set search_path='public'
as $$
  insert into public.prediction_reminder_deliveries(
    match_id,profile_id,device_id,reminder_type
  ) values(p_match_id,p_profile_id,p_device_id,p_reminder_type)
  on conflict(match_id,profile_id,device_id,reminder_type) do nothing;
$$;

revoke all on function public.record_prediction_reminder_delivery(uuid,uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.record_prediction_reminder_delivery(uuid,uuid,uuid,text)
  to service_role;

select vault.create_secret(
  'https://ovzijmqrnsgcmryinkfa.supabase.co',
  'prediction_reminders_project_url',
  'Project URL used by the prediction reminder cron job'
)
where not exists (
  select 1 from vault.decrypted_secrets where name='prediction_reminders_project_url'
);

select vault.create_secret(
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im92emlqbXFybnNnY21yeWlua2ZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM0OTYyNDMsImV4cCI6MjA5OTA3MjI0M30.7lJM-Iy0j9HzAGPrlDVBk7LbFy2qAm9T-f3OhTcsMkU',
  'prediction_reminders_anon_jwt',
  'Public anon JWT used only to invoke the reminder Edge Function'
)
where not exists (
  select 1 from vault.decrypted_secrets where name='prediction_reminders_anon_jwt'
);

select cron.schedule(
  'send-prediction-reminders',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets
            where name='prediction_reminders_project_url') ||
           '/functions/v1/send-prediction-reminders',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets
        where name='prediction_reminders_anon_jwt'
      )
    ),
    body := jsonb_build_object('scheduled_at',now()),
    timeout_milliseconds := 20000
  );
  $$
);

commit;
