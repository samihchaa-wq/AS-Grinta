// Intermédiaire entre la base et le workflow GitHub qui fabrique les vidéos
// de présentation des compositions.
//
// Le workflow ne reçoit jamais de clé Supabase : il prouve son identité par
// le jeton OIDC de GitHub (voir security.ts), et cette fonction lui remet
// seulement ce dont il a besoin, pour quelques minutes :
//
//   pending   combien de vidéos attendent (pour s'arrêter tout de suite) ;
//   claim     les vidéos à fabriquer, avec des liens temporaires vers les
//             photos des titulaires ;
//   uploads   des liens d'envoi pour déposer les deux fichiers d'une vidéo ;
//   complete  la vidéo est déposée : elle devient visible dans l'application ;
//   fail      le rendu a échoué : la demande repart en file (trois essais).
//
// Chaque réservation fait aussi le ménage : les fichiers des vidéos remplacées
// ou de matchs passés sont effacés, pour que le stockage reste minime.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2.95.0";
import {
  isUuid,
  MAX_BODY_BYTES,
  photoSource,
  PROFILE_PHOTOS_BUCKET,
  readBoundedJson,
  RequestBodyTooLargeError,
  sanitizeError,
  VARIANTS,
  verifyGithubToken,
  videoPath,
} from "./security.ts";

const VIDEO_BUCKET = "lineup-presentations";
const PHOTO_URL_TTL_SECONDS = 30 * 60;

type RenderRequest = {
  action?: string;
  limit?: number;
  job_id?: string;
  match_id?: string;
  fingerprint?: string;
  duration_ms?: number;
  error?: string;
};

