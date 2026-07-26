-- Diagnostic de production en lecture seule.
-- À exécuter avec un rôle d’administration Supabase.
-- Aucune instruction de ce fichier ne modifie les données ou le schéma.

-- 1. Sessions en attente ou transactions anormalement longues.
select
  pid,
  usename,
  application_name,
  state,
  wait_event_type,
  wait_event,
  now() - coalesce(xact_start, query_start) as elapsed,
  left(regexp_replace(query, '\s+', ' ', 'g'), 300) as query
from pg_stat_activity
where datname = current_database()
  and pid <> pg_backend_pid()
  and (
    wait_event_type is not null
    or state = 'idle in transaction'
    or now() - coalesce(xact_start, query_start) > interval '30 seconds'
  )
order by elapsed desc nulls last;

-- 2. Requêtes applicatives les plus coûteuses depuis le dernier redémarrage.
select
  calls,
  round(total_exec_time::numeric, 1) as total_ms,
  round(mean_exec_time::numeric, 2) as mean_ms,
  round(max_exec_time::numeric, 2) as max_ms,
  rows,
  shared_blks_hit,
  shared_blks_read,
  left(regexp_replace(query, '\s+', ' ', 'g'), 500) as query
from extensions.pg_stat_statements
where dbid = (select oid from pg_database where datname = current_database())
  and query not ilike '%pg_stat_statements%'
  and query not ilike 'select pg_sleep%'
  and query not ilike '%pg_timezone_names%'
order by total_exec_time desc
limit 30;

-- 3. Index jamais utilisés, avec leur taille et la date de démarrage des statistiques.
-- Ne pas supprimer un index uniquement sur ce résultat : vérifier son rôle pour les
-- contraintes, clés étrangères, opérations rares et pics saisonniers.
select
  schemaname,
  relname as table_name,
  indexrelname as index_name,
  idx_scan,
  pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
  pg_postmaster_start_time() as statistics_started_at
from pg_stat_user_indexes
where idx_scan = 0
order by pg_relation_size(indexrelid) desc, schemaname, relname, indexrelname;

-- 4. Cohérence entre les profils applicatifs et les comptes Auth.
select
  count(*) filter (where u.id is null and p.status = 'active')
    as active_profiles_without_auth,
  count(*) filter (where u.id is null and p.status = 'pending')
    as pending_profiles_without_auth,
  count(*) filter (where p.id is null)
    as auth_users_without_profile
from public.profiles p
full join auth.users u on u.id = p.id
where coalesce(p.id, u.id) <> '00000000-0000-0000-0000-000000000001'::uuid;

-- 5. Échecs récents des tâches planifiées.
select
  jobid,
  status,
  start_time,
  end_time,
  return_message
from cron.job_run_details
where start_time >= now() - interval '24 hours'
  and status <> 'succeeded'
order by start_time desc
limit 100;

-- 6. Historique et fréquence des tâches actives.
select jobid, schedule, command, active
from cron.job
order by jobid;
