// Gestion des comptes par le staff : invitation par identifiant,
// réinitialisation sécurisée par mot de passe temporaire et suppression.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const USERNAME_DOMAIN = "pronos.as-grinta.local";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function normalizeName(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

function randomCharacter(alphabet: string): string {
  const value = new Uint32Array(1);
  crypto.getRandomValues(value);
  return alphabet[value[0] % alphabet.length];
}

function generateTemporaryPassword(): string {
  const lower = "abcdefghijkmnopqrstuvwxyz";
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const digits = "23456789";
  const symbols = "!@#$%+-_";
  const all = lower + upper + digits + symbols;
  const characters = [
    randomCharacter(lower),
    randomCharacter(upper),
    randomCharacter(digits),
    randomCharacter(symbols),
  ];
  while (characters.length < 14) characters.push(randomCharacter(all));
  for (let index = characters.length - 1; index > 0; index--) {
    const value = new Uint32Array(1);
    crypto.getRandomValues(value);
    const target = value[0] % (index + 1);
    [characters[index], characters[target]] =
      [characters[target], characters[index]];
  }
  return characters.join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse({ error: "Missing or invalid authorization header" }, 401);
    }
    const contentLength = Number(req.headers.get("content-length") ?? "0");
    if (contentLength > 16_384) {
      return jsonResponse({ error: "Request body too large" }, 413);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !serviceRoleKey || !anonKey) {
      throw new Error("Missing server configuration");
    }

    const token = authHeader.slice("Bearer ".length);
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } =
      await callerClient.auth.getUser(token);
    if (userError || !userData.user) {
      return jsonResponse({ error: "Invalid authenticated user" }, 401);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: callerProfile, error: profileError } = await admin
      .from("profiles")
      .select("role,status")
      .eq("id", userData.user.id)
      .single();
    if (
      profileError ||
      String(callerProfile?.role) !== "admin" ||
      callerProfile?.status !== "active"
    ) {
      return jsonResponse({ error: "Active admin role required" }, 403);
    }

    const body = await req.json();
    const action = String(body.action ?? "");

    if (action === "invite") {
      const firstName = String(body.firstName ?? "").trim();
      const lastInitial = String(body.lastInitial ?? "").trim();
      const surnom = String(body.surnom ?? "").trim();
      const isGoalkeeper = body.isGoalkeeper === true;

      if (!firstName || firstName.length > 100) {
        return jsonResponse({ error: "Prénom requis." }, 400);
      }
      const normalizedFirst = normalizeName(firstName);
      const normalizedInitial = normalizeName(lastInitial).slice(0, 1);
      if (!normalizedFirst || !normalizedInitial) {
        return jsonResponse(
          { error: "Prénom et initiale du nom sont requis." },
          400,
        );
      }

      const base = `${normalizedFirst}${normalizedInitial}`;
      let username = base;
      for (let suffix = 2; suffix <= 20; suffix++) {
        const { data: existing, error: existsError } = await admin
          .from("profiles")
          .select("id")
          .eq("username", username)
          .maybeSingle();
        if (existsError) throw existsError;
        if (!existing) break;
        username = `${base}${suffix}`;
      }

      const { data: created, error: createError } =
        await admin.auth.admin.createUser({
          email: `${username}@${USERNAME_DOMAIN}`,
          password: crypto.randomUUID() + crypto.randomUUID(),
          email_confirm: true,
          user_metadata: {
            first_name: firstName,
            last_name: `${normalizedInitial.toUpperCase()}.`,
            surnom: surnom || null,
            invited: true,
          },
        });
      if (createError) throw createError;
      const newUserId = created.user?.id;
      if (!newUserId) throw new Error("Compte non créé");

      const { error: updateError } = await admin
        .from("profiles")
        .update({
          username,
          password_set: false,
          must_change_password: false,
          is_goalkeeper: isGoalkeeper,
          surnom: surnom || null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", newUserId);
      if (updateError) throw updateError;

      return jsonResponse({ userId: newUserId, username });
    }

    if (action === "reset-password") {
      const userId = String(body.userId ?? "");
      const uuidIsValid =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          .test(userId);
      if (!uuidIsValid) {
        return jsonResponse({ error: "Valid user id is required" }, 400);
      }
      if (userId === userData.user.id) {
        return jsonResponse(
          { error: "Utilise ton profil pour modifier ton mot de passe." },
          400,
        );
      }
      if (userId === "00000000-0000-0000-0000-000000000001") {
        return jsonResponse({ error: "Compte technique protégé." }, 400);
      }

      const temporaryPassword = generateTemporaryPassword();
      const { error: passwordError } = await admin.auth.admin.updateUserById(
        userId,
        { password: temporaryPassword },
      );
      if (passwordError) throw passwordError;

      const { error: flagError } = await admin
        .from("profiles")
        .update({
          password_set: true,
          must_change_password: true,
          updated_at: new Date().toISOString(),
        })
        .eq("id", userId);
      if (flagError) throw flagError;

      return jsonResponse({ reset: true, temporaryPassword });
    }

    if (action === "delete") {
      const userId = String(body.userId ?? "");
      const uuidIsValid =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          .test(userId);
      if (!uuidIsValid) {
        return jsonResponse({ error: "Valid user id is required" }, 400);
      }
      if (userId === userData.user.id) {
        return jsonResponse({ error: "You cannot delete your own account" }, 400);
      }
      if (userId === "00000000-0000-0000-0000-000000000001") {
        return jsonResponse(
          { error: "The historical import actor cannot be deleted" },
          400,
        );
      }

      const { data: targetProfile, error: targetError } = await admin
        .from("profiles")
        .select("role,status")
        .eq("id", userId)
        .maybeSingle();
      if (targetError || !targetProfile) {
        return jsonResponse({ error: "Target account not found" }, 404);
      }

      if (targetProfile.role === "admin" && targetProfile.status === "active") {
        const { count, error: countError } = await admin
          .from("profiles")
          .select("id", { count: "exact", head: true })
          .eq("role", "admin")
          .eq("status", "active");
        if (countError) throw countError;
        if ((count ?? 0) <= 1) {
          return jsonResponse(
            { error: "The last active admin cannot be deleted" },
            409,
          );
        }
      }

      const { error } = await admin.auth.admin.deleteUser(userId, false);
      if (error) throw error;
      return jsonResponse({ deleted: true });
    }

    return jsonResponse({ error: "Unsupported action" }, 400);
  } catch (error) {
    console.error("manage-user failure", error);
    return jsonResponse(
      {
        error:
          error instanceof Error ? error.message : "Unexpected server error",
      },
      400,
    );
  }
});
