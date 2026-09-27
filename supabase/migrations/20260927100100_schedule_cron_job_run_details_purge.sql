begin;

-- Le journal des tâches planifiées (`cron.job_run_details`) n'était jamais
-- vidé. Six tâches tournent chaque minute : en production, le 27 septembre
-- 2026, il comptait environ 370 000 lignes pour 71 Mo, sur une base de 100 Mo,
-- et gagnait près de 7 600 lignes par jour. L'offre gratuite de Supabase
-- plafonne la base à 500 Mo.
--
-- Une purge quotidienne garde les sept derniers jours : c'est assez pour
-- diagnostiquer une tâche en échec, et le journal cesse de grossir. Une ligne
-- encore en cours n'a pas d'`end_time` : elle n'est jamais supprimée.
--
-- La migration peut être rejouée : la tâche est déprogrammée si elle existe,
-- puis reprogrammée à l'identique.

do $$
begin
  if exists (
    select 1 from cron.job where jobname = 'purge-cron-job-run-details'
  ) then
    perform cron.unschedule('purge-cron-job-run-details');
  end if;
end
$$;

select cron.schedule(
  'purge-cron-job-run-details',
  '23 3 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$
);

commit;
