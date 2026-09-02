begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select like(
  pg_get_functiondef('public.push_prediction_j5_notifications()'::regprocedure),
  '%m.match_type <> ''entre_nous''%',
  'le scheduler J-5 exclut explicitement les matchs entre nous'
);

select like(
  pg_get_functiondef('public.internal_push_dispatch(text,uuid)'::regprocedure),
  '%p_kind = ''prediction_j5'' and v_match.match_type = ''entre_nous''%',
  'le dispatcher bloque aussi les rappels de pronostic entre nous en defense en profondeur'
);

select * from finish();
rollback;
