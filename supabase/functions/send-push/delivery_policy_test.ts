import {
  classifyPushFailure,
  executePushDelivery,
  MAX_PUSH_DELIVERY_ATTEMPTS,
  pushRetryDelayMs,
} from "./delivery_policy.ts";

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ?? `Expected ${String(expected)}, received ${String(actual)}`,
    );
  }
}

Deno.test("classe les abonnements supprimés comme expirés", () => {
  assertEquals(classifyPushFailure(404), "expired");
  assertEquals(classifyPushFailure(410), "expired");
});

Deno.test("classe les erreurs temporaires comme relançables", () => {
  for (const status of [null, 408, 425, 429, 500, 502, 503, 504]) {
    assertEquals(classifyPushFailure(status), "retryable");
  }
});

Deno.test("ne relance pas les refus permanents", () => {
  for (const status of [400, 401, 403, 422]) {
    assertEquals(classifyPushFailure(status), "permanent");
  }
});

Deno.test("réussit au second essai après une erreur temporaire", async () => {
  let calls = 0;
  const waits: number[] = [];

  const outcome = await executePushDelivery(
    async () => {
      calls += 1;
      if (calls === 1) throw { statusCode: 503 };
      return { statusCode: 201 };
    },
    { sleep: (milliseconds) => {
      waits.push(milliseconds);
      return Promise.resolve();
    } },
  );

  assertEquals(outcome.success, true);
  assertEquals(outcome.attempts, 2);
  assertEquals(calls, 2);
  assertEquals(waits.length, 1);
  assertEquals(waits[0], pushRetryDelayMs(1));
});

Deno.test("supprime sans relance un endpoint expiré", async () => {
  let calls = 0;

  const outcome = await executePushDelivery(async () => {
    calls += 1;
    throw { statusCode: 410 };
  });

  assertEquals(outcome.success, false);
  assertEquals(outcome.attempts, 1);
  assertEquals(calls, 1);
  if (outcome.success) throw new Error("Expected a failed delivery");
  assertEquals(outcome.failureClass, "expired");
});

Deno.test("arrête la relance après la limite", async () => {
  let calls = 0;

  const outcome = await executePushDelivery(
    async () => {
      calls += 1;
      throw new Error("network unavailable");
    },
    { sleep: () => Promise.resolve() },
  );

  assertEquals(outcome.success, false);
  assertEquals(outcome.attempts, MAX_PUSH_DELIVERY_ATTEMPTS);
  assertEquals(calls, MAX_PUSH_DELIVERY_ATTEMPTS);
  if (outcome.success) throw new Error("Expected a failed delivery");
  assertEquals(outcome.failureClass, "retryable");
});
