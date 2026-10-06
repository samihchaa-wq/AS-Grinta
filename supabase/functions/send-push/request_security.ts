export const MAX_BODY_BYTES = 16_384;

export class RequestBodyTooLargeError extends Error {
  constructor() {
    super("Request body exceeds the allowed size");
    this.name = "RequestBodyTooLargeError";
  }
}

const textEncoder = new TextEncoder();

async function sha256(value: string): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", textEncoder.encode(value)),
  );
}

export async function secretsEqual(
  candidate: string,
  expected: string,
): Promise<boolean> {
  const [candidateDigest, expectedDigest] = await Promise.all([
    sha256(candidate),
    sha256(expected),
  ]);

  let difference = 0;
  for (let index = 0; index < candidateDigest.length; index += 1) {
    difference |= candidateDigest[index] ^ expectedDigest[index];
  }
  return difference === 0;
}

export async function readBoundedJson<T>(
  req: Request,
  maxBytes = MAX_BODY_BYTES,
): Promise<T> {
  const declaredLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new RequestBodyTooLargeError();
  }
  if (!req.body) {
    throw new SyntaxError("Request body is empty");
  }

  const reader = req.body.getReader();
  const decoder = new TextDecoder();
  let totalBytes = 0;
  let json = "";

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;

      totalBytes += value.byteLength;
      if (totalBytes > maxBytes) {
        await reader.cancel();
        throw new RequestBodyTooLargeError();
      }
      json += decoder.decode(value, { stream: true });
    }
    json += decoder.decode();
  } finally {
    reader.releaseLock();
  }

  return JSON.parse(json) as T;
}

// Adresse d'écran portée par une notification : une route relative de
// l'application (`matches/<id>/lineup?section=effectif`, `armoire`…). Tout le
// reste — adresse absolue, autre domaine, chemin remontant, caractères
// inattendus — ramène à l'accueil de l'application.
const NOTIFICATION_ROUTE =
  /^[A-Za-z0-9][A-Za-z0-9_-]*(?:\/[A-Za-z0-9_-]+)*(?:\?[A-Za-z0-9_=&-]*)?$/;
const MAX_NOTIFICATION_ROUTE_LENGTH = 200;

export function safeNotificationUrl(value: unknown): string {
  if (typeof value !== "string") return ".";
  const route = value.trim();
  if (
    route.length === 0 ||
    route.length > MAX_NOTIFICATION_ROUTE_LENGTH ||
    !NOTIFICATION_ROUTE.test(route)
  ) {
    return ".";
  }
  return route;
}
