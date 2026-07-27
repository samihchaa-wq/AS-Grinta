begin;

do $block$
begin
  if exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'feature_flag_change_signals'
  ) then
    alter publication supabase_realtime
      drop table public.feature_flag_change_signals;
  end if;
end;
$block$;

drop trigger if exists trg_signal_feature_flag_change
  on private.app_feature_flags;
drop function if exists private.signal_feature_flag_change();
drop table if exists public.feature_flag_change_signals;

commit;
