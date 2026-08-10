begin;

-- Les pronostics de saison restent privés tant que la saison n'est pas
-- verrouillée. L'écran de saisie recharge déjà les données du joueur après sa
-- propre sauvegarde, et le verrouillage de la saison (table seasons) déclenche
-- ensuite le refresh global qui rend les pronostics et points visibles à tous.
-- Éviter le signal global ici supprime donc un fanout inutile à chaque ligne
-- enregistrée sans changer le comportement observable.
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

commit;
