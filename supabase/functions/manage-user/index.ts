// Gestion des comptes par un admin : réinitialisation par lien à usage unique
// et suppression.
//
// La création de compte se fait exclusivement par auto-inscription
// (`register-account`), qui applique le limiteur de débit. L'ancienne action
// `invite` a été retirée : elle n'avait aucun appelant et contournait
// entièrement ce limiteur.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.95.0";

const PUBLIC_APP_URL = "https://samihchaa-wq.github.io/AS-Grinta/";

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

function isUserNotFound(error: {
  status?: number;
  code?: string;
  message?: string;
}): boolean {
  return error.status === 404 ||
    error.code === "user_not_found" ||
    error.message?.toLowerCase().includes("user not found") === true;
}

async function deleteProfileWithRetry(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<void> {
  let lastError: unknown = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    const { error } = await admin.from("profiles").delete().eq("id", userId);
    if (!error) {
      const { data: remaining, error: verifyError } = await admin
        .from("profiles")
        .select("id")
        .eq("id", userId)
        .maybeSingle();
      if (verifyError) throw verifyError;
      if (!remaining) return;
      lastError = new Error("Profile still exists after deletion");
    } else {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 150 * (attempt + 1)));
  }
  throw lastError ?? new Error("Profile deletion failed");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

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

    if (action === "reset-password") {
      const userId = String(body.userId ?? "");
      const uuidIsValid =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
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

      const { data: targetProfile, error: targetError } = await admin
        .from("profiles")
        .select("id,status")
        .eq("id", userId)
        .maybeSingle();
      if (targetError || !targetProfile) {
        return jsonResponse({ error: "Target account not found" }, 404);
      }
      if (targetProfile.status === "archived") {
        return jsonResponse({ error: "Réactive d’abord ce compte." }, 409);
      }

      const { data: targetUser, error: targetUserError } =
        await admin.auth.admin.getUserById(userId);
      if (targetUserError || !targetUser.user?.email) {
        if (targetUserError && isUserNotFound(targetUserError)) {
          return jsonResponse(
            {
              error:
                "Ce profil n’a plus de compte de connexion. Supprime-le puis recrée son accès.",
            },
            409,
          );
        }
        throw targetUserError ?? new Error("Target account has no email");
      }

      const { data: linkData, error: linkError } =
        await admin.auth.admin.generateLink({
          type: "recovery",
          email: targetUser.user.email,
          options: {
            redirectTo: `${PUBLIC_APP_URL}#/auth/new-password?recovery=1`,
          },
        });
      if (linkError) throw linkError;

      return jsonResponse({ reset: true, resetLink: linkData.properties.action_link });
    }

    if (action === "delete") {
      const userId = String(body.userId ?? "");
      const uuidIsValid =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
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

      if (
        targetProfile.role === "admin" &&
        targetProfile.status === "active"
      ) {
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

      // Cette préparation est idempotente : une nouvelle tentative peut donc
      // reprendre proprement si une précédente suppression s'est interrompue.
      const { error: prepareError } = await admin.rpc(
        "prepare_profile_for_hard_deletion",
        { p_profile_id: userId },
      );
      if (prepareError) throw prepareError;

      const { error: authDeleteError } = await admin.auth.admin.deleteUser(
        userId,
        false,
      );
      if (authDeleteError && !isUserNotFound(authDeleteError)) {
        throw authDeleteError;
      }

      // La suppression Auth et celle du profil ne peuvent pas partager une
      // transaction. On rend donc la deuxième moitié répétable et vérifiée.
      await deleteProfileWithRetry(admin, userId);

      return jsonResponse({ deleted: true });
    }

    return jsonResponse({ error: "Unsupported action" }, 400);
  } catch (error) {
    console.error("manage-user failure", error);
    return jsonResponse({ error: "La demande n’a pas pu être traitée." }, 500);
  }
});
