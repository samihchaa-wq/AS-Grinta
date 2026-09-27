begin;

select plan(7);

select is(
  private.match_prediction_closes_at(timestamptz '2026-09-28 19:00:00+00'),
  timestamptz '2026-09-28 17:00:00+00',
  'le match du 28/09 à 21h Paris bascule Live/pronos/verrou à 19h Paris'
);

select is(
  private.match_prediction_closes_at(timestamptz '2026-09-29 19:00:00+00'),
  timestamptz '2026-09-29 18:45:00+00',
  'toute autre rencontre conserve T-15'
);

select ok(
  position(
    'private.match_prediction_closes_at(v_kickoff_at)' in
    pg_get_functiondef(
      'private.open_match_live_workspace(uuid,integer)'::regprocedure
    )
  ) > 0,
  'ouvrir le Tableau Blanc utilise la frontière commune'
);

select ok(
  position(
    'private.match_prediction_closes_at(v_kickoff_at)' in
    pg_get_functiondef(
      'private.confirm_start_match_live(uuid,text)'::regprocedure
    )
  ) > 0,
  'démarrer le Live utilise la frontière commune'
);

select ok(
  position(
    'private.match_prediction_closes_at(v_kickoff_at)' in
    pg_get_functiondef(
      'public.admin_save_match_composition(uuid,text,jsonb,boolean,text,integer)'::regprocedure
    )
  ) > 0,
  'sauvegarder la composition utilise la frontière commune'
);

select ok(
  position(
    'private.match_prediction_closes_at(v_kickoff_at)' in
    pg_get_functiondef(
      'public.admin_publish_match_composition(uuid,boolean,text)'::regprocedure
    )
  ) > 0,
  'publier la composition utilise la frontière commune'
);

select ok(
  position(
    'private.match_prediction_closes_at(v_kickoff_at)' in
    pg_get_functiondef(
      'public.admin_remove_match_guest(uuid,uuid,text)'::regprocedure
    )
  ) > 0,
  'retirer un invité utilise la frontière commune'
);

select * from finish();
rollback;
