import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const jsonHeaders = {
  ...corsHeaders,
  "Content-Type": "application/json",
};

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
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse(
        { error: "Missing or invalid authorization header" },
        401,
      );
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
      !["moderateur", "admin"].includes(String(callerProfile?.role)) ||
      callerProfile?.status !== "active"
    ) {
      return jsonResponse({ error: "Moderator or admin role required" }, 403);
    }

    const body = await req.json();
    const action = String(body.action ?? "");

    if (action === "invite") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const firstName = String(body.firstName ?? "").trim();
      const lastName = String(body.lastName ?? "").trim();
      const emailIsValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
      if (!emailIsValid || !firstName || !lastName) {
        return jsonResponse(
          { error: "Valid email, first name and last name are required" },
          400,
        );
      }
      if (
        firstName.length > 100 ||
        lastName.length > 100 ||
        email.length > 320
      ) {
        return jsonResponse({ error: "Input is too long" }, 400);
      }

      const redirectTo = String(body.redirectTo ?? "").trim() || undefined;
      const { data, error } = await admin.auth.admin.generateLink({
        type: "invite",
        email,
        options: {
          data: {
            first_name: firstName,
            last_name: lastName,
            approval_required: true,
          },
          redirectTo,
        },
      });
      if (error) throw error;
      return jsonResponse({
        userId: data.user?.id,
        actionLink: data.properties?.action_link,
      });
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
        return jsonResponse(
          { error: "A moderator cannot delete their own account" },
          400,
        );
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
        targetProfile.role === "moderateur" &&
        targetProfile.status === "active"
      ) {
        const { count, error: countError } = await admin
          .from("profiles")
          .select("id", { count: "exact", head: true })
          .eq("role", "moderateur")
          .eq("status", "active");
        if (countError) throw countError;
        if ((count ?? 0) <= 1) {
          return jsonResponse(
            { error: "The last active moderator cannot be deleted" },
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
