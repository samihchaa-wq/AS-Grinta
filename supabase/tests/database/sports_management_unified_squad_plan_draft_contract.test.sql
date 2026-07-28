begin;

-- Ce contrat garantit qu’enregistrer et publier restent deux actions distinctes.
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
    'unified_convocation_snapshot' in
    lower(pg_get_functiondef(
      'private.save_match_squad_plan(uuid,text,jsonb,text)'::regprocedure
    ))
  ) > 0
  and position(
    'snapshot.convocation_status' in
    lower(pg_get_functiondef(
      'private.save_match_squad_plan(uuid,text,jsonb,text)'::regprocedure
    ))
  ) > 0,
  'le brouillon restaure la dernière publication après validation interne'
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
