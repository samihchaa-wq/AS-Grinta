// Inscription publique via le lien partagé dans la conversation du club :
// le joueur saisit prénom, nom et mot de passe. Le compte est créé
// « en attente de validation » (status pending) et l'identifiant généré
// (prénom + initiale) lui est retourné. L'admin valide ensuite le compte.
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
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
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
    const firstName = String(body.firstName ?? "").trim();
    const lastName = String(body.lastName ?? "").trim();
    const password = String(body.password ?? "");

    if (
      !firstName || firstName.length > 100 ||
      !lastName || lastName.length > 100
    ) {
      return jsonResponse({ error: "Prénom et nom sont requis." }, 400);
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

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

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
        password,
        email_confirm: true,
        user_metadata: {
          first_name: firstName,
          last_name: lastName,
        },
      });
    if (createError) throw createError;
    const newUserId = created.user?.id;
    if (!newUserId) throw new Error("Compte non créé");

    const { error: updateError } = await admin
      .from("profiles")
      .update({ username, updated_at: new Date().toISOString() })
      .eq("id", newUserId);
    if (updateError) throw updateError;

    return jsonResponse({ username });
  } catch (error) {
    console.error("register-account failure", error);
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Erreur inattendue" },
      400,
    );
  }
});
