begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'coach_adjust_match_live_score'
      and proc.pronargs = 5
      and pg_get_function_arguments(proc.oid)
        like '%p_operation_id uuid%'
  ),
  'la RPC de score versionnee par operation_id existe'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.coach_adjust_match_live_score(uuid,text,integer,uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.coach_adjust_match_live_score(uuid,text,integer,uuid,uuid)',
    'EXECUTE'
  ),
  'seul un client authentifie peut appeler la RPC idempotente'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.adjust_match_live_score_idempotent(uuid,text,integer,uuid,uuid)',
    'EXECUTE'
  ),
  'le helper prive idempotent reste inaccessible directement au client'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'private.match_live_score_commands',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'private.match_live_score_commands',
    'INSERT'
  ),
  'le ledger d idempotence reste inaccessible directement au client'
);

select ok(
  (
    select relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private'
      and c.relname = 'match_live_score_commands'
  ),
  'le ledger d idempotence a RLS active'
);

insert into auth.users(id, email, raw_user_meta_data)
values (
  '43000000-0000-0000-0000-000000000001',
  'live-score-admin@example.invalid',
  '{"first_name":"Live","last_name":"Score"}'::jsonb
);

update public.profiles
set role = 'admin',
    status = 'active',
    updated_at = now()
where id = '43000000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = null
where key = 'sports_management';

insert into public.seasons(id, name, status)
values (
  '43000000-0000-0000-0000-000000000010',
  '2096-2097',
  'open'
);

insert into public.matches(
  id,
  season_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  status,
  created_by
)
values (
  '43000000-0000-0000-0000-000000000020',
  '43000000-0000-0000-0000-000000000010',
  current_date + 1,
  '20:00'::time,
  'domicile',
  90,
  'a_venir',
  '43000000-0000-0000-0000-000000000001'
);

insert into public.match_live_sessions(
  match_id,
  state,
  planned_duration_minutes,
  started_at,
  running_since,
  updated_by
)
values (
  '43000000-0000-0000-0000-000000000020',
  'running',
  90,
  now(),
  now(),
  '43000000-0000-0000-0000-000000000001'
);

set local role authenticated;
set local request.jwt.claim.sub = '43000000-0000-0000-0000-000000000001';

select is(
  (
    public.coach_adjust_match_live_score(
      '43000000-0000-0000-0000-000000000020',
      'us',
      1,
      null,
      '43000000-0000-0000-0000-000000000101'
    ) ->> 'score_as_grinta'
  )::integer,
  1,
  'le premier +1 est applique'
);

select is(
  (
    public.coach_adjust_match_live_score(
      '43000000-0000-0000-0000-000000000020',
      'us',
      1,
      null,
      '43000000-0000-0000-0000-000000000101'
    ) ->> 'score_as_grinta'
  )::integer,
  1,
  'rejouer exactement le meme +1 ne modifie pas le score deux fois'
);

select is(
  (
    select count(*)::integer
    from public.match_live_events
    where match_id = '43000000-0000-0000-0000-000000000020'
      and type = 'goal_us'
  ),
  1,
  'le retry du +1 ne cree pas de second evenement de but'
);

select throws_ok(
  $$select public.coach_adjust_match_live_score(
    '43000000-0000-0000-0000-000000000020',
    'them',
    1,
    null,
    '43000000-0000-0000-0000-000000000101'
  )$$,
  '22023',
  'un operation_id ne peut pas etre reutilise avec un autre payload'
);

select is(
  (
    public.coach_adjust_match_live_score(
      '43000000-0000-0000-0000-000000000020',
      'us',
      -1,
      null,
      '43000000-0000-0000-0000-000000000102'
    ) ->> 'score_as_grinta'
  )::integer,
  0,
  'le premier -1 est applique'
);

select is(
  (
    public.coach_adjust_match_live_score(
      '43000000-0000-0000-0000-000000000020',
      'us',
      -1,
      null,
      '43000000-0000-0000-0000-000000000102'
    ) ->> 'score_as_grinta'
  )::integer,
  0,
  'rejouer exactement le meme -1 ne decremente pas deux fois'
);

select is(
  (
    select count(*)::integer
    from public.match_live_events
    where match_id = '43000000-0000-0000-0000-000000000020'
      and type = 'goal_us'
  ),
  0,
  'le retry du -1 ne supprime pas un autre but'
);

select is(
  (
    public.coach_adjust_match_live_score(
      '43000000-0000-0000-0000-000000000020',
      'us',
      1,
      null,
      '43000000-0000-0000-0000-000000000103'
    ) ->> 'score_as_grinta'
  )::integer,
  1,
  'un nouvel operation_id applique une nouvelle commande'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select count(*)::integer
    from private.match_live_score_commands
    where actor_id = '43000000-0000-0000-0000-000000000001'
      and match_id = '43000000-0000-0000-0000-000000000020'
  ),
  3,
  'le ledger contient une ligne par action logique et aucune ligne de retry'
);

select * from finish();
rollback;
