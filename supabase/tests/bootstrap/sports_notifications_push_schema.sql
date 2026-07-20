-- Minimal faithful push-subscription schema required by the isolated sports
-- notification tests. Production already has this table from the Web Push
-- migration; this file is test bootstrap only.

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
