// Garde de la fonction « lineup-presentations ».
//
// Le seul appelant légitime est le workflow GitHub qui fabrique les vidéos,
// lancé depuis la branche main de ce dépôt. GitHub lui remet un jeton signé
// (OIDC) qui le prouve : aucun secret partagé n'est stocké chez GitHub, et un
// dépôt copié, une autre branche ou un autre workflow sont refusés.
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@6.2.12";

export const GITHUB_OIDC_ISSUER = "https://token.actions.githubusercontent.com";
export const OIDC_AUDIENCE = "as-grinta-lineup-presentations";
export const ALLOWED_REPOSITORY = "samihchaa-wq/AS-Grinta";
export const ALLOWED_WORKFLOW_REF =
  "samihchaa-wq/AS-Grinta/.github/workflows/lineup_presentation_render.yml@refs/heads/main";
const ALLOWED_EVENTS = new Set(["workflow_dispatch", "schedule"]);

export const MAX_BODY_BYTES = 4_096;

const jwks = createRemoteJWKSet(
  new URL(`${GITHUB_OIDC_ISSUER}/.well-known/jwks`),
);

/** Raison du refus, ou null quand le jeton vient bien du bon workflow. */
export function rejectClaims(claims: JWTPayload): string | null {
  if (claims.repository !== ALLOWED_REPOSITORY) return "dépôt non autorisé";
  if (claims.ref !== "refs/heads/main") return "branche non autorisée";
  if (claims.workflow_ref !== ALLOWED_WORKFLOW_REF) return "workflow non autorisé";
  if (!ALLOWED_EVENTS.has(String(claims.event_name ?? ""))) {
    return "déclencheur non autorisé";
  }
  return null;
}

export async function verifyGithubToken(token: string): Promise<boolean> {
  try {
    const { payload } = await jwtVerify(token, jwks, {
      issuer: GITHUB_OIDC_ISSUER,
      audience: OIDC_AUDIENCE,
      algorithms: ["RS256"],
    });
    return rejectClaims(payload) === null;
  } catch {
    return false;
  }
}

export class RequestBodyTooLargeError extends Error {
  constructor() {
    super("Request body exceeds the allowed size");
    this.name = "RequestBodyTooLargeError";
  }
}

/** Lit un corps JSON sans jamais accepter plus de `maxBytes` octets. */
export async function readBoundedJson<T>(
  req: Request,
  maxBytes = MAX_BODY_BYTES,
): Promise<T> {
  const declaredLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new RequestBodyTooLargeError();
  }
  if (!req.body) throw new SyntaxError("Request body is empty");

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

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FINGERPRINT_RE = /^[0-9a-f]{32}$/;

export const isUuid = (value: unknown): value is string =>
  typeof value === "string" && UUID_RE.test(value);

export const VARIANTS = ["1080", "720"] as const;
export type Variant = (typeof VARIANTS)[number];

/** Emplacement imposé d'une vidéo : le même que celui que la base enregistre. */
export function videoPath(matchId: string, fingerprint: string, variant: Variant): string {
  if (!isUuid(matchId) || !FINGERPRINT_RE.test(fingerprint)) {
    throw new Error("Identifiants de vidéo invalides");
  }
  return `${matchId}/${fingerprint}/${variant}.mp4`;
}

export const PROFILE_PHOTOS_BUCKET = "profile-photos";

/**
 * Chemin de stockage d'une valeur `photo_url`, comme ProfilePhotoUrlCache
 * dans l'application : chemin relatif, ou adresse Supabase complète d'une
 * ancienne ligne. Une adresse externe en https est rendue telle quelle ;
 * toute autre valeur est ignorée.
 */
export function photoSource(
  value: unknown,
): { path: string } | { url: string } | null {
  const trimmed = typeof value === "string" ? value.trim() : "";
  if (!trimmed) return null;
  if (!/^https?:\/\//i.test(trimmed)) {
    return { path: trimmed.replace(/^\/+/, "") };
  }
  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    return null;
  }
  for (const marker of [
    `/storage/v1/object/public/${PROFILE_PHOTOS_BUCKET}/`,
    `/storage/v1/object/sign/${PROFILE_PHOTOS_BUCKET}/`,
    `/storage/v1/object/authenticated/${PROFILE_PHOTOS_BUCKET}/`,
  ]) {
    const index = url.pathname.indexOf(marker);
    if (index >= 0) {
      return { path: decodeURIComponent(url.pathname.slice(index + marker.length)) };
    }
  }
  return url.protocol === "https:" ? { url: trimmed } : null;
}

/** Message d'échec gardé court et débarrassé de toute adresse. */
export function sanitizeError(value: unknown): string {
  const text = typeof value === "string" ? value : "Échec du rendu";
  return text.replace(/https?:\/\/\S+/g, "[adresse]").slice(0, 300);
}
