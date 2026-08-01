-- Cached match weather, available only inside the six-day upcoming-match window.
-- Forecast data is written by the protected internal Edge worker and read by active users.

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
  source text not null default 'open-meteo'
    check (source = 'open-meteo'),
  fetched_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.match_weather is
  'Server-cached Open-Meteo forecast for a match, refreshed only from J-6 until kickoff.';

create index match_weather_fetched_at_idx
  on public.match_weather(fetched_at);

alter table public.match_weather enable row level security;
revoke all on table public.match_weather from public, anon, authenticated;
grant select on table public.match_weather to authenticated;
grant all on table public.match_weather to service_role;

create policy match_weather_active_profile_select
on public.match_weather
for select
to authenticated
using ((select private.is_active_profile()));

-- Realtime is a signal only: Flutter receives the changed row and redraws the
-- cached forecast. No client receives permission to write weather data.
do $do$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'match_weather'
  ) then
    alter publication supabase_realtime add table public.match_weather;
  end if;
end;
$do$;

-- Centralise the refresh cadence so the server cannot accidentally request
-- forecasts for distant, cancelled or already played matches.
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

-- Internal read model consumed by the worker. It returns only matches that are
-- currently eligible AND whose cache is due for refresh.
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
    and match.kickoff_at <= p_now + interval '6 days'
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

-- Reuse the existing private server-to-server token used for protected Edge
-- calls. It never reaches Flutter and remains stored in Supabase Vault.
create or replace function private.request_match_weather_refresh(
  p_match_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token text;
  v_request_id bigint;
begin
  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return null;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := case
      when p_match_id is null then jsonb_build_object('kind', 'refresh_match_weather')
      else jsonb_build_object(
        'kind', 'refresh_match_weather',
        'match_id', p_match_id
      )
    end,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 15000
  ) into v_request_id;

  return v_request_id;
exception
  when others then
    -- Weather is strictly non-blocking: an external/API failure must never
    -- disturb match management or any other scheduled job.
    return null;
end;
$function$;

revoke all on function private.request_match_weather_refresh(uuid)
  from public, anon, authenticated;
grant execute on function private.request_match_weather_refresh(uuid)
  to service_role;

-- A lightweight wake-up every 15 minutes is enough to make weather appear
-- shortly after J-6. The candidate RPC enforces the actual 12h/6h/2h/1h API
-- refresh cadence, so most wake-ups perform zero external weather requests.
do $do$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'match-weather-refresh'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'match-weather-refresh',
    '*/15 * * * *',
    $cron$select private.request_match_weather_refresh(null);$cron$
  );
end;
$do$;
