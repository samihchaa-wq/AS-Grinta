-- Minimal faithful push-subscription schema required by the isolated sports
-- notification tests. Production already has these objects from the Web Push
-- migration; this file is test bootstrap only.

-- The baseline business bootstrap historically called this timestamp
-- `created_at`, while production's notification log uses `sent_at`. Align the
-- isolated schema before notification migrations install triggers that update
-- the delivery timestamp.
do $do$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'push_notification_log'
      and column_name = 'created_at'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'push_notification_log'
      and column_name = 'sent_at'
  ) then
    alter table public.push_notification_log rename column created_at to sent_at;
  end if;
end;
$do$;

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_push_subscriptions_profile
  on public.push_subscriptions(profile_id);

alter table public.push_subscriptions enable row level security;

create or replace function public.internal_push_prune(p_endpoints text[])
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_deleted integer;
begin
  delete from public.push_subscriptions
  where endpoint = any(coalesce(p_endpoints, '{}'::text[]));
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$function$;

revoke all on function public.internal_push_prune(text[])
  from public, anon, authenticated;
grant execute on function public.internal_push_prune(text[])
  to service_role;
