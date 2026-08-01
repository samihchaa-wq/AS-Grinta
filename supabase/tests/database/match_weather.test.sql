begin;
\ir ../../migrations/20260802050000_match_weather.sql

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'aa000000-0000-0000-0000-000000000001',
    'weather-active@example.invalid',
    '{"first_name":"Meteo","last_name":"Active"}'::jsonb
  ),
  (
    'aa000000-0000-0000-0000-000000000002',
    'weather-pending@example.invalid',
    '{"first_name":"Meteo","last_name":"Pending"}'::jsonb
  );

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
values (
  'aa200000-0000-0000-0000-000000000001',
  'Météo FC',
  '12 rue Extérieure, 31000 Toulouse'
);

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

select is((select count(*) from public.internal_match_weather_candidates(null,timestamptz '2040-01-01 12:00:00+00') where match_id='aa300000-0000-0000-0000-000000000001'),0::bigint,'un match à J-7 ne déclenche aucun appel météo');
select is((select count(*) from public.internal_match_weather_candidates(null,timestamptz '2040-01-01 12:00:00+00') where match_id='aa300000-0000-0000-0000-000000000002'),1::bigint,'un match entre dans le pipeline exactement à J-6');
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
