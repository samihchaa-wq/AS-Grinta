begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Le bootstrap métier léger de la CI s'arrête à la dernière migration déjà
-- déployée. Cette copie transactionnelle de la migration en cours permet d'en
-- exercer le comportement puis est entièrement annulée à la fin du test.
alter table public.shared_data_change_signals
  add column if not exists profile_revision bigint;

update public.shared_data_change_signals
set profile_revision = revision
where profile_revision is null;

alter table public.shared_data_change_signals
  alter column profile_revision set default 1,
  alter column profile_revision set not null;

do $block$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.shared_data_change_signals'::regclass
      and conname = 'shared_data_change_signals_profile_revision_valid'
  ) then
    alter table public.shared_data_change_signals
      add constraint shared_data_change_signals_profile_revision_valid
      check (profile_revision > 0 and profile_revision <= revision);
  end if;
end;
$block$;

create or replace function private.signal_shared_data_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile_increment bigint := 0;
begin
  if tg_table_schema = 'public' and tg_table_name = 'profiles' then
    v_profile_increment := 1;
  end if;

  insert into public.shared_data_change_signals(
    key,
    revision,
    profile_revision,
    updated_at
  )
  values ('global', 1, 1, now())
  on conflict (key) do update
  set revision = public.shared_data_change_signals.revision + 1,
      profile_revision =
        public.shared_data_change_signals.profile_revision
        + v_profile_increment,
      updated_at = excluded.updated_at;
  return null;
end;
$function$;

revoke execute on function private.signal_shared_data_change()
  from public, anon, authenticated;

select ok(
  to_regclass('public.shared_data_change_signals') is not null,
  'la table de signal inter-modules existe'
);

select ok(
  exists (
    select 1
    from pg_attribute
    where attrelid = 'public.shared_data_change_signals'::regclass
      and attname = 'profile_revision'
      and attnum > 0
      and not attisdropped
      and attnotnull
  ),
  'le compteur dédié aux changements de profil existe et reste obligatoire'
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
    from pg_policies
    where schemaname = 'public'
      and tablename = 'shared_data_change_signals'
      and policyname = 'shared_data_change_signals_active_read'
      and roles = array['authenticated']::name[]
      and cmd = 'SELECT'
      and qual ~ 'private\.is_active_profile'
  ),
  'la lecture du signal reste limitée aux profils actifs'
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
select set_config(
  'test.profile_revision_before',
  (
    select profile_revision::text
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

select is(
  (
    select profile_revision
    from public.shared_data_change_signals
    where key = 'global'
  ),
  current_setting('test.profile_revision_before')::bigint,
  'une écriture hors profils ne demande pas de rechargement du profil'
);

select set_config(
  'test.shared_revision_after_opponent',
  (
    select revision::text
    from public.shared_data_change_signals
    where key = 'global'
  ),
  true
);
select set_config(
  'test.profile_revision_after_opponent',
  (
    select profile_revision::text
    from public.shared_data_change_signals
    where key = 'global'
  ),
  true
);

update public.profiles
set updated_at = clock_timestamp()
where id = 'fb000000-0000-0000-0000-000000000001';

select ok(
  (
    select revision
    from public.shared_data_change_signals
    where key = 'global'
  ) > current_setting('test.shared_revision_after_opponent')::bigint,
  'une écriture de profil continue d’incrémenter la révision globale'
);

select ok(
  (
    select profile_revision
    from public.shared_data_change_signals
    where key = 'global'
  ) > current_setting('test.profile_revision_after_opponent')::bigint,
  'une écriture de profil demande explicitement son rechargement'
);

select * from finish();
rollback;
