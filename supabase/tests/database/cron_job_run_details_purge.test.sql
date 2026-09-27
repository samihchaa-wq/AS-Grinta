begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Le journal des tâches planifiées est purgé chaque nuit : seules les
-- exécutions terminées depuis plus de sept jours disparaissent.

select is(
  (select count(*)::int from cron.job where jobname = 'purge-cron-job-run-details'),
  1,
  'la purge du journal des tâches planifiées est programmée une seule fois'
);

select is(
  (
    select schedule || ' | ' || command
    from cron.job
    where jobname = 'purge-cron-job-run-details'
  ),
  '23 3 * * * | delete from cron.job_run_details where end_time < now() - interval ''7 days''',
  'la purge tourne chaque nuit et ne vise que les exécutions de plus de sept jours'
);

select ok(
  (select active from cron.job where jobname = 'purge-cron-job-run-details'),
  'la tâche de purge est active'
);

insert into cron.job_run_details (
  jobid, runid, job_pid, database, username, command, status,
  return_message, start_time, end_time
) values
  (0, -910001, 1, current_database(), 'postgres', 'select 1', 'succeeded', '1 row',
   now() - interval '8 days', now() - interval '8 days'),
  (0, -910002, 1, current_database(), 'postgres', 'select 1', 'succeeded', '1 row',
   now() - interval '6 days', now() - interval '6 days'),
  (0, -910003, 1, current_database(), 'postgres', 'select 1', 'running', null,
   now() - interval '9 days', null);

do $$
begin
  execute (
    select command from cron.job where jobname = 'purge-cron-job-run-details'
  );
end
$$;

select is(
  (select count(*)::int from cron.job_run_details where runid = -910001),
  0,
  'une exécution terminée il y a plus de sept jours est supprimée'
);

select is(
  (select count(*)::int from cron.job_run_details where runid = -910002),
  1,
  'une exécution de moins de sept jours est conservée'
);

select is(
  (select count(*)::int from cron.job_run_details where runid = -910003),
  1,
  'une exécution sans fin enregistrée est conservée'
);

select * from finish();
rollback;
