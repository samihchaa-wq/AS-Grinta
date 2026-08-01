import { createClient } from "npm:@supabase/supabase-js@2.95.0";

type WeatherCandidate = {
  match_id: string;
  kickoff_at: string;
  planned_duration_minutes: number;
  resolved_address: string;
  cached_latitude: number | null;
  cached_longitude: number | null;
  cached_geocoded_address: string | null;
};

type GeocodingResult = {
  latitude?: number;
  longitude?: number;
  timezone?: string;
  name?: string;
  admin1?: string;
  country?: string;
};

type GeocodingResponse = {
  results?: GeocodingResult[];
};

type ForecastResponse = {
  timezone?: string;
  hourly?: {
    time?: Array<number | string>;
    temperature_2m?: Array<number | null>;
    apparent_temperature?: Array<number | null>;
    precipitation_probability?: Array<number | null>;
    weather_code?: Array<number | null>;
    relative_humidity_2m?: Array<number | null>;
    wind_speed_10m?: Array<number | null>;
    wind_gusts_10m?: Array<number | null>;
  };
};

function finiteNumber(value: unknown): number | null {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : null;
}

function oneDecimal(value: unknown): number | null {
  const number = finiteNumber(value);
  return number == null ? null : Math.round(number * 10) / 10;
}

function boundedPercent(value: unknown): number | null {
  const number = finiteNumber(value);
  return number == null ? null : Math.min(100, Math.max(0, Math.round(number)));
}

async function fetchJson<T>(url: string): Promise<T> {
  const response = await fetch(url, { signal: AbortSignal.timeout(12_000) });
  if (!response.ok) {
    throw new Error(`Open-Meteo ${response.status}`);
  }
  return await response.json() as T;
}

function geocodingQueries(address: string): string[] {
  const trimmed = address.trim();
  const queries = [trimmed];

  // Open-Meteo geocoding searches place names rather than street addresses.
  // Fall back to the postal-code/city portion, then to the last comma segment.
  const postalCity = trimmed.match(/\b\d{4,6}\b\s+([^,]+)/)?.[0]?.trim();
  if (postalCity && postalCity !== trimmed) queries.push(postalCity);

  const segments = trimmed.split(",").map((part) => part.trim()).filter(Boolean);
  if (segments.length > 1) {
    const lastTwo = segments.slice(-2).join(" ");
    if (!queries.includes(lastTwo)) queries.push(lastTwo);
    const last = segments.at(-1)!;
    if (!queries.includes(last)) queries.push(last);
  }

  return [...new Set(queries)].slice(0, 4);
}

async function geocode(address: string): Promise<{
  latitude: number;
  longitude: number;
  timezone: string | null;
}> {
  for (const query of geocodingQueries(address)) {
    const url = new URL("https://geocoding-api.open-meteo.com/v1/search");
    url.searchParams.set("name", query);
    url.searchParams.set("count", "5");
    url.searchParams.set("language", "fr");
    url.searchParams.set("format", "json");

    const data = await fetchJson<GeocodingResponse>(url.toString());
    const result = data.results?.find((item) =>
      finiteNumber(item.latitude) != null && finiteNumber(item.longitude) != null
    );
    if (result) {
      return {
        latitude: Number(result.latitude),
        longitude: Number(result.longitude),
        timezone: typeof result.timezone === "string" ? result.timezone : null,
      };
    }
  }

  throw new Error(`Adresse météo introuvable: ${address}`);
}

