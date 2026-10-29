import {
  ALLOWED_WORKFLOW_REF,
  photoSource,
  readBoundedJson,
  rejectClaims,
  RequestBodyTooLargeError,
  sanitizeError,
  videoPath,
} from "./security.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, received ${JSON.stringify(actual)}`,
    );
  }
}

function assertThrows(run: () => unknown): void {
  try {
    run();
  } catch {
    return;
  }
  throw new Error("Expected an error");
}

async function assertRejects(
  run: () => Promise<unknown>,
  type: new (...args: never[]) => Error,
): Promise<void> {
  try {
    await run();
  } catch (error) {
    if (error instanceof type) return;
    throw error;
  }
  throw new Error("Expected a rejection");
}

const legitimate = {
  repository: "samihchaa-wq/AS-Grinta",
  ref: "refs/heads/main",
  workflow_ref: ALLOWED_WORKFLOW_REF,
  event_name: "workflow_dispatch",
};

Deno.test("le workflow de rendu lancé depuis main est accepté", () => {
  assertEquals(rejectClaims(legitimate), null);
  assertEquals(rejectClaims({ ...legitimate, event_name: "schedule" }), null);
});

Deno.test("un dépôt copié, une autre branche ou un autre workflow sont refusés", () => {
  assertEquals(
    rejectClaims({ ...legitimate, repository: "quelquun/AS-Grinta" }),
    "dépôt non autorisé",
  );
  assertEquals(
    rejectClaims({ ...legitimate, ref: "refs/heads/claude/essai" }),
    "branche non autorisée",
  );
  assertEquals(
    rejectClaims({
      ...legitimate,
      workflow_ref: "samihchaa-wq/AS-Grinta/.github/workflows/flutter_ci.yml@refs/heads/main",
    }),
    "workflow non autorisé",
  );
  assertEquals(
    rejectClaims({ ...legitimate, event_name: "pull_request_target" }),
    "déclencheur non autorisé",
  );
  assertEquals(rejectClaims({}), "dépôt non autorisé");
});

Deno.test("les vidéos ne peuvent être rangées qu'à leur emplacement", () => {
  assertEquals(
    videoPath("d1b5bbb6-f21c-4271-82ed-d667ffe6c3ff", "0123456789abcdef0123456789abcdef", "720"),
    "d1b5bbb6-f21c-4271-82ed-d667ffe6c3ff/0123456789abcdef0123456789abcdef/720.mp4",
  );
  assertThrows(() => videoPath("../profile-photos", "0123456789abcdef0123456789abcdef", "720"));
  assertThrows(() =>
    videoPath("d1b5bbb6-f21c-4271-82ed-d667ffe6c3ff", "../../x", "1080")
  );
});

Deno.test("les photos sont lues comme dans l'application", () => {
  assertEquals(photoSource("abc/photo.jpg"), { path: "abc/photo.jpg" });
  assertEquals(photoSource("/abc/photo.jpg"), { path: "abc/photo.jpg" });
  assertEquals(
    photoSource(
      "https://x.supabase.co/storage/v1/object/public/profile-photos/abc/ph%C3%A9.jpg",
    ),
    { path: "abc/phé.jpg" },
  );
  assertEquals(photoSource("https://exemple.fr/photo.jpg"), {
    url: "https://exemple.fr/photo.jpg",
  });
  assertEquals(photoSource("http://exemple.fr/photo.jpg"), null);
  assertEquals(photoSource("  "), null);
  assertEquals(photoSource(null), null);
});

Deno.test("un message d'échec ne transporte aucune adresse", () => {
  assertEquals(
    sanitizeError("Échec https://x.supabase.co/a?token=secret puis fin"),
    "Échec [adresse] puis fin",
  );
  assertEquals(sanitizeError(undefined), "Échec du rendu");
  assertEquals(sanitizeError("x".repeat(400)).length, 300);
});

Deno.test("un corps trop volumineux est refusé sans être lu en entier", async () => {
  const big = new Request("https://exemple.invalid", {
    method: "POST",
    body: JSON.stringify({ action: "x".repeat(5_000) }),
  });
  await assertRejects(() => readBoundedJson(big), RequestBodyTooLargeError);
  const small = new Request("https://exemple.invalid", {
    method: "POST",
    body: JSON.stringify({ action: "pending" }),
  });
  assertEquals(await readBoundedJson(small), { action: "pending" });
});
