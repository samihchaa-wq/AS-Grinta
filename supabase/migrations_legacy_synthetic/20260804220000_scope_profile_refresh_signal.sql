begin;

-- Le signal global continue d'annoncer toutes les écritures partagées. Un
-- second compteur indique uniquement les écritures qui peuvent modifier le
-- profil authentifié (rôle, statut, identité ou photo). Les clients anciens
-- ignorent cette colonne et conservent donc leur comportement actuel.
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

comment on column public.shared_data_change_signals.profile_revision is
  'Revision incremented only when the public.profiles table changes.';

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

commit;
