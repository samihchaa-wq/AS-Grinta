-- Diagnostic de production en lecture seule : une notification a-t-elle été
-- vue ? À exécuter avec un rôle d’administration Supabase. Aucune instruction
-- de ce fichier ne modifie les données ou le schéma.
--
-- Remplacer :match_id par l’identifiant du match. Pour chaque joueur visé par
-- l’ouverture des disponibilités, la requête dit si Apple ou Google ont
-- accepté l’envoi, si le téléphone l’a affichée, et sinon pourquoi c’est
-- probable.

with sent as (
  select
    log.profile_id,
    min(log.created_at) as sent_at,
    bool_or(log.success) as accepted
  from public.push_delivery_log log
  where log.match_id = :'match_id'::uuid
    and log.kind = 'availability_open'
  group by log.profile_id
),
seen as (
  select receipt.profile_id, min(receipt.displayed_at) as displayed_at
  from private.push_display_receipts receipt
  where receipt.tag = 'sport-' || :'match_id' || '-availability-open'
  group by receipt.profile_id
),
devices as (
  select
    subscription.profile_id,
    max(subscription.device_reported_at) as last_report,
    string_agg(
      distinct coalesce(subscription.notification_permission, 'inconnue'),
      ', '
    ) as permissions
  from public.push_subscriptions subscription
  group by subscription.profile_id
)
select
  profile.first_name || ' ' || left(profile.last_name, 1) as joueur,
  to_char(sent.sent_at at time zone 'Europe/Paris', 'DD/MM HH24:MI') as envoyee,
  sent.accepted as acceptee,
  to_char(seen.displayed_at at time zone 'Europe/Paris', 'DD/MM HH24:MI') as affichee,
  devices.permissions as autorisation_telephone,
  to_char(devices.last_report at time zone 'Europe/Paris', 'DD/MM HH24:MI') as derniere_ouverture,
  case
    when sent.profile_id is null then 'aucun appareil abonné'
    when not sent.accepted then 'refusée par Apple ou Google'
    when seen.profile_id is not null then 'vue'
    when devices.permissions like '%denied%' then 'bloquée dans les réglages du téléphone'
    when devices.last_report is null or devices.last_report < sent.sent_at
      then 'en attente : téléphone pas rouvert depuis l’envoi'
    else 'acceptée mais jamais affichée par le téléphone'
  end as verdict
from sent
full join seen on seen.profile_id = sent.profile_id
join public.profiles profile
  on profile.id = coalesce(sent.profile_id, seen.profile_id)
left join devices on devices.profile_id = profile.id
order by verdict, joueur;
