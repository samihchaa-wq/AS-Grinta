import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("Missing authorization header");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const token = authHeader.replace("Bearer ", "");

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } =
      await callerClient.auth.getUser(token);
    if (userError || !userData.user) {
      throw new Error("Invalid authenticated user");
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { data: callerProfile, error: profileError } = await admin
      .from("profiles")
      .select("role,status")
      .eq("id", userData.user.id)
      .single();
    if (
      profileError ||
      callerProfile?.role !== "moderateur" ||
      callerProfile?.status !== "active"
    ) {
      return new Response(
        JSON.stringify({ error: "Moderator role required" }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body = await req.json();
    const action = body.action as string;

    if (action === "invite") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const firstName = String(body.firstName ?? "").trim();
      const lastName = String(body.lastName ?? "").trim();
      if (!email || !firstName || !lastName) {
        throw new Error("Email, first name and last name are required");
      }

      const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { first_name: firstName, last_name: lastName },
      });
      if (error) throw error;
      return new Response(JSON.stringify({ userId: data.user?.id }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "delete") {
      const userId = String(body.userId ?? "");
      if (!userId) throw new Error("User id is required");
      if (userId === userData.user.id) {
        throw new Error("A moderator cannot delete their own account");
      }

      const { error } = await admin.auth.admin.deleteUser(userId, false);
      if (error) throw error;
      return new Response(JSON.stringify({ deleted: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    throw new Error("Unsupported action");
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : String(error),
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
