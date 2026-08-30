begin;
set local search_path = public, extensions, pg_catalog;
select plan(6);

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

select ok(
  position(
    'session.score_as_grinta' in pg_get_functiondef(
      'private.get_match_sport_report(uuid)'::regprocedure
    )
  ) > 0,
  'le brouillon reprend le score AS Grinta de la session Live'
);

select ok(
  position(
    'session.score_adverse' in pg_get_functiondef(
      'private.get_match_sport_report(uuid)'::regprocedure
    )
  ) > 0,
  'le brouillon reprend le score adverse de la session Live'
);

select ok(
  position(
    'not coalesce(v_live_exported, false)' in pg_get_functiondef(
      'private.get_match_sport_report(uuid)'::regprocedure
    )
  ) > 0,
  'la projection Live ne s applique qu avant la validation durable'
);

select * from finish();
rollback;
