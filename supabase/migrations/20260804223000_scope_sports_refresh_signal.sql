begin;

-- Les écritures de disponibilité et de composition ne nécessitent pas de
-- recharger les classements, badges, statistiques ou pronostics. Ce compteur
-- permet aux clients récents de reconnaître un lot composé uniquement de ces
-- écritures, tandis que les anciens clients continuent d'utiliser revision.
alter table public.shared_data_change_signals
  add column if not exists sports_revision bigint;

update public.shared_data_change_signals
set sports_revision = revision
where sports_revision is null;

alter table public.shared_data_change_signals
  alter column sports_revision set default 1,
  alter column sports_revision set not null;

do $block$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.shared_data_change_signals'::regclass
      and conname = 'shared_data_change_signals_sports_revision_valid'
  ) then
    alter table public.shared_data_change_signals
      add constraint shared_data_change_signals_sports_revision_valid
      check (sports_revision > 0 and sports_revision <= revision);
  end if;
end;
$block$;

comment on column public.shared_data_change_signals.sports_revision is
  'Revision incremented for availability, selection and composition changes.';

create or replace function private.signal_shared_data_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile_increment bigint := 0;
  v_sports_increment bigint := 0;
begin
  if tg_table_schema = 'public' and tg_table_name = 'profiles' then
    v_profile_increment := 1;
  end if;

  if tg_table_schema = 'public' and tg_table_name = any (array[
    'guest_players',
    'match_compositions',
    'match_composition_entries',
    'match_composition_publications',
    'sport_waitlist_entries',
    'match_sport_participants',
    'match_sport_workflows'
  ]) then
    v_sports_increment := 1;
  end if;

  insert into public.shared_data_change_signals(
    key,
    revision,
    profile_revision,
    sports_revision,
    updated_at
  )
  values ('global', 1, 1, 1, now())
  on conflict (key) do update
  set revision = public.shared_data_change_signals.revision + 1,
      profile_revision =
        public.shared_data_change_signals.profile_revision
        + v_profile_increment,
      sports_revision =
        public.shared_data_change_signals.sports_revision
        + v_sports_increment,
      updated_at = excluded.updated_at;
  return null;
end;
$function$;

revoke execute on function private.signal_shared_data_change()
  from public, anon, authenticated;

commit;