type Job = {
  id: string;
  match_id: string;
  fingerprint: string;
  payload: {
    players?: Array<Record<string, unknown>>;
    [key: string]: unknown;
  };
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

/** Remplace le chemin de chaque photo par un lien temporaire de lecture. */
async function withPhotoUrls(admin: SupabaseClient, job: Job): Promise<Job> {
  const players = job.payload.players ?? [];
  const sources = players.map((player) => photoSource(player.photo_path));
  const paths = [
    ...new Set(
      sources.flatMap((source) => (source && "path" in source ? [source.path] : [])),
    ),
  ];
  const signed = new Map<string, string>();
  if (paths.length > 0) {
    const { data } = await admin.storage
      .from(PROFILE_PHOTOS_BUCKET)
      .createSignedUrls(paths, PHOTO_URL_TTL_SECONDS);
    for (const item of data ?? []) {
      if (item.path && item.signedUrl && !item.error) signed.set(item.path, item.signedUrl);
    }
  }
  return {
    ...job,
    payload: {
      ...job.payload,
      players: players.map((player, index) => {
        const source = sources[index];
        const { photo_path: _ignored, ...rest } = player;
        // Une photo introuvable laisse place aux initiales, comme dans l'appli.
        const photoUrl = source === null
          ? null
          : "url" in source
          ? source.url
          : signed.get(source.path) ?? null;
        return { ...rest, photo_url: photoUrl };
      }),
    },
  };
}

/** Efface les fichiers des vidéos devenues inutiles. Au mieux : jamais bloquant. */
async function purgeStaleVideos(admin: SupabaseClient): Promise<void> {
  try {
    const { data } = await admin.rpc("lineup_render_purgeable", { p_limit: 20 });
    const stale = (data ?? []) as Array<{ id: string; paths: Array<string | null> }>;
    if (stale.length === 0) return;
    const paths = stale.flatMap((item) => item.paths.filter((p): p is string => !!p));
    if (paths.length > 0) {
      const { error } = await admin.storage.from(VIDEO_BUCKET).remove(paths);
      if (error) return;
    }
    await admin.rpc("lineup_render_mark_purged", { p_ids: stale.map((item) => item.id) });
  } catch {
    // Le ménage sera refait à la prochaine réservation.
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("méthode non autorisée", { status: 405 });
  }

  const authHeader = req.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response("non autorisé", { status: 401 });
  }
  if (!(await verifyGithubToken(authHeader.slice("Bearer ".length).trim()))) {
    return new Response("non autorisé", { status: 401 });
  }

  let body: RenderRequest;
  try {
    body = await readBoundedJson<RenderRequest>(req, MAX_BODY_BYTES);
  } catch (error) {
    if (error instanceof RequestBodyTooLargeError) {
      return new Response("corps trop volumineux", { status: 413 });
    }
    return new Response("requête invalide", { status: 400 });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  switch (body.action) {
    case "pending": {
      const { data, error } = await admin.rpc("lineup_render_pending_count");
      if (error) return json({ error: "file indisponible" }, 503);
      return json({ pending: Number(data ?? 0) });
    }

    case "claim": {
      await purgeStaleVideos(admin);
      const limit = Math.min(5, Math.max(1, Math.trunc(Number(body.limit ?? 2)) || 2));
      const { data, error } = await admin.rpc("lineup_render_claim", { p_limit: limit });
      if (error) return json({ error: "file indisponible" }, 503);
      const jobs = await Promise.all(
        ((data ?? []) as Job[]).map((job) => withPhotoUrls(admin, job)),
      );
      return json({ jobs });
    }

    case "uploads": {
      if (!isUuid(body.match_id) || typeof body.fingerprint !== "string") {
        return json({ error: "demande invalide" }, 400);
      }
      const uploads: Record<string, { url: string }> = {};
      for (const variant of VARIANTS) {
        let path: string;
        try {
          path = videoPath(body.match_id, body.fingerprint, variant);
        } catch {
          return json({ error: "demande invalide" }, 400);
        }
        const { data, error } = await admin.storage
          .from(VIDEO_BUCKET)
          .createSignedUploadUrl(path, { upsert: true });
        if (error || !data) return json({ error: "dépôt indisponible" }, 503);
        uploads[variant] = { url: data.signedUrl };
      }
      return json({ uploads });
    }

    case "complete": {
      if (!isUuid(body.job_id) || !isUuid(body.match_id) || typeof body.fingerprint !== "string") {
        return json({ error: "demande invalide" }, 400);
      }
      const durationMs = Math.trunc(Number(body.duration_ms));
      if (!Number.isFinite(durationMs) || durationMs <= 0 || durationMs > 120_000) {
        return json({ error: "durée invalide" }, 400);
      }
      // Les deux fichiers doivent être réellement déposés avant d'annoncer la
      // vidéo : l'application ne doit jamais tomber sur un lien mort.
      const folder = `${body.match_id}/${body.fingerprint}`;
      const { data: files, error: listError } = await admin.storage
        .from(VIDEO_BUCKET)
        .list(folder, { limit: 10 });
      if (listError) return json({ error: "dépôt illisible" }, 503);
      const sizes = new Map(
        (files ?? []).map((file) => [file.name, Number(file.metadata?.size ?? 0)]),
      );
      const bytes1080 = sizes.get("1080.mp4") ?? 0;
      const bytes720 = sizes.get("720.mp4") ?? 0;
      if (bytes1080 <= 0 || bytes720 <= 0) {
        return json({ error: "fichiers manquants" }, 409);
      }
      const { data, error } = await admin.rpc("lineup_render_complete", {
        p_id: body.job_id,
        p_duration_ms: durationMs,
        p_bytes_1080: bytes1080,
        p_bytes_720: bytes720,
      });
      if (error) return json({ error: "enregistrement impossible" }, 503);
      if (!data) return json({ error: "demande déjà traitée" }, 409);
      return json({ ready: true });
    }

    case "fail": {
      if (!isUuid(body.job_id)) return json({ error: "demande invalide" }, 400);
      const { error } = await admin.rpc("lineup_render_fail", {
        p_id: body.job_id,
        p_error: sanitizeError(body.error),
      });
      if (error) return json({ error: "enregistrement impossible" }, 503);
      return json({ noted: true });
    }

    default:
      return json({ error: "action inconnue" }, 400);
  }
});
