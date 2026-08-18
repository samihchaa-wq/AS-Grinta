begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  has_function_privilege('authenticated','public.get_match_motm_vote(uuid)','EXECUTE')
  and has_function_privilege('authenticated','public.cast_match_motm_vote(uuid,uuid)','EXECUTE'),
  'authenticated keeps the public MOTM player RPCs'
);

select ok(
  has_function_privilege('authenticated','public.admin_get_match_motm_dashboard(uuid)','EXECUTE')
  and has_function_privilege('authenticated','public.admin_list_match_motm_votes()','EXECUTE')
  and has_function_privilege('authenticated','public.admin_cancel_match_motm_vote(uuid,text)','EXECUTE')
  and has_function_privilege('authenticated','public.admin_restart_match_motm_vote(uuid,text)','EXECUTE')
  and has_function_privilege('authenticated','public.admin_close_match_motm_vote_early(uuid,text)','EXECUTE'),
  'authenticated keeps the guarded public MOTM admin RPCs'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.oid::regprocedure::text = any(array[
        'private.get_match_motm_vote(uuid)',
        'private.cast_match_motm_vote(uuid,uuid)',
        'private.get_admin_match_motm_dashboard(uuid)',
        'private.list_admin_match_motm_votes()',
        'private.admin_cancel_match_motm_vote(uuid,text)',
        'private.admin_restart_match_motm_vote(uuid,text)',
        'private.admin_close_match_motm_vote_early(uuid,text)'
      ])
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ),
  0::bigint,
  'authenticated cannot execute MOTM private implementations directly'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.oid::regprocedure::text = any(array[
        'get_match_motm_vote(uuid)',
        'cast_match_motm_vote(uuid,uuid)',
        'admin_get_match_motm_dashboard(uuid)',
        'admin_list_match_motm_votes()',
        'admin_cancel_match_motm_vote(uuid,text)',
        'admin_restart_match_motm_vote(uuid,text)',
        'admin_close_match_motm_vote_early(uuid,text)'
      ])
      and p.prosecdef
      and coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""']
      and (
        pg_get_functiondef(p.oid) ~* 'private\\.is_active_profile\\s*\\('
        or pg_get_functiondef(p.oid) ~* 'private\\.is_admin\\s*\\('
      )
  ),
  7::bigint,
  'all seven public MOTM boundaries are guarded SECURITY DEFINER functions with empty search_path'
);

select * from finish();
rollback;
