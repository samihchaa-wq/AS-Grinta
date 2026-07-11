// Première connexion d'un joueur invité : il choisit son mot de passe.
// Appelée sans session (l'utilisateur n'est pas encore connecté).
// { username: "lucasb", password: "..." }
import { createClient } from "jsr:@supabase/supabase-js@2";

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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Missing server configuration");
    }

    const body = await req.json();
    const username = String(body.username ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");

    if (!/^[a-z0-9]{2,30}$/.test(username)) {
      return jsonResponse({ error: "Identifiant invalide." }, 400);
    }
    if (password.length < 8 || password.length > 72) {
      return jsonResponse(
        { error: "Le mot de passe doit contenir entre 8 et 72 caractères." },
        400,
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("id,password_set,status")
      .eq("username", username)
      .maybeSingle();

    if (profileError) throw profileError;
    if (!profile || profile.status !== "active") {
      return jsonResponse(
        { error: "Identifiant inconnu. Vérifie auprès de Samih." },
        404,
      );
    }
    if (profile.password_set) {
      return jsonResponse(
        {
          error:
            "Ce compte est déjà activé. Utilise « Se connecter », ou demande "
            + "à Samih de réinitialiser ton mot de passe.",
        },
        409,
      );
    }

    const { error: updateError } = await admin.auth.admin.updateUserById(
      profile.id,
      { password, email_confirm: true },
    );
    if (updateError) throw updateError;

    const { error: flagError } = await admin
      .from("profiles")
      .update({ password_set: true, updated_at: new Date().toISOString() })
      .eq("id", profile.id);
    if (flagError) throw flagError;

    return jsonResponse({ activated: true });
  } catch (error) {
    console.error("claim-account failure", error);
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Erreur inattendue" },
      400,
    );
  }
});
