-- Renforce la résilience du pipeline Web Push sans exposer de données client.
-- Les erreurs temporaires sont relancées par l'Edge Function et le nombre
-- d'essais est conservé pour permettre une surveillance agrégée.

alter table public.push_delivery_log
  add column if not exists attempts smallint not null default 1;

do $$
begin
  alter table public.push_delivery_log
    add constraint push_delivery_log_attempts_check
    check (attempts between 1 and 2);
exception
  when duplicate_object then null;
end;
$$;

create index if not exists idx_push_delivery_log_health
  on public.push_delivery_log (created_at desc, success, status_code);

create or replace function public.internal_push_delivery_health(
  p_since timestamptz default (now() - interval '24 hours')
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'since', p_since,
    'attempted', count(*)::integer,
    'sent', count(*) filter (where delivery.success)::integer,
    'failed', count(*) filter (where not delivery.success)::integer,
    'expired', count(*) filter (
      where not delivery.success and delivery.status_code in (404, 410)
    )::integer,
    'transient_failures', count(*) filter (
      where not delivery.success
        and (
          delivery.status_code is null
          or delivery.status_code in (408, 425, 429)
          or delivery.status_code >= 500
        )
    )::integer,
    'retry_recoveries', count(*) filter (
      where delivery.success and delivery.attempts > 1
    )::integer,
    'retry_exhausted', count(*) filter (
      where not delivery.success
        and delivery.attempts > 1
        and (
          delivery.status_code is null
          or delivery.status_code in (408, 425, 429)
          or delivery.status_code >= 500
        )
    )::integer,
    'latest_delivery_at', max(delivery.created_at),
    'requires_attention', count(*) filter (
      where not delivery.success
        and coalesce(delivery.status_code not in (404, 410), true)
    ) > 0
  )
  from public.push_delivery_log delivery
  where delivery.created_at >= p_since;
$$;

revoke all on function public.internal_push_delivery_health(timestamptz)
  from public, anon, authenticated;
grant execute on function public.internal_push_delivery_health(timestamptz)
  to service_role;
