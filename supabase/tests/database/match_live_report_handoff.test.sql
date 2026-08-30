begin;
set local search_path = public, extensions, pg_catalog;
select plan(9);

select ok(
  to_regprocedure('private.match_live_report_goal_actions_json(uuid)') is not null,
  'la projection des buts du Live vers le brouillon existe'
);

select ok(
  position(
    'match_live_events' in pg_get_functiondef(
      'private.match_live_report_goal_actions_json(uuid)'::regprocedure
    )
  ) > 0,
  'la projection lit le journal du Live'
);

select ok(
  position(
    'source_live_event_id' in pg_get_functiondef(
      'private.match_live_report_goal_actions_json(uuid)'::regprocedure
    )
  ) > 0,
  'chaque fait projeté garde son identité Live'
);

select has_column(
  'public',
  'match_live_events',
  'assist_participant_id',
  'le journal Live expose directement le participant passeur'
);

select ok(
  pg_get_functiondef(
    'private.match_live_report_goal_actions_json(uuid)'::regprocedure
  ) ~ 'event\.assist_participant_id'
  and pg_get_functiondef(
    'private.match_live_report_goal_actions_json(uuid)'::regprocedure
  ) !~ 'to_jsonb\(event\)',
  'la projection utilise la FK passeur canonique sans contournement JSON'
);

select ok(
  position(
    'score_as_grinta' in (
      select prosrc
      from pg_proc
      where oid = 'public.admin_get_match_sport_report(uuid)'::regprocedure
    )
  ) > 0,
  'le brouillon reprend le score AS Grinta de la session Live'
);

select ok(
  position(
    'score_adverse' in (
      select prosrc
      from pg_proc
      where oid = 'public.admin_get_match_sport_report(uuid)'::regprocedure
    )
  ) > 0,
  'le brouillon reprend le score adverse de la session Live'
);

select ok(
  position(
    'v_live_exported' in (
      select prosrc
      from pg_proc
      where oid = 'public.admin_get_match_sport_report(uuid)'::regprocedure
    )
  ) > 0,
  'la projection Live ne s applique qu avant la validation durable'
);

select ok(
  position(
    'private.is_admin()' in (
      select prosrc
      from pg_proc
      where oid = 'public.admin_get_match_sport_report(uuid)'::regprocedure
    )
  ) > 0,
  'la facade SECURITY DEFINER porte un garde d autorisation explicite'
);

select * from finish();
rollback;
