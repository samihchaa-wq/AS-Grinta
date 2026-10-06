import {
  readBoundedJson,
  RequestBodyTooLargeError,
  safeNotificationUrl,
  secretsEqual,
} from "./request_security.ts";

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ?? `Expected ${String(expected)}, received ${String(actual)}`,
    );
  }
}

async function assertRejectsWith(
  action: () => Promise<unknown>,
  expected: new (...args: never[]) => Error,
): Promise<void> {
  try {
    await action();
  } catch (error) {
    if (error instanceof expected) return;
    throw error;
  }
  throw new Error(`Expected ${expected.name} to be thrown`);
}

Deno.test("compare le jeton interne sans comparaison directe de chaînes", async () => {
  assertEquals(await secretsEqual("grinta-secret", "grinta-secret"), true);
  assertEquals(await secretsEqual("grinta-secret", "grinta-secreu"), false);
  assertEquals(await secretsEqual("court", "beaucoup-plus-long"), false);
});

Deno.test("lit un petit corps JSON", async () => {
  const request = new Request("http://localhost/send-push", {
    method: "POST",
    body: JSON.stringify({ kind: "test" }),
  });

  const body = await readBoundedJson<{ kind: string }>(request, 64);
  assertEquals(body.kind, "test");
});

Deno.test("rejette une taille déclarée au-dessus de la limite", async () => {
  const request = new Request("http://localhost/send-push", {
    method: "POST",
    headers: { "content-length": "65" },
    body: "{}",
  });

  await assertRejectsWith(
    () => readBoundedJson(request, 64),
    RequestBodyTooLargeError,
  );
});

Deno.test("rejette aussi un flux réellement trop grand sans Content-Length", async () => {
  const request = new Request("http://localhost/send-push", {
    method: "POST",
    body: new Uint8Array(65),
  });
  assertEquals(request.headers.get("content-length"), null);

  await assertRejectsWith(
    () => readBoundedJson(request, 64),
    RequestBodyTooLargeError,
  );
});

Deno.test("laisse remonter un JSON invalide sous la limite", async () => {
  const request = new Request("http://localhost/send-push", {
    method: "POST",
    body: "pas du json",
  });

  await assertRejectsWith(
    () => readBoundedJson(request, 64),
    SyntaxError,
  );
});

Deno.test("garde la route d'application portée par une notification", () => {
  const matchId = "6f1d2c3b-0a9e-4f8d-8c7b-1a2b3c4d5e6f";
  assertEquals(
    safeNotificationUrl(`matches/${matchId}/lineup?section=effectif`),
    `matches/${matchId}/lineup?section=effectif`,
  );
  assertEquals(safeNotificationUrl(`matches/${matchId}`), `matches/${matchId}`);
  assertEquals(safeNotificationUrl("armoire"), "armoire");
  assertEquals(safeNotificationUrl("admin/administration"), "admin/administration");
});

Deno.test("ramène à l'accueil toute adresse de notification douteuse", () => {
  for (
    const value of [
      undefined,
      null,
      42,
      "",
      "   ",
      ".",
      "https://exemple.invalid/matches",
      "//exemple.invalid/matches",
      "/matches",
      "../matches",
      "matches/../admin",
      "javascript:alert(1)",
      "matches/1#/admin",
      "matches/1?section=<script>",
      "a".repeat(201),
    ]
  ) {
    assertEquals(safeNotificationUrl(value), ".", `accepté à tort : ${value}`);
  }
});
