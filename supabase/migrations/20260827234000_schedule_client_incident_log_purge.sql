begin;

-- La rétention de 90 jours du journal d'incidents client était écrite dans la
-- documentation et implémentée dans `private.purge_client_incident_log()`,
-- mais aucune tâche ne l'appelait : ni cron, ni fonction, ni Edge Function.
-- Le journal grossissait donc sans fin, et la durée de conservation annoncée
-- n'était appliquée nulle part.
--
-- La purge tourne une fois par jour : la fenêtre est de 90 jours, une
-- granularité horaire n'apporterait rien et ferait tourner une suppression
-- inutile toutes les heures.

select cron.schedule(
  'purge-client-incident-log',
  '17 3 * * *',
  'select private.purge_client_incident_log(now());'
);

commit;
