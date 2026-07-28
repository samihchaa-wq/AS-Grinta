begin;

set local search_path = public, extensions, pg_catalog;
select plan(7);

select ok(
  position(
    'private.save_match_effectif' in
    pg_get_functiondef(
      'private.save_match_squad_plan(uuid,text,jsonb,text)'::regprocedure
    )
  ) > 0,
  'le plan unifié enregistre désormais un brouillon d’effectif'
);

select ok(
  position(
    'private.save_match_composition' in
    pg_get_functiondef(
      'private.save_match_squad_plan(uuid,text,jsonb,text)'::regprocedure
    )
  ) > 0,
  'le plan unifié enregistre aussi un brouillon de composition'
);

select ok(
  position(
    'update public.match_sport_participants' in
    lower(pg_get_functiondef(
      'private.save_match_squad_plan(uuid,text,jsonb,text)'::regprocedure
    ))
  ) = 0,
  'l’enregistrement unifié ne publie plus directement les convocations'
);

select ok(
  position(
    'private.publish_match_effectif' in
    pg_get_functiondef(
      'private.publish_match_squad_plan(uuid,text,jsonb,text)'::regprocedure
    )
  ) > 0,
  'la publication unifiée publie explicitement l’effectif'
);

select ok(
  position(
    'private.publish_match_composition' in
    pg_get_functiondef(
      'private.publish_match_squad_plan(uuid,text,jsonb,text)'::regprocedure
    )
  ) > 0,
  'la publication unifiée publie ensuite la composition'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.admin_save_match_squad_plan(uuid,text,jsonb,text)'::regprocedure
  ),
  false,
  'le RPC public de brouillon reste SECURITY INVOKER'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.admin_publish_match_squad_plan(uuid,text,jsonb,text)'::regprocedure
  ),
  false,
  'le RPC public de publication reste SECURITY INVOKER'
);

select * from finish();
rollback;