function formatHour(epochSeconds: number, timezone: string): string {
  try {
    const parts = new Intl.DateTimeFormat("fr-FR", {
      timeZone: timezone,
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).formatToParts(new Date(epochSeconds * 1000));
    const hour = parts.find((part) => part.type === "hour")?.value ?? "";
    const minute = parts.find((part) => part.type === "minute")?.value ?? "00";
    return minute === "00" ? `${hour}h` : `${hour}h${minute}`;
  } catch {
    return new Date(epochSeconds * 1000).toISOString().slice(11, 16).replace(":00", "h");
  }
}

function at<T>(values: T[] | undefined, index: number): T | null {
  if (!values || index < 0 || index >= values.length) return null;
  return values[index] ?? null;
}

function nearestIndex(times: number[], target: number): number {
  let bestIndex = -1;
  let bestDelta = Number.POSITIVE_INFINITY;
  for (let index = 0; index < times.length; index += 1) {
    const delta = Math.abs(times[index] - target);
    if (delta < bestDelta) {
      bestDelta = delta;
      bestIndex = index;
    }
  }
  return bestIndex;
}

async function forecastForMatch(
  latitude: number,
  longitude: number,
  kickoffAt: string,
  plannedDurationMinutes: number,
): Promise<{
  timezone: string;
  temperature: number | null;
  apparentTemperature: number | null;
  precipitationProbability: number | null;
  weatherCode: number | null;
  windSpeed: number | null;
  windGusts: number | null;
  humidity: number | null;
  hourlyForecast: Array<Record<string, unknown>>;
}> {
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", latitude.toString());
  url.searchParams.set("longitude", longitude.toString());
  url.searchParams.set(
    "hourly",
    [
      "temperature_2m",
      "apparent_temperature",
      "precipitation_probability",
      "weather_code",
      "relative_humidity_2m",
      "wind_speed_10m",
      "wind_gusts_10m",
    ].join(","),
  );
  url.searchParams.set("wind_speed_unit", "kmh");
  url.searchParams.set("timezone", "auto");
  url.searchParams.set("timeformat", "unixtime");
  url.searchParams.set("forecast_days", "8");

  const data = await fetchJson<ForecastResponse>(url.toString());
  const hourly = data.hourly;
  if (!hourly?.time?.length) throw new Error("Prévision horaire vide");

  const times = hourly.time.map((value) => Number(value)).filter(Number.isFinite);
  if (times.length !== hourly.time.length) throw new Error("Horodatages météo invalides");

  const kickoffEpoch = Math.floor(new Date(kickoffAt).getTime() / 1000);
  if (!Number.isFinite(kickoffEpoch)) throw new Error("Coup d’envoi invalide");

  const mainIndex = nearestIndex(times, kickoffEpoch);
  if (mainIndex < 0) throw new Error("Créneau météo du coup d’envoi introuvable");

  const timezone = typeof data.timezone === "string" && data.timezone.trim()
    ? data.timezone
    : "UTC";
  const duration = Math.max(1, Number(plannedDurationMinutes) || 90);
  const stripStart = kickoffEpoch - 3600;
  const stripEnd = kickoffEpoch + duration * 60 + 3599;
  const hourlyForecast: Array<Record<string, unknown>> = [];

  for (let index = 0; index < times.length; index += 1) {
    const epoch = times[index];
    if (epoch < stripStart || epoch > stripEnd) continue;
    hourlyForecast.push({
      forecast_at: new Date(epoch * 1000).toISOString(),
      label: formatHour(epoch, timezone),
      temperature: oneDecimal(at(hourly.temperature_2m, index)),
      apparent_temperature: oneDecimal(at(hourly.apparent_temperature, index)),
      precipitation_probability: boundedPercent(
        at(hourly.precipitation_probability, index),
      ),
      weather_code: finiteNumber(at(hourly.weather_code, index)),
      wind_speed: oneDecimal(at(hourly.wind_speed_10m, index)),
      wind_gusts: oneDecimal(at(hourly.wind_gusts_10m, index)),
      humidity: boundedPercent(at(hourly.relative_humidity_2m, index)),
    });
  }

  // On very short/half-hour matches the range may contain too few whole-hour
  // points. Keep the three nearest slots as a useful minimum.
  if (hourlyForecast.length < 3) {
    const closest = times
      .map((epoch, index) => ({ epoch, index, delta: Math.abs(epoch - kickoffEpoch) }))
      .sort((a, b) => a.delta - b.delta)
      .slice(0, 3)
      .sort((a, b) => a.epoch - b.epoch);
    hourlyForecast.length = 0;
    for (const item of closest) {
      const index = item.index;
      hourlyForecast.push({
        forecast_at: new Date(item.epoch * 1000).toISOString(),
        label: formatHour(item.epoch, timezone),
        temperature: oneDecimal(at(hourly.temperature_2m, index)),
        apparent_temperature: oneDecimal(at(hourly.apparent_temperature, index)),
        precipitation_probability: boundedPercent(
          at(hourly.precipitation_probability, index),
        ),
        weather_code: finiteNumber(at(hourly.weather_code, index)),
        wind_speed: oneDecimal(at(hourly.wind_speed_10m, index)),
        wind_gusts: oneDecimal(at(hourly.wind_gusts_10m, index)),
        humidity: boundedPercent(at(hourly.relative_humidity_2m, index)),
      });
    }
  }

  return {
    timezone,
    temperature: oneDecimal(at(hourly.temperature_2m, mainIndex)),
    apparentTemperature: oneDecimal(at(hourly.apparent_temperature, mainIndex)),
    precipitationProbability: boundedPercent(
      at(hourly.precipitation_probability, mainIndex),
    ),
    weatherCode: finiteNumber(at(hourly.weather_code, mainIndex)),
    windSpeed: oneDecimal(at(hourly.wind_speed_10m, mainIndex)),
    windGusts: oneDecimal(at(hourly.wind_gusts_10m, mainIndex)),
    humidity: boundedPercent(at(hourly.relative_humidity_2m, mainIndex)),
    hourlyForecast,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response("configuration indisponible", { status: 500 });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: config, error: configError } = await supabase.rpc(
    "internal_push_config",
  );
  if (configError || !config?.token) {
    console.error("refresh-match-weather config failure", configError);
    return new Response("configuration indisponible", { status: 500 });
  }

  const token = req.headers.get("x-push-token") ?? "";
  if (token !== config.token) {
    return new Response("non autorisé", { status: 401 });
  }

  let body: { match_id?: string } = {};
  try {
    body = await req.json();
  } catch {
    // Cron wake-ups intentionally use an empty JSON body; an actually empty
    // body is harmless as well.
  }

  const requestedMatchId = typeof body.match_id === "string" && body.match_id.trim()
    ? body.match_id.trim()
    : null;
  const { data: candidatesRaw, error: candidatesError } = await supabase.rpc(
    "internal_match_weather_candidates",
    { p_match_id: requestedMatchId },
  );
  if (candidatesError) {
    console.error("refresh-match-weather candidates failure", candidatesError);
    return new Response("candidats indisponibles", { status: 500 });
  }

  const candidates = (candidatesRaw ?? []) as WeatherCandidate[];
  let refreshed = 0;
  let failed = 0;
  const failures: Array<{ match_id: string; error: string }> = [];

  for (const candidate of candidates) {
    try {
      let latitude = finiteNumber(candidate.cached_latitude);
      let longitude = finiteNumber(candidate.cached_longitude);

      if (
        latitude == null ||
        longitude == null ||
        candidate.cached_geocoded_address !== candidate.resolved_address
      ) {
        const location = await geocode(candidate.resolved_address);
        latitude = location.latitude;
        longitude = location.longitude;
      }

      const forecast = await forecastForMatch(
        latitude,
        longitude,
        candidate.kickoff_at,
        candidate.planned_duration_minutes,
      );

      const { error: upsertError } = await supabase.from("match_weather").upsert({
        match_id: candidate.match_id,
        forecast_for: candidate.kickoff_at,
        latitude,
        longitude,
        geocoded_address: candidate.resolved_address,
        timezone: forecast.timezone,
        temperature: forecast.temperature,
        apparent_temperature: forecast.apparentTemperature,
        precipitation_probability: forecast.precipitationProbability,
        weather_code: forecast.weatherCode,
        wind_speed: forecast.windSpeed,
        wind_gusts: forecast.windGusts,
        humidity: forecast.humidity,
        hourly_forecast: forecast.hourlyForecast,
        source: "open-meteo",
        fetched_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }, { onConflict: "match_id" });

      if (upsertError) throw upsertError;
      refreshed += 1;
    } catch (error) {
      failed += 1;
      const message = error instanceof Error ? error.message : String(error);
      console.error("refresh-match-weather match failure", candidate.match_id, message);
      failures.push({ match_id: candidate.match_id, error: message.slice(0, 200) });
      // Deliberately keep the previous cached row unchanged.
    }
  }

  return Response.json({
    candidates: candidates.length,
    refreshed,
    failed,
    failures,
  });
});
