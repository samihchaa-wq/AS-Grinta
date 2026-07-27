-- Diagnostic en lecture seule du système de notifications Web Push.
-- À exécuter avec un rôle d’exploitation autorisé. Aucune URL complète ni clé
-- d’abonnement n’est affichée.

-- Résumé des livraisons récentes.
select
  date_trunc('hour', created_at) as hour,
  kind,
  count(*) as attempts,
  count(*) filter (where success) as successes,
  count(*) filter (where not success) as failures,
  round(
    100.0 * count(*) filter (where success) / nullif(count(*), 0),
    2
  ) as success_rate_percent
from public.push_delivery_log
where created_at >= now() - interval '24 hours'
group by 1, 2
order by 1 desc, 2;

-- Erreurs récentes regroupées sans endpoint complet.
select
  kind,
  coalesce(status_code, 0) as status_code,
  coalesce(endpoint_host, 'unknown') as endpoint_host,
  left(coalesce(error_message, 'unknown'), 160) as error_summary,
  count(*) as occurrences,
  max(created_at) as last_seen_at
from public.push_delivery_log
where not success
  and created_at >= now() - interval '24 hours'
group by 1, 2, 3, 4
order by occurrences desc, last_seen_at desc;

-- Les endpoints sont uniques par construction ; toute ligne signale une dérive.
select endpoint_host, duplicate_count
from (
  select
    split_part(replace(endpoint, 'https://', ''), '/', 1) as endpoint_host,
    count(*) as duplicate_count
  from public.push_subscriptions
  group by endpoint
  having count(*) > 1
) duplicates;

-- Abonnements encore liés à un compte non actif.
select
  profile.status,
  count(*) as subscriptions
from public.push_subscriptions subscription
join public.profiles profile on profile.id = subscription.profile_id
where profile.status <> 'active'
group by profile.status
order by profile.status;

-- Abonnements qui n’ont pas été actualisés depuis longtemps. Ils ne sont pas
-- supprimés automatiquement sur ce seul critère : le rapport sert à décider
-- d’un contrôle ou d’une campagne de réinscription.
select
  split_part(replace(endpoint, 'https://', ''), '/', 1) as endpoint_host,
  count(*) as subscriptions,
  min(updated_at) as oldest_update,
  max(updated_at) as newest_update
from public.push_subscriptions
where updated_at < now() - interval '180 days'
group by 1
order by subscriptions desc, oldest_update;

-- Événements métier qui n’ont jamais produit de tentative de livraison.
select
  event.match_id,
  event.kind,
  event.created_at
from public.push_notification_log event
where event.created_at >= now() - interval '24 hours'
  and not exists (
    select 1
    from public.push_delivery_log delivery
    where delivery.match_id = event.match_id
      and delivery.kind = event.kind
  )
order by event.created_at desc;
