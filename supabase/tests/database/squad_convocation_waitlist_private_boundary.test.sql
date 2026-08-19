begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

create temporary table pg_temp.private_targets(signature text primary key) on commit drop;
insert into pg_temp.private_targets(signature) values
  ('private.create_postmatch_composition(uuid,text,jsonb,boolean,text)'),
  ('private.finalize_match_waitlist_turns_internal(uuid,boolean)'),
  ('private.get_admin_match_composition(uuid)'),
  ('private.get_match_convocations(uuid)'),
  ('private.enrich_match_convocation_history(jsonb)'),
  ('private.get_sport_waitlist(uuid)'),
  ('private.enrich_sport_waitlist_history(jsonb)'),
  ('private.publish_match_composition(uuid,boolean,text)'),
  ('private.publish_match_convocations(uuid,text)'),
  ('private.publish_match_effectif(uuid,integer,jsonb,text)'),
  ('private.recompute_match_convocations_internal(uuid,boolean)'),
  ('private.reorder_sport_waitlist(uuid,uuid[],text)'),
  ('private.lock_match_composition_version(uuid,integer)'),
  ('private.save_match_composition(uuid,text,jsonb,boolean,text)'),
  ('private.set_match_convocation(uuid,uuid,text,boolean,text)'),
  ('private.update_postmatch_composition(uuid,text,jsonb,boolean,text)'),
  ('private.get_published_match_composition(uuid)'),
  ('private.get_sport_waitlist_readonly(uuid)');

create temporary table pg_temp.public_targets(signature text primary key) on commit drop;
insert into pg_temp.public_targets(signature) values
  ('public.admin_create_postmatch_composition(uuid,text,jsonb,boolean,text)'),
  ('public.admin_finalize_match_waitlist_turns(uuid)'),
  ('public.admin_get_match_composition(uuid)'),
  ('public.admin_get_match_convocations(uuid)'),
  ('public.admin_get_sport_waitlist(uuid)'),
  ('public.admin_publish_match_composition(uuid,boolean,text)'),
  ('public.admin_publish_match_convocations(uuid,text)'),
  ('public.admin_publish_match_effectif(uuid,integer,jsonb,text)'),
  ('public.admin_recompute_match_convocations(uuid,boolean)'),
  ('public.admin_reorder_sport_waitlist(uuid,uuid[],text)'),
  ('public.admin_save_match_composition(uuid,text,jsonb,boolean,text)'),
  ('public.admin_save_match_composition(uuid,text,jsonb,boolean,text,integer)'),
  ('public.admin_save_match_effectif(uuid,integer,jsonb,text)'),
  ('public.admin_set_match_convocation(uuid,uuid,text,boolean,text)'),
  ('public.admin_update_postmatch_composition(uuid,text,jsonb,boolean,text)'),
  ('public.get_published_match_composition(uuid)'),
  ('public.get_sport_waitlist(uuid)');

select is(
  (select count(*) from pg_temp.private_targets where to_regprocedure(signature) is not null),
  18::bigint,
  'all eighteen private squad/convocation/waitlist implementation functions exist'
);

select is(
  (
    select count(*)
    from pg_temp.private_targets
    where has_function_privilege('authenticated', to_regprocedure(signature), 'EXECUTE')
  ),
  0::bigint,
  'authenticated cannot execute squad/convocation/waitlist private implementations directly'
);

select is(
  (select count(*) from pg_temp.public_targets where to_regprocedure(signature) is not null),
  17::bigint,
  'all seventeen public squad/convocation/waitlist RPC signatures exist'
);

select is(
  (
    select count(*)
    from pg_temp.public_targets t
    join pg_proc p on p.oid = to_regprocedure(t.signature)
    where has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and p.prosecdef
      and coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""']
  ),
  17::bigint,
  'all seventeen public RPCs are authenticated-only SECURITY DEFINER boundaries with empty search_path'
);

select ok(
  position(
    'private.is_admin()'
    in pg_get_functiondef('public.admin_recompute_match_convocations(uuid,boolean)'::regprocedure)
  ) > 0,
  'admin recompute wrapper explicitly enforces the administrator gate'
);

select ok(
  position(
    'private.is_active_profile()'
    in pg_get_functiondef('private.get_published_match_composition(uuid)'::regprocedure)
  ) > 0,
  'published composition private reader retains active-profile authorization'
);

select ok(
  position(
    'private.is_active_profile()'
    in pg_get_functiondef('private.get_sport_waitlist_readonly(uuid)'::regprocedure)
  ) > 0,
  'readonly waitlist private reader retains active-profile authorization'
);

select * from finish();
rollback;
