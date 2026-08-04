begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'notify_motm_vote'
  )
  and exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'notify_convocation'
  ),
  'les préférences HDM et convocation existent'
);

select ok(
  to_regprocedure(
    'public.update_my_notification_preferences(boolean,boolean,boolean)'
  ) is not null,
  'la RPC des trois préférences facultatives existe'
);

select is(
  private.match_features_open_at('2026-08-15 18:00:00+00'::timestamptz),
  '2026-08-09 10:00:00+00'::timestamptz,
  'les disponibilités ouvrent à J-6 midi Europe/Paris'
);

select is(
  private.match_prediction_notification_at(
    '2026-08-15 18:00:00+00'::timestamptz
  ),
  '2026-08-10 10:00:00+00'::timestamptz,
  'le rappel prono est planifié à J-5 midi Europe/Paris'
);

select is(
  private.match_notification_time_label(
    '2026-08-15 18:00:00+00'::timestamptz
  ),
  '20h'::text,
  'le libellé horaire omet les minutes quand elles valent zéro'
);

select is(
  position(
    'availability_j3' in
    pg_get_functiondef(
      'private.process_sport_availability_notifications(timestamptz)'::regprocedure
    )
  ),
  0,
  'aucun rappel automatique de disponibilité J-3 ne subsiste'
);

select is(
  position(
    'availability_j1' in
    pg_get_functiondef(
      'private.process_sport_availability_notifications(timestamptz)'::regprocedure
    )
  ),
  0,
  'aucun rappel automatique de disponibilité J-1 ne subsiste'
);

select is(
  position(
    'motm_reminder' in
    pg_get_functiondef(
      'private.process_match_motm_jobs(timestamptz)'::regprocedure
    )
  ),
  0,
  'le job HDM ne pousse plus de rappel automatique'
);

select ok(
  position(
    'match_sport_finalizations' in lower(
      pg_get_functiondef('private.match_motm_opens_at(uuid)'::regprocedure)
    )
  ) > 0
  and position(
    'validated_at' in lower(
      pg_get_functiondef('private.match_motm_opens_at(uuid)'::regprocedure)
    )
  ) > 0
  and position(
    'interval ''1 hour 45 minutes''' in
    pg_get_functiondef('private.match_motm_opens_at(uuid)'::regprocedure)
  ) = 0,
  'l’ouverture HDM est ancrée à la validation du compte rendu'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.matches'::regclass
      and tgname = 'trg_notification_match_changes'
      and not tgisinternal
  ),
  'annulations et changements de date/heure sont surveillés côté serveur'
);

select ok(
  not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.matches'::regclass
      and tgname = 'trg_push_on_match_result'
      and not tgisinternal
  ),
  'le score final ne déclenche plus de push automatique'
);

select ok(
  not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.match_sport_motm_elections'::regclass
      and tgname = 'trg_push_on_motm_election_closed'
      and not tgisinternal
  ),
  'la fermeture HDM ne déclenche plus de notification de résultat'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.match_sport_participants'::regclass
      and tgname = 'trg_notify_waitlist_promotion'
      and not tgisinternal
  ),
  'la promotion liste d’attente vers convoqué est surveillée'
);

select is(
  (
    select count(*)::integer
    from cron.job
    where jobname = 'prediction-j5-reminders'
      and active
      and command = 'select public.push_prediction_j5_notifications();'
  ),
  1,
  'le cron de pronostic J-5 est actif'
);

select is(
  (
    select count(*)::integer
    from cron.job
    where jobname = 'prediction-closing-reminders'
      and active
  ),
  0,
  'l’ancien rappel de pronostic H-2 est désactivé'
);

select * from finish();
rollback;
