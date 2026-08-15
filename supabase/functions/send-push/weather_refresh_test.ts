import {
  fetchWeatherJson,
  geocodeWeatherAddress,
  geocodingQueries,
  isRetryableWeatherStatus,
} from "./weather_refresh.ts";

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ?? `Expected ${String(expected)}, received ${String(actual)}`,
    );
  }
}

Deno.test("classe les erreurs météo temporaires comme relançables", () => {
  for (const status of [408, 425, 429, 500, 502, 503, 504]) {
    assertEquals(isRetryableWeatherStatus(status), true);
  }
  for (const status of [400, 401, 403, 404, 422]) {
    assertEquals(isRetryableWeatherStatus(status), false);
  }
});

Deno.test("relance une requête Open-Meteo temporairement indisponible", async () => {
  let calls = 0;
  const waits: number[] = [];

  const result = await fetchWeatherJson<{ ok: boolean }>(
    "https://example.invalid/weather",
    {
      fetcher: () => {
        calls += 1;
        if (calls === 1) {
          return Promise.resolve(new Response("{}", { status: 503 }));
        }
        return Promise.resolve(
          new Response('{"ok":true}', {
            status: 200,
            headers: { "content-type": "application/json" },
          }),
        );
      },
      sleep: (milliseconds) => {
        waits.push(milliseconds);
        return Promise.resolve();
      },
    },
  );

  assertEquals(result.ok, true);
  assertEquals(calls, 2);
  assertEquals(waits.length, 1);
});

Deno.test("ne relance pas un refus HTTP permanent", async () => {
  let calls = 0;
  let failed = false;

  try {
    await fetchWeatherJson(
      "https://example.invalid/weather",
      {
        fetcher: () => {
          calls += 1;
          return Promise.resolve(new Response("{}", { status: 400 }));
        },
        sleep: () => Promise.resolve(),
      },
    );
  } catch {
    failed = true;
  }

  assertEquals(failed, true);
  assertEquals(calls, 1);
});

Deno.test("priorise la ville extraite avant l'adresse de rue", () => {
  const queries = geocodingQueries(
    "223 Rue des Arts, 31670 Labège, France",
  );
  assertEquals(queries[0], "Labège");
  assertEquals(queries.includes("223 Rue des Arts, 31670 Labège, France"), true);
});

Deno.test("continue le géocodage après l'échec d'une requête", async () => {
  let calls = 0;

  const location = await geocodeWeatherAddress(
    "223 Rue des Arts, 31670 Labège, France",
    {
      maxAttempts: 1,
      fetcher: () => {
        calls += 1;
        if (calls === 1) {
          return Promise.reject(new Error("temporary network failure"));
        }
        return Promise.resolve(
          new Response(
            JSON.stringify({
              results: [{ latitude: 43.52935, longitude: 1.52999 }],
            }),
            {
              status: 200,
              headers: { "content-type": "application/json" },
            },
          ),
        );
      },
      sleep: () => Promise.resolve(),
    },
  );

  assertEquals(calls, 2);
  assertEquals(location.latitude, 43.52935);
  assertEquals(location.longitude, 1.52999);
});
