begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Comme le test météo, ce contrat reconstruit la surface ajoutée par la
-- migration afin de rester indépendant de la liste manuelle de migrations du
-- bootstrap CI. Le fichier de migration est contrôlé séparément côté Flutter.
create table public.shared_data_change_signals (
  key text primary key,
  revision bigint not null default 1,
  updated_at timestamptz not null default now(),
  constraint shared_data_change_signals_key_format
    check (key ~ '^[a-z][a-z0-9_]*$'),
  constraint shared_data_change_signals_revision_positive
    check (revision > 0)
);

-- Le bootstrap métier CI n'installe pas tout le catalogue réellement présent
-- en production. Une table minimale suffit ici pour le seul objet encore absent.
-- Les compositions internes font désormais partie de la baseline CI afin que
-- le durcissement courant soit testé sur leur vrai schéma et leurs vraies RLS.
create table public.badges (
  id uuid primary key
);

alter table public.shared_data_change_signals enable row level security;
revoke all on table public.shared_data_change_signals
  from public, anon, authenticated;
grant select on table public.shared_data_change_signals
  to authenticated, service_role;

create policy shared_data_change_signals_active_read
on public.shared_data_change_signals
for select
to authenticated
using ((select private.is_active_profile()));

insert into public.shared_data_change_signals(key, revision, updated_at)
values ('global', 1, now());

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
    execute format(
      'create trigger trg_shared_data_change '
      'after insert or update or delete on public.%I '
      'for each statement execute function private.signal_shared_data_change()',
      v_table
    );
  end loop;
end;
$block$;

do $block$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    alter publication supabase_realtime
      add table public.shared_data_change_signals;
  end if;
end;
$block$;

select ok(
  to_regclass('public.shared_data_change_signals') is not null,
  'la table de signal inter-modules existe'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.shared_data_change_signals'::regclass
  ),
  'la RLS est active sur le signal inter-modules'
);

select ok(
  not has_table_privilege(
    'anon', 'public.shared_data_change_signals', 'SELECT'
  )
  and has_table_privilege(
    'authenticated', 'public.shared_data_change_signals', 'SELECT'
  )
  and not has_table_privilege(
    'authenticated', 'public.shared_data_change_signals', 'INSERT'
  )
  and not has_table_privilege(
    'authenticated', 'public.shared_data_change_signals', 'UPDATE'
  )
  and not has_table_privilege(
    'authenticated', 'public.shared_data_change_signals', 'DELETE'
  ),
  'les clients authentifiés ne peuvent que lire le signal'
);

select ok(
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shared_data_change_signals'
  ),
  'le signal est publié dans Supabase Realtime'
);

select ok(
  not has_function_privilege(
    'anon', 'private.signal_shared_data_change()', 'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated', 'private.signal_shared_data_change()', 'EXECUTE'
  ),
  'la fonction de signal ne peut pas être appelée directement par un client'
);

select is(
  (
    select count(*)
    from pg_trigger trigger
    join pg_class table_class on table_class.oid = trigger.tgrelid
    join pg_namespace namespace on namespace.oid = table_class.relnamespace
    where namespace.nspname = 'public'
      and trigger.tgname = 'trg_shared_data_change'
      and not trigger.tgisinternal
  ),
  23::bigint,
  'les 23 tables partagées critiques déclenchent le signal'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'fb000000-0000-0000-0000-000000000001',
    'sync-active@example.invalid',
    '{"first_name":"Active","last_name":"Sync"}'::jsonb
  ),
  (
    'fb000000-0000-0000-0000-000000000002',
    'sync-pending@example.invalid',
    '{"first_name":"Pending","last_name":"Sync"}'::jsonb
  );

update public.profiles
set status = case
      when id = 'fb000000-0000-0000-0000-000000000001' then 'active'
      else 'pending'
    end,
    updated_at = now()
where id in (
  'fb000000-0000-0000-0000-000000000001',
  'fb000000-0000-0000-0000-000000000002'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"fb000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from public.shared_data_change_signals),
  0::bigint,
  'un compte en attente ne peut pas écouter les changements métier'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"fb000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from public.shared_data_change_signals where key = 'global'),
  1::bigint,
  'un joueur actif peut écouter le signal sans voir de donnée métier'
);

reset role;
select set_config(
  'test.shared_revision_before',
  (
    select revision::text
    from public.shared_data_change_signals
    where key = 'global'
  ),
  true
);

insert into public.opponents(name)
values ('Signal inter-modules pgTAP');

select ok(
  (
    select revision
    from public.shared_data_change_signals
    where key = 'global'
  ) > current_setting('test.shared_revision_before')::bigint,
  'une écriture métier incrémente la révision globale'
);

select * from finish();
rollback;
