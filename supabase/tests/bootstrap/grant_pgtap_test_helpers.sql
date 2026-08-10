-- Test-only helpers applied after the canonical production schema has been
-- replayed in the isolated CI database. Production is never affected.

-- Some load scenarios deliberately disable triggers via
-- session_replication_role=replica. Supply the CI-only identity defaults needed
-- by those direct fixtures without changing production defaults.
\ir canonical_player_direct_fixture_defaults.sql

-- The tests deliberately switch roles while running pgTAP assertions.
grant usage on schema extensions to anon, authenticated;
grant execute on all functions in schema extensions to anon, authenticated;

-- Some scenarios create a pg_temp function before switching to authenticated.
-- Restore that default only inside the ephemeral test database.
alter default privileges grant execute on functions to authenticated;

-- Depending on the local image, a few pgTAP helpers can remain in public.
-- Grant only the assertion names used by this test suite.
do $block$
declare
  helper record;
begin
  for helper in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'extensions')
      and p.proname in (
        'plan', 'no_plan', 'finish', 'ok', 'is', 'isnt', 'pass', 'fail',
        'throws_ok', 'throws_like', 'throws_ilike', 'lives_ok', 'like',
        'unlike', 'cmp_ok', 'is_empty', 'isnt_empty', 'results_eq',
        'set_eq', 'bag_eq', 'row_eq', 'has_function', 'has_table',
        'has_column', 'has_policy', 'has_trigger', 'is_definer',
        'isnt_definer', 'function_privs_are', 'table_privs_are',
        'schema_privs_are', 'policies_are', 'col_type_is'
      )
  loop
    execute format(
      'grant execute on function %s to anon, authenticated',
      helper.signature
    );
  end loop;
end;
$block$;

-- Fail explicitly if the anon role still cannot execute any throws_ok overload.
do $block$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'extensions')
      and p.proname = 'throws_ok'
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'pgTAP throws_ok is not executable by anon in test database';
  end if;
end;
$block$;
