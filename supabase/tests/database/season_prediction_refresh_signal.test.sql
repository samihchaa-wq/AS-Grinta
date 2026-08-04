begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Le schéma métier de CI peut précéder la migration en cours. On reproduit
-- transactionnellement la nouvelle version de la fonction afin de tester son
-- comportement réel sans modifier le bootstrap partagé.
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
  if tg_table_schema = 'public' and tg_table_name = 'season_predictions' then
    return null;
  end if;

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

select ok(
  exists (
    select 1
    from pg_trigger trigger
    join pg_class table_class on table_class.oid = trigger.tgrelid
    join pg_namespace namespace on namespace.oid = table_class.relnamespace
    where namespace.nspname = 'public'
      and table_class.relname = 'season_predictions'
      and trigger.tgname = 'trg_shared_data_change'
      and not trigger.tgisinternal
  ),
  'le trigger season_predictions reste installé'
);

insert into auth.users(id, email, raw_user_meta_data)
values (
  'fb100000-0000-0000-0000-000000000001',
  'season-signal@example.invalid',
  '{"first_name":"Signal","last_name":"Season"}'::jsonb
);

update public.profiles
set status = 'active', updated_at = now()
where id = 'fb100000-0000-0000-0000-000000000001';

insert into public.seasons(id, name, status)
values (
  'fb100000-0000-0000-0000-000000000010',
  'Saison Signal pgTAP',
  'open'
);

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active
)
values (
  'fb100000-0000-0000-0000-000000000020',
  'fb100000-0000-0000-0000-000000000010',
  'Signal',
  'Player',
  false,
  true
);

select set_config(
  'test.shared_revision_before_prediction',
  (
    select revision::text
    from public.shared_data_change_signals
    where key = 'global'
  ),
  true
);

insert into public.season_predictions(
  season_id,
  predictor_profile_id,
  season_player_id,
  category,
  predicted_value_30,
  is_filled
)
values (
  'fb100000-0000-0000-0000-000000000010',
  'fb100000-0000-0000-0000-000000000001',
  'fb100000-0000-0000-0000-000000000020',
  'buts',
  12,
  true
);

select is(
  (
    select revision
    from public.shared_data_change_signals
    where key = 'global'
  ),
  current_setting('test.shared_revision_before_prediction')::bigint,
  'enregistrer un prono de saison ne déclenche plus le refresh global'
);

update public.season_predictions
set predicted_value_30 = 13,
    updated_at = clock_timestamp()
where season_id = 'fb100000-0000-0000-0000-000000000010'
  and predictor_profile_id = 'fb100000-0000-0000-0000-000000000001'
  and season_player_id = 'fb100000-0000-0000-0000-000000000020'
  and category = 'buts';

select is(
  (
    select revision
    from public.shared_data_change_signals
    where key = 'global'
  ),
  current_setting('test.shared_revision_before_prediction')::bigint,
  'modifier un prono de saison ne déclenche plus le refresh global'
);

select set_config(
  'test.shared_revision_before_season',
  (
    select revision::text
    from public.shared_data_change_signals
    where key = 'global'
  ),
  true
);

update public.seasons
set name = name
where id = 'fb100000-0000-0000-0000-000000000010';

select ok(
  (
    select revision
    from public.shared_data_change_signals
    where key = 'global'
  ) > current_setting('test.shared_revision_before_season')::bigint,
  'les changements de saison continuent de déclencher le refresh global'
);

select is(
  (
    select count(*)
    from public.season_predictions
    where season_id = 'fb100000-0000-0000-0000-000000000010'
      and predictor_profile_id = 'fb100000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'les pronostics sont bien enregistrés malgré la suppression du fanout'
);

select * from finish();
rollback;
