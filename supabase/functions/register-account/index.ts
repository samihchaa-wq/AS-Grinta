// Inscription publique via le lien partagé dans la conversation du club.
// Le compte reste en attente de validation par l'administrateur.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.95.0";

const USERNAME_DOMAIN = "pronos.as-grinta.local";
const MAX_BODY_BYTES = 4_096;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };

function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...jsonHeaders, ...extraHeaders },
  });
}

function normalizeName(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

function requestOrigin(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return (
    req.headers.get("cf-connecting-ip")?.trim() ||
    forwarded ||
    req.headers.get("x-real-ip")?.trim() ||
    "unknown"
  ).slice(0, 128);
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    return jsonResponse({ error: "Requête trop volumineuse." }, 413);
  }

  let newUserId: string | null = null;
  let admin: ReturnType<typeof createClient> | null = null;

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Missing server configuration");
    }

    admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const originHash = await sha256Hex(requestOrigin(req));
    const { data: allowed, error: rateLimitError } = await admin.rpc(
      "consume_registration_rate_limit",
      { p_origin_hash: originHash },
    );
    if (rateLimitError) throw rateLimitError;
    if (allowed !== true) {
      return jsonResponse(
        { error: "Trop de tentatives. Réessaie plus tard." },
        429,
        { "Retry-After": "3600" },
      );
    }

    const body = await req.json();
    const firstName = String(body.firstName ?? "").trim();
    const lastName = String(body.lastName ?? "").trim();
    const password = String(body.password ?? "");

    if (
      firstName.length < 2 ||
      firstName.length > 50 ||
      lastName.length < 2 ||
      lastName.length > 50 ||
      /[\u0000-\u001f\u007f]/.test(firstName + lastName)
    ) {
      return jsonResponse({ error: "Prénom ou nom invalide." }, 400);
    }
    if (password.length < 8 || password.length > 72) {
      return jsonResponse(
        { error: "Le mot de passe doit contenir entre 8 et 72 caractères." },
        400,
      );
    }

    const normalizedFirst = normalizeName(firstName);
    const normalizedInitial = normalizeName(lastName).slice(0, 1);
    if (!normalizedFirst || !normalizedInitial) {
      return jsonResponse({ error: "Prénom ou nom invalide." }, 400);
    }

    const base = `${normalizedFirst}${normalizedInitial}`.slice(0, 27);
    let username = "";
    for (let suffix = 1; suffix <= 20; suffix++) {
      const candidate = suffix === 1 ? base : `${base}${suffix}`;
      const { data: existing, error: existsError } = await admin
        .from("profiles")
        .select("id")
        .eq("username", candidate)
        .maybeSingle();
      if (existsError) throw existsError;
      if (!existing) {
        username = candidate;
        break;
      }
    }
    if (!username) {
      return jsonResponse(
        { error: "Impossible de générer un identifiant disponible." },
        409,
      );
    }

    const { data: created, error: createError } =
      await admin.auth.admin.createUser({
        email: `${username}@${USERNAME_DOMAIN}`,
        password,
        email_confirm: true,
        user_metadata: {
          first_name: firstName,
          last_name: lastName,
        },
      });
    if (createError) throw createError;
    newUserId = created.user?.id ?? null;
    if (!newUserId) throw new Error("Account creation returned no user id");

    const { error: updateError } = await admin
      .from("profiles")
      .update({ username, updated_at: new Date().toISOString() })
      .eq("id", newUserId);
    if (updateError) throw updateError;

    return jsonResponse({ username });
  } catch (error) {
    console.error("register-account failure", error);

    if (newUserId && admin) {
      const { error: cleanupError } = await admin.auth.admin.deleteUser(
        newUserId,
        false,
      );
      if (cleanupError) {
        console.error("register-account cleanup failure", cleanupError);
      }
    }

    return jsonResponse(
      { error: "La création du compte a échoué. Réessaie plus tard." },
      400,
    );
  }
});
