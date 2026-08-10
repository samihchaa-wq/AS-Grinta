begin;

-- The canonical schema dump can inherit local extension/default ACLs that are
-- not present in production. Production exposes no public-schema data object
-- to PUBLIC/anon, so normalize that security floor on fresh installs.
revoke all privileges on all tables in schema public from public, anon;
revoke all privileges on all sequences in schema public from public, anon;

-- pg_dump recreates tables, policies and grants, but not Supabase Realtime
-- publication membership. Fresh installs must reproduce the five tables
-- published in production.
do $block$
declare
  v_table text;
begin
  if not exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    raise exception 'Supabase Realtime publication is missing';
  end if;

  foreach v_table in array array[
    'feature_flag_change_signals',
    'match_live_events',
    'match_live_sessions',
    'match_weather',
    'shared_data_change_signals'
  ]
  loop
    if to_regclass(format('public.%I', v_table)) is null then
      raise exception 'Realtime table public.% is missing', v_table;
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        v_table
      );
    end if;
  end loop;
end;
$block$;

commit;
