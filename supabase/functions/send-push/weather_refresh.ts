import type { SupabaseClient } from "npm:@supabase/supabase-js@2.95.0";

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
};

type GeocodingResponse = { results?: GeocodingResult[] };

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

type WeatherFetch = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

type WeatherFetchOptions = {
  fetcher?: WeatherFetch;
  maxAttempts?: number;
  timeoutMs?: number;
  sleep?: (milliseconds: number) => Promise<void>;
};

export const WEATHER_FETCH_MAX_ATTEMPTS = 2;
export const WEATHER_FETCH_TIMEOUT_MS = 4_500;

class WeatherHttpError extends Error {
  constructor(status: number) {
    super(`Open-Meteo ${status}`);
    this.name = "WeatherHttpError";
    this.status = status;
  }

  readonly status: number;
}

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

export function isRetryableWeatherStatus(status: number): boolean {
  return status === 408 ||
    status === 425 ||
    status === 429 ||
    status >= 500;
}

export function weatherRetryDelayMs(completedAttempts: number): number {
  const attempts = Math.max(1, Math.floor(completedAttempts));
  return Math.min(250 * 2 ** (attempts - 1), 1_000);
}

export async function fetchWeatherJson<T>(
  url: string,
  options: WeatherFetchOptions = {},
): Promise<T> {
  const fetcher = options.fetcher ?? fetch;
  const maxAttempts = Math.max(
    1,
    Math.floor(options.maxAttempts ?? WEATHER_FETCH_MAX_ATTEMPTS),
  );
  const timeoutMs = Math.max(
    250,
    Math.floor(options.timeoutMs ?? WEATHER_FETCH_TIMEOUT_MS),
  );
  const sleep = options.sleep ?? ((milliseconds: number) =>
    new Promise<void>((resolve) => setTimeout(resolve, milliseconds)));

  let lastError: unknown;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    let response: Response;
    try {
      response = await fetcher(url, {
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      lastError = error;
      if (attempt < maxAttempts) {
        await sleep(weatherRetryDelayMs(attempt));
        continue;
      }
      throw error;
    }

    if (!response.ok) {
      const error = new WeatherHttpError(response.status);
      lastError = error;
      if (isRetryableWeatherStatus(response.status) && attempt < maxAttempts) {
        await sleep(weatherRetryDelayMs(attempt));
        continue;
      }
      throw error;
    }

    return await response.json() as T;
  }

  throw lastError ?? new Error("Open-Meteo indisponible");
}

export function geocodingQueries(address: string): string[] {
  const trimmed = address.trim();
  const queries: string[] = [];
  const postalCityMatch = trimmed.match(/\b\d{4,6}\b\s+([^,]+)/);
  const postalCity = postalCityMatch?.[0]?.trim();
  const cityOnly = postalCityMatch?.[1]?.trim();

  // Open-Meteo geocodes places rather than street addresses. Prefer the city
  // extracted from a postal address, then progressively broader fallbacks.
  if (cityOnly) queries.push(cityOnly);
  if (postalCity) queries.push(postalCity);

  const segments = trimmed.split(",").map((part) => part.trim()).filter(Boolean);
  if (segments.length > 1) {
    const lastTwo = segments.slice(-2).join(" ");
    queries.push(lastTwo);
    queries.push(segments.at(-1)!);
  }
  queries.push(trimmed);

  return [...new Set(queries.filter(Boolean))].slice(0, 5);
}

export async function geocodeWeatherAddress(
  address: string,
  options: WeatherFetchOptions = {},
): Promise<{ latitude: number; longitude: number }> {
  let lastError: unknown;

  for (const query of geocodingQueries(address)) {
    const url = new URL("https://geocoding-api.open-meteo.com/v1/search");
    url.searchParams.set("name", query);
    url.searchParams.set("count", "5");
    url.searchParams.set("language", "fr");
    url.searchParams.set("format", "json");

    try {
      const data = await fetchWeatherJson<GeocodingResponse>(
        url.toString(),
        options,
      );
      const result = data.results?.find((item) =>
        finiteNumber(item.latitude) != null && finiteNumber(item.longitude) != null
      );
      if (result) {
        return {
          latitude: Number(result.latitude),
          longitude: Number(result.longitude),
        };
      }
    } catch (error) {
      // A street-level or transient geocoding failure must not prevent a city
      // fallback from succeeding on the next query.
      lastError = error;
    }
  }

  const suffix = lastError instanceof Error ? ` (${lastError.message})` : "";
  throw new Error(`Adresse météo introuvable: ${address}${suffix}`);
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
) {
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

  const data = await fetchWeatherJson<ForecastResponse>(url.toString());
  const hourly = data.hourly;
  if (!hourly?.time?.length) throw new Error("Prévision horaire vide");

  const times = hourly.time.map((value) => Number(value));
  if (times.some((value) => !Number.isFinite(value))) {
    throw new Error("Horodatages météo invalides");
  }

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

  const point = (index: number) => ({
    forecast_at: new Date(times[index] * 1000).toISOString(),
    label: formatHour(times[index], timezone),
    temperature: oneDecimal(at(hourly.temperature_2m, index)),
    apparent_temperature: oneDecimal(at(hourly.apparent_temperature, index)),
    precipitation_probability: boundedPercent(at(hourly.precipitation_probability, index)),
    weather_code: finiteNumber(at(hourly.weather_code, index)),
    wind_speed: oneDecimal(at(hourly.wind_speed_10m, index)),
    wind_gusts: oneDecimal(at(hourly.wind_gusts_10m, index)),
    humidity: boundedPercent(at(hourly.relative_humidity_2m, index)),
  });

  let hourlyForecast = times
    .map((epoch, index) => ({ epoch, index }))
    .filter((item) => item.epoch >= stripStart && item.epoch <= stripEnd)
    .map((item) => point(item.index));

  if (hourlyForecast.length < 3) {
    hourlyForecast = times
      .map((epoch, index) => ({ epoch, index, delta: Math.abs(epoch - kickoffEpoch) }))
      .sort((a, b) => a.delta - b.delta)
      .slice(0, 3)
      .sort((a, b) => a.epoch - b.epoch)
      .map((item) => point(item.index));
  }

  return {
    timezone,
    temperature: oneDecimal(at(hourly.temperature_2m, mainIndex)),
    apparentTemperature: oneDecimal(at(hourly.apparent_temperature, mainIndex)),
    precipitationProbability: boundedPercent(at(hourly.precipitation_probability, mainIndex)),
    weatherCode: finiteNumber(at(hourly.weather_code, mainIndex)),
    windSpeed: oneDecimal(at(hourly.wind_speed_10m, mainIndex)),
    windGusts: oneDecimal(at(hourly.wind_gusts_10m, mainIndex)),
    humidity: boundedPercent(at(hourly.relative_humidity_2m, mainIndex)),
    hourlyForecast,
  };
}

export async function refreshMatchWeather(
  supabase: SupabaseClient,
  requestedMatchId: string | null,
): Promise<{ candidates: number; refreshed: number; failed: number }> {
  const { data: candidatesRaw, error: candidatesError } = await supabase.rpc(
    "internal_match_weather_candidates",
    { p_match_id: requestedMatchId },
  );
  if (candidatesError) throw candidatesError;

  const candidates = (candidatesRaw ?? []) as WeatherCandidate[];
  let refreshed = 0;
  let failed = 0;

  for (const candidate of candidates) {
    try {
      let latitude = finiteNumber(candidate.cached_latitude);
      let longitude = finiteNumber(candidate.cached_longitude);
      if (
        latitude == null ||
        longitude == null ||
        candidate.cached_geocoded_address !== candidate.resolved_address
      ) {
        const location = await geocodeWeatherAddress(candidate.resolved_address);
        latitude = location.latitude;
        longitude = location.longitude;
      }

      const forecast = await forecastForMatch(
        latitude,
        longitude,
        candidate.kickoff_at,
        candidate.planned_duration_minutes,
      );
      const now = new Date().toISOString();
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
        fetched_at: now,
        updated_at: now,
      }, { onConflict: "match_id" });
      if (upsertError) throw upsertError;
      refreshed += 1;
    } catch (error) {
      failed += 1;
      console.error(
        "match-weather refresh failure",
        candidate.match_id,
        error instanceof Error ? error.message : String(error),
      );
      // Keep the previous cache untouched when geocoding or Open-Meteo fails.
    }
  }

  return { candidates: candidates.length, refreshed, failed };
}
