-- Le rappel « Pense à pronostiquer » part le jour du match à 16 h
-- (Europe/Paris), ni avant ni après. Il remplace le rappel J-5 à 12 h.
--
-- Le nom du job, de la fonction et du type de notification (`prediction_j5`)
-- restent inchangés : le cron, l'Edge Function send-push et l'écran de test
-- des notifications s'appuient dessus.
begin;

create or replace function private.match_prediction_notification_at(
  p_kickoff_at timestamptz
)
returns timestamptz
language sql
stable
strict
set search_path = ''
as $function$
  select (
    ((p_kickoff_at at time zone 'Europe/Paris')::date + time '16:00')
    at time zone 'Europe/Paris'
  );
$function$;

comment on function private.match_prediction_notification_at(timestamptz) is
  'Heure du rappel de pronostic : le jour du match à 16 h Europe/Paris.';

create or replace function public.push_prediction_j5_notifications()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match record;
  v_sent integer := 0;
begin
  if private.is_feature_enabled('notifications_paused') then
    return 0;
  end if;

  -- Le cron tourne chaque minute. La fenêtre de 10 minutes ne sert qu'à
  -- rattraper une exécution manquée : passé 16 h 10, le rappel n'est plus
  -- envoyé, et jamais après la fermeture des pronostics (T-15).
  for v_match in
    select m.id
    from public.matches m
    where m.status = 'a_venir'
      and m.match_type <> 'entre_nous'
      and m.kickoff_at is not null
      and now() >= private.match_prediction_notification_at(m.kickoff_at)
      and now() < private.match_prediction_notification_at(m.kickoff_at)
        + interval '10 minutes'
      and now() < private.match_prediction_closes_at(m.kickoff_at)
      and (m.predictions_closed_at is null or now() < m.predictions_closed_at)
    order by m.kickoff_at
  loop
    insert into public.push_notification_log(match_id, kind, sent_at)
    values (v_match.id, 'prediction_j5', now())
    on conflict do nothing;
    if found then
      perform public.internal_push_notify('prediction_j5', v_match.id);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$function$;

commit;
