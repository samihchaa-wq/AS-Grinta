begin;

-- La valeur autoritaire reste dans private.app_feature_flags. Cette table publique
-- ne contient qu'un signal de changement sans configuration ni état fonctionnel.
create table if not exists public.feature_flag_change_signals (
  key text primary key,
  revision bigint not null default 1,
  updated_at timestamptz not null default now(),
  constraint feature_flag_change_signals_key_format
    check (key ~ '^[a-z][a-z0-9_]*$'),
  constraint feature_flag_change_signals_revision_positive
    check (revision > 0)
);

comment on table public.feature_flag_change_signals is
  'Public-safe Realtime signal. Clients refresh authoritative feature flags through RPC.';

alter table public.feature_flag_change_signals enable row level security;

revoke all on table public.feature_flag_change_signals
  from public, anon, authenticated;
grant select on table public.feature_flag_change_signals
  to authenticated, service_role;

drop policy if exists feature_flag_change_signals_read
  on public.feature_flag_change_signals;
create policy feature_flag_change_signals_read
on public.feature_flag_change_signals
as permissive
for select
to authenticated
using (true);

drop policy if exists active_authenticated_profile_only
  on public.feature_flag_change_signals;
create policy active_authenticated_profile_only
on public.feature_flag_change_signals
as restrictive
for all
to authenticated
using ((select private.is_active_profile()))
with check ((select private.is_active_profile()));

insert into public.feature_flag_change_signals(key, revision, updated_at)
select flag.key, 1, flag.updated_at
from private.app_feature_flags flag
on conflict (key) do update
set updated_at = excluded.updated_at;

create or replace function private.signal_feature_flag_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.feature_flag_change_signals(key, revision, updated_at)
  values (new.key, 1, new.updated_at)
  on conflict (key) do update
  set revision = public.feature_flag_change_signals.revision + 1,
      updated_at = excluded.updated_at;

  return new;
end;
$function$;

revoke execute on function private.signal_feature_flag_change()
  from public, anon, authenticated;

drop trigger if exists trg_signal_feature_flag_change
  on private.app_feature_flags;
create trigger trg_signal_feature_flag_change
after update of enabled, config on private.app_feature_flags
for each row
when (
  old.enabled is distinct from new.enabled
  or old.config is distinct from new.config
)
execute function private.signal_feature_flag_change();

-- Postgres Changes est suffisant ici : une seule ligne peu fréquemment modifiée,
-- protégée par RLS, et aucun contenu métier n'est publié.
do $block$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'feature_flag_change_signals'
  ) then
    alter publication supabase_realtime
      add table public.feature_flag_change_signals;
  end if;
end;
$block$;

commit;
