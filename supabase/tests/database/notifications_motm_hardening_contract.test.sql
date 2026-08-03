begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  position(
    'match_sport_finalization_versions' in
    pg_get_functiondef('private.match_motm_opens_at(uuid)'::regprocedure)
  ) > 0
  and position(
    'interval ''2 hours''' in
    pg_get_functiondef('private.match_motm_opens_at(uuid)'::regprocedure)
  ) > 0
  and position(
    'greatest' in lower(
      pg_get_functiondef('private.match_motm_opens_at(uuid)'::regprocedure)
    )
  ) > 0,
  'le HDM ouvre après finalisation Stats/Live, jamais avant le coup d’envoi, sinon à H+2'
);

select ok(
  position(
    'interval ''24 hours''' in
    pg_get_functiondef('private.ensure_match_motm_election(uuid)'::regprocedure)
  ) > 0,
  'la fermeture HDM reste ancrée à H+24 après le coup d’envoi'
);

select ok(
  to_regprocedure('private.push_due_motm_reminders(timestamptz)') is null
  and to_regprocedure('public.push_on_motm_election_closed()') is null
  and to_regprocedure('public.push_on_match_result()') is null,
  'les anciens traitements automatiques HDM/résultat ont été supprimés'
);

select ok(
  position(
    'motm_reminder' in
    pg_get_functiondef('private.dispatch_motm_push(text,uuid)'::regprocedure)
  ) = 0
  and position(
    'motm_results' in
    pg_get_functiondef('private.dispatch_motm_push(text,uuid)'::regprocedure)
  ) = 0,
  'le transport HDM privé n’accepte plus les anciens types de rappel/résultat'
);

select ok(
  not (
    select procedure.prosecdef
    from pg_proc procedure
    where procedure.oid =
      'public.save_match_prediction(uuid,integer,integer,boolean)'::regprocedure
  )
  and has_function_privilege(
    'authenticated',
    'public.save_match_prediction(uuid,integer,integer,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.save_match_prediction(uuid,integer,integer,boolean)',
    'EXECUTE'
  ),
  'l’adaptateur historique du prono x2 est SECURITY INVOKER et réservé aux connectés'
);

select ok(
  to_regclass('public.match_internal_composition_entries_participant_match_idx') is not null
  and to_regclass('public.match_live_events_created_by_idx') is not null
  and to_regclass('public.match_live_events_player_in_participant_match_idx') is not null
  and to_regclass('public.match_live_events_player_out_participant_match_idx') is not null
  and to_regclass('public.match_live_events_scorer_participant_match_idx') is not null
  and to_regclass('public.match_live_sessions_updated_by_idx') is not null,
  'les clés étrangères chaudes disposent de leurs index de couverture'
);

select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'public'
      and tablename = 'match_internal_compositions'
      and permissive = 'PERMISSIVE'
      and 'authenticated' = any(roles)
      and cmd in ('SELECT', 'ALL')
  ),
  1,
  'la composition interne n’a plus deux policies permissives en lecture'
);

select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'public'
      and tablename = 'match_internal_composition_entries'
      and permissive = 'PERMISSIVE'
      and 'authenticated' = any(roles)
      and cmd in ('SELECT', 'ALL')
  ),
  1,
  'les entrées de composition interne n’ont plus deux policies permissives en lecture'
);

select ok(
  not (
    select convalidated
    from pg_constraint
    where conrelid = 'public.push_notification_log'::regclass
      and conname = 'push_notification_log_kind_check'
  )
  and position(
    'motm_results' in
    pg_get_constraintdef((
      select oid
      from pg_constraint
      where conrelid = 'public.push_notification_log'::regclass
        and conname = 'push_notification_log_kind_check'
    ))
  ) = 0
  and position(
    'result_validated' in
    pg_get_constraintdef((
      select oid
      from pg_constraint
      where conrelid = 'public.push_notification_log'::regclass
        and conname = 'push_notification_log_kind_check'
    ))
  ) = 0,
  'le journal de notifications conserve l’historique mais refuse les anciens types à l’avenir'
);

select ok(
  not (
    select convalidated
    from pg_constraint
    where conrelid = 'public.push_delivery_log'::regclass
      and conname = 'push_delivery_log_kind_check'
  )
  and position(
    'availability_j3' in
    pg_get_constraintdef((
      select oid
      from pg_constraint
      where conrelid = 'public.push_delivery_log'::regclass
        and conname = 'push_delivery_log_kind_check'
    ))
  ) = 0
  and position(
    'motm_reminder' in
    pg_get_constraintdef((
      select oid
      from pg_constraint
      where conrelid = 'public.push_delivery_log'::regclass
        and conname = 'push_delivery_log_kind_check'
    ))
  ) = 0,
  'le journal de livraison n’autorise plus les rappels automatiques retirés'
);

select * from finish();
rollback;
