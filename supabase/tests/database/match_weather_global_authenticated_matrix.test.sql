begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- `supabase test db` mounts the test files but does not expose the repository
-- migration directory to psql. Recreate the migration's query/security surface
-- here so the isolated contract remains executable; the migration itself is
-- independently protected by the migration guard.
create table public.match_weather (
  match_id uuid primary key references public.matches(id) on delete cascade,
  forecast_for timestamptz not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  geocoded_address text not null check (char_length(geocoded_address) between 1 and 500),
  timezone text,
  temperature numeric,
  apparent_temperature numeric,
  precipitation_probability integer check (
    precipitation_probability is null
    or precipitation_probability between 0 and 100
  ),
  weather_code integer,
  wind_speed numeric check (wind_speed is null or wind_speed >= 0),
  wind_gusts numeric check (wind_gusts is null or wind_gusts >= 0),
  humidity integer check (humidity is null or humidity between 0 and 100),
  hourly_forecast jsonb not null default '[]'::jsonb
    check (jsonb_typeof(hourly_forecast) = 'array'),
  source text not null default 'open-meteo' check (source = 'open-meteo'),
  fetched_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.match_weather enable row level security;
revoke all on table public.match_weather from public, anon, authenticated;
grant select on table public.match_weather to authenticated;
grant all on table public.match_weather to service_role;

create policy match_weather_active_profile_select
on public.match_weather
for select
to authenticated
using ((select private.is_active_profile()));

create or replace function private.match_weather_refresh_interval(
  p_kickoff_at timestamptz,
  p_now timestamptz
)
returns interval
language sql
immutable
set search_path = ''
as $function$
  select case
    when p_kickoff_at - p_now > interval '72 hours' then interval '12 hours'
    when p_kickoff_at - p_now > interval '24 hours' then interval '6 hours'
    when p_kickoff_at - p_now > interval '6 hours' then interval '2 hours'
    else interval '1 hour'
  end;
$function$;

revoke all on function private.match_weather_refresh_interval(timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function private.match_weather_refresh_interval(timestamptz, timestamptz)
  to service_role;

create or replace function private.match_features_open_at(
  p_kickoff_at timestamptz
)
returns timestamptz
language sql
stable
strict
set search_path = ''
as $function$
  select (
    ((p_kickoff_at at time zone 'Europe/Paris')::date - 6) + time '12:00'
  ) at time zone 'Europe/Paris';
$function$;

revoke all on function private.match_features_open_at(timestamptz)
  from public, anon, authenticated;

create or replace function public.internal_match_weather_candidates(
  p_match_id uuid default null,
  p_now timestamptz default now()
)
returns table (
  match_id uuid,
  kickoff_at timestamptz,
  planned_duration_minutes integer,
  resolved_address text,
  cached_latitude double precision,
  cached_longitude double precision,
  cached_geocoded_address text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    match.id,
    match.kickoff_at,
    match.planned_duration_minutes,
    address.resolved_address,
    weather.latitude,
    weather.longitude,
    weather.geocoded_address
  from public.matches match
  left join public.opponents opponent on opponent.id = match.opponent_id
  left join public.club_settings club on club.id
  left join public.match_weather weather on weather.match_id = match.id
  cross join lateral (
    select coalesce(
      nullif(btrim(match.address), ''),
      case
        when match.location = 'domicile' then nullif(btrim(club.home_address), '')
        else nullif(btrim(opponent.address), '')
      end
    ) as resolved_address
  ) address
  where match.status = 'a_venir'
    and match.kickoff_at is not null
    and match.kickoff_at > p_now
    and private.match_features_open_at(match.kickoff_at) <= p_now
    and address.resolved_address is not null
    and (p_match_id is null or match.id = p_match_id)
    and (
      weather.match_id is null
      or weather.forecast_for is distinct from match.kickoff_at
      or weather.geocoded_address is distinct from address.resolved_address
      or weather.fetched_at is null
      or weather.fetched_at <= p_now - private.match_weather_refresh_interval(
        match.kickoff_at,
        p_now
      )
    )
  order by match.kickoff_at;
$function$;

revoke all on function public.internal_match_weather_candidates(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.internal_match_weather_candidates(uuid, timestamptz)
  to service_role;

do $do$
declare
  v_job_id bigint;
begin
  for v_job_id in select jobid from cron.job where jobname = 'match-weather-refresh'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
  perform cron.schedule(
    'match-weather-refresh',
    '*/15 * * * *',
    $cron$select 1;$cron$
  );
end;
$do$;

insert into auth.users(id, email, raw_user_meta_data)
values
  ('aa000000-0000-0000-0000-000000000001','weather-active@example.invalid','{"first_name":"Meteo","last_name":"Active"}'::jsonb),
  ('aa000000-0000-0000-0000-000000000002','weather-pending@example.invalid','{"first_name":"Meteo","last_name":"Pending"}'::jsonb);

update public.profiles
set status = case
      when id = 'aa000000-0000-0000-0000-000000000001' then 'active'
      else 'pending'
    end,
    role = 'pronostiqueur',
    updated_at = now()
where id in (
  'aa000000-0000-0000-0000-000000000001',
  'aa000000-0000-0000-0000-000000000002'
);

insert into public.seasons(id, name, status)
values ('aa100000-0000-0000-0000-000000000001', '2039-2040', 'open');

insert into public.opponents(id, name, address)
values ('aa200000-0000-0000-0000-000000000001','Météo FC','12 rue Extérieure, 31000 Toulouse');

update public.club_settings
set home_address = '1 rue du Stade, 31000 Toulouse'
where id;

insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, created_by, address
)
values
  ('aa300000-0000-0000-0000-000000000001','aa100000-0000-0000-0000-000000000001','aa200000-0000-0000-0000-000000000001',date '2040-01-08',time '13:00','domicile',90,'a_venir','aa000000-0000-0000-0000-000000000001',null),
  ('aa300000-0000-0000-0000-000000000002','aa100000-0000-0000-0000-000000000001','aa200000-0000-0000-0000-000000000001',date '2040-01-07',time '13:00','domicile',90,'a_venir','aa000000-0000-0000-0000-000000000001',null),
  ('aa300000-0000-0000-0000-000000000003','aa100000-0000-0000-0000-000000000001','aa200000-0000-0000-0000-000000000001',date '2040-01-06',time '13:00','exterieur',90,'a_venir','aa000000-0000-0000-0000-000000000001',null),
  ('aa300000-0000-0000-0000-000000000004','aa100000-0000-0000-0000-000000000001','aa200000-0000-0000-0000-000000000001',date '2040-01-05',time '13:00','domicile',90,'termine','aa000000-0000-0000-0000-000000000001',null);

update public.matches set kickoff_at = timestamptz '2040-01-08 12:00:00+00' where id = 'aa300000-0000-0000-0000-000000000001';
update public.matches set kickoff_at = timestamptz '2040-01-07 12:00:00+00' where id = 'aa300000-0000-0000-0000-000000000002';
update public.matches set kickoff_at = timestamptz '2040-01-06 12:00:00+00' where id = 'aa300000-0000-0000-0000-000000000003';
update public.matches set kickoff_at = timestamptz '2040-01-05 12:00:00+00' where id = 'aa300000-0000-0000-0000-000000000004';

select ok((select relrowsecurity from pg_class where oid = 'public.match_weather'::regclass),'RLS est active sur match_weather');
select ok(has_table_privilege('authenticated','public.match_weather','SELECT'),'authenticated possède le droit de lecture utile');
select ok(not has_table_privilege('authenticated','public.match_weather','INSERT') and not has_table_privilege('authenticated','public.match_weather','UPDATE') and not has_table_privilege('authenticated','public.match_weather','DELETE'),'authenticated ne peut pas écrire le cache météo');
select ok(not has_table_privilege('anon','public.match_weather','SELECT'),'anon ne peut pas lire le cache météo');
select ok(not has_function_privilege('authenticated','public.internal_match_weather_candidates(uuid,timestamptz)','EXECUTE'),'la RPC météo interne n’est pas exposée aux clients');
select ok(has_function_privilege('service_role','public.internal_match_weather_candidates(uuid,timestamptz)','EXECUTE'),'le worker serveur peut lire les candidats météo');

select is(private.match_weather_refresh_interval(timestamptz '2040-01-06 12:00:00+00',timestamptz '2040-01-01 12:00:00+00'),interval '12 hours','de J-6 à J-3 la météo est rafraîchie toutes les 12 heures');
select is(private.match_weather_refresh_interval(timestamptz '2040-01-03 12:00:00+00',timestamptz '2040-01-01 12:00:00+00'),interval '6 hours','de J-3 à J-1 la météo est rafraîchie toutes les 6 heures');
select is(private.match_weather_refresh_interval(timestamptz '2040-01-02 00:00:00+00',timestamptz '2040-01-01 12:00:00+00'),interval '2 hours','dans les dernières 24 heures la météo est rafraîchie toutes les 2 heures');
select is(private.match_weather_refresh_interval(timestamptz '2040-01-01 16:00:00+00',timestamptz '2040-01-01 12:00:00+00'),interval '1 hour','dans les six dernières heures la météo est rafraîchie chaque heure');

select is((select count(*) from public.internal_match_weather_candidates(null,timestamptz '2040-01-01 11:00:00+00') where match_id='aa300000-0000-0000-0000-000000000001'),0::bigint,'un match à J-7 ne déclenche aucun appel météo');
select is((select count(*) from public.internal_match_weather_candidates(null,timestamptz '2040-01-01 11:00:00+00') where match_id='aa300000-0000-0000-0000-000000000002'),1::bigint,'un match entre dans le pipeline exactement à J-6 à midi, heure de Paris');
select is((select resolved_address from public.internal_match_weather_candidates('aa300000-0000-0000-0000-000000000002',timestamptz '2040-01-01 12:00:00+00')),'1 rue du Stade, 31000 Toulouse','un match à domicile reprend l’adresse du club');
select is((select resolved_address from public.internal_match_weather_candidates('aa300000-0000-0000-0000-000000000003',timestamptz '2040-01-01 12:00:00+00')),'12 rue Extérieure, 31000 Toulouse','un match extérieur reprend l’adresse de l’adversaire');
select is((select count(*) from public.internal_match_weather_candidates('aa300000-0000-0000-0000-000000000004',timestamptz '2040-01-01 12:00:00+00')),0::bigint,'un match terminé ne déclenche jamais de météo');

insert into public.match_weather(match_id,forecast_for,latitude,longitude,geocoded_address,temperature,apparent_temperature,precipitation_probability,weather_code,wind_speed,wind_gusts,humidity,hourly_forecast,fetched_at,updated_at)
values ('aa300000-0000-0000-0000-000000000002',timestamptz '2040-01-07 12:00:00+00',43.6045,1.4440,'1 rue du Stade, 31000 Toulouse',16,14,65,61,22,35,78,'[{"forecast_at":"2040-01-07T12:00:00Z","label":"13h","temperature":16}]'::jsonb,timestamptz '2040-01-01 11:00:00+00',timestamptz '2040-01-01 11:00:00+00');

select is((select count(*) from public.internal_match_weather_candidates('aa300000-0000-0000-0000-000000000002',timestamptz '2040-01-01 12:00:00+00')),0::bigint,'un cache récent n’est pas rafraîchi inutilement');
update public.match_weather set fetched_at=timestamptz '2039-12-31 23:00:00+00' where match_id='aa300000-0000-0000-0000-000000000002';
select is((select count(*) from public.internal_match_weather_candidates('aa300000-0000-0000-0000-000000000002',timestamptz '2040-01-01 12:00:00+00')),1::bigint,'un cache arrivé à échéance redevient candidat');
update public.match_weather set fetched_at=timestamptz '2040-01-01 11:30:00+00',geocoded_address='Ancienne adresse' where match_id='aa300000-0000-0000-0000-000000000002';
select is((select count(*) from public.internal_match_weather_candidates('aa300000-0000-0000-0000-000000000002',timestamptz '2040-01-01 12:00:00+00')),1::bigint,'un changement d’adresse force un nouveau géocodage');
update public.match_weather set geocoded_address='1 rue du Stade, 31000 Toulouse',forecast_for=timestamptz '2040-01-07 11:00:00+00' where match_id='aa300000-0000-0000-0000-000000000002';
select is((select count(*) from public.internal_match_weather_candidates('aa300000-0000-0000-0000-000000000002',timestamptz '2040-01-01 12:00:00+00')),1::bigint,'un changement d’heure force une nouvelle prévision');
select is((select count(*) from cron.job where jobname='match-weather-refresh' and schedule='*/15 * * * *'),1::bigint,'un seul réveil météo serveur est planifié toutes les quinze minutes');

select set_config('request.jwt.claims','{"sub":"aa000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select is((select count(*) from public.match_weather),1::bigint,'un profil actif peut lire la météo');
select throws_ok($$insert into public.match_weather(match_id,forecast_for,latitude,longitude,geocoded_address) values ('aa300000-0000-0000-0000-000000000003',now(),43,1,'interdit')$$,'42501','un profil actif ne peut pas écrire directement la météo');
reset role;

select set_config('request.jwt.claims','{"sub":"aa000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select is((select count(*) from public.match_weather),0::bigint,'un compte en attente ne peut pas lire la météo');
reset role;

select * from finish();
rollback;