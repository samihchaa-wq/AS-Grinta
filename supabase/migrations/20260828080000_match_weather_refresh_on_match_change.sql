begin;

-- La météo d'un match n'était calculée que par le cron « match-weather-refresh »,
-- toutes les quinze minutes. Un match créé — ou déplacé — à l'intérieur de la
-- fenêtre J-6 restait donc sans prévision jusqu'au passage suivant du cron, et
-- la carte météo n'apparaissait pas dans la fiche du match.
--
-- On demande désormais un rafraîchissement immédiat dès que la date, l'adresse,
-- le lieu, l'adversaire ou le statut du match changent. La requête reste
-- asynchrone (pg_net) et `internal_match_weather_candidates` continue de filtrer
-- les appels inutiles : une prévision déjà fraîche ne déclenche aucun appel à
-- Open-Meteo.
create or replace function private.request_match_weather_refresh_on_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.status is distinct from 'a_venir'
     or new.kickoff_at is null
     or new.kickoff_at <= now()
     or private.match_features_open_at(new.kickoff_at) > now() then
    return null;
  end if;

  perform private.request_match_weather_refresh(new.id);
  return null;
exception
  when others then
    -- Une météo indisponible ne doit jamais faire échouer l'enregistrement
    -- du match lui-même.
    return null;
end;
$function$;

alter function private.request_match_weather_refresh_on_change() owner to postgres;

revoke all on function private.request_match_weather_refresh_on_change()
  from public, anon, authenticated;

drop trigger if exists trg_request_match_weather_refresh on public.matches;
create trigger trg_request_match_weather_refresh
after insert or update of kickoff_at, address, location, opponent_id, status
on public.matches
for each row
execute function private.request_match_weather_refresh_on_change();

commit;
