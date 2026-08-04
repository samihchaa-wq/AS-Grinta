-- Fixture du domaine badges utilisée par le schéma Supabase isolé.
-- La table reprend la forme actuelle nécessaire aux migrations récentes ; les
-- calculs métier complets restent couverts par les migrations et tests dédiés.

create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text not null,
  emoji text not null,
  family text not null check (family = any(array['joueur'::text, 'pronostiqueur'::text])),
  auto boolean not null default true,
  metric text,
  threshold integer,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  kind text not null default 'tier',
  category text not null default 'all_time',
  image_url text,
  color text,
  has_star boolean not null default false,
  standalone boolean not null default false,
  secret boolean not null default false
);

alter table public.badges enable row level security;

create or replace function public.profile_badge_metrics(p_profile_id uuid)
returns table(total_points bigint)
language sql
stable
security definer
set search_path to ''
as $function$
  select 0::bigint;
$function$;

revoke all on function public.profile_badge_metrics(uuid) from public, anon;
grant execute on function public.profile_badge_metrics(uuid) to authenticated, service_role;
