begin;

-- Les modules Flutter lisent plusieurs vues/tables mises en cache. Ce signal
-- public-safe ne contient aucune donnée métier : il sert uniquement à annoncer
-- qu'une écriture partagée vient d'être validée afin que les clients actifs
-- rechargent leurs données autoritaires via les RPC et SELECT habituels.
create table if not exists public.shared_data_change_signals (
  key text primary key,
  revision bigint not null default 1,
  updated_at timestamptz not null default now(),
  constraint shared_data_change_signals_key_format
    check (key ~ '^[a-z][a-z0-9_]*$'),
  constraint shared_data_change_signals_revision_positive
    check (revision > 0)
);

comment on table public.shared_data_change_signals is
  'Public-safe Realtime revision used to refresh shared Flutter module caches.';

alter table public.shared_data_change_signals enable row level security;
revoke all on table public.shared_data_change_signals
  from public, anon, authenticated;
grant select on table public.shared_data_change_signals
  to authenticated, service_role;

drop policy if exists shared_data_change_signals_active_read
  on public.shared_data_change_signals;
create policy shared_data_change_signals_active_read
on public.shared_data_change_signals
for select
to authenticated
using ((select private.is_active_profile()));

insert into public.shared_data_change_signals(key, revision, updated_at)
values ('global', 1, now())
on conflict (key) do nothing;

create or replace function private.signal_shared_data_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.shared_data_change_signals(key, revision, updated_at)
  values ('global', 1, now())
  on conflict (key) do update
  set revision = public.shared_data_change_signals.revision + 1,
      updated_at = excluded.updated_at;
  return null;
end;
$function$;

revoke execute on function private.signal_shared_data_change()
  from public, anon, authenticated;

-- Une seule notification par instruction SQL, même lorsqu'une finalisation
-- met à jour plusieurs dizaines de joueurs. Les tables du mode Live ne sont
-- volontairement pas ici : elles ont déjà leurs flux Realtime dédiés et sont
-- beaucoup plus bavardes pendant un match.
do $block$
declare
  v_table text;
begin
  foreach v_table in array array[
    'matches',
    'match_odds',
    'opponents',
    'seasons',
    'season_players',
    'profiles',
    'match_player_stats',
    'match_attendance',
    'match_man_of_match',
    'profile_badges',
    'badges',
    'season_predictions',
    'guest_players',
    'match_compositions',
    'match_composition_entries',
    'match_composition_publications',
    'match_internal_compositions',
    'match_internal_composition_entries',
    'sport_waitlist_entries',
    'match_sport_participants',
    'match_sport_workflows',
    'match_sport_finalizations',
    'match_sport_motm_results'
  ]
  loop
    if to_regclass('public.' || v_table) is null then
      raise exception 'shared data sync: table %.% is missing', 'public', v_table;
    end if;

    execute format(
      'drop trigger if exists trg_shared_data_change on public.%I',
      v_table
    );
    execute format(
      'create trigger trg_shared_data_change '
      'after insert or update or delete on public.%I '
      'for each statement execute function private.signal_shared_data_change()',
      v_table
    );
  end loop;
end;
$block$;

-- Un seul flux Realtime remplace l'abonnement direct à toutes les tables métier.
do $block$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shared_data_change_signals'
  ) then
    alter publication supabase_realtime
      add table public.shared_data_change_signals;
  end if;
end;
$block$;

commit;
