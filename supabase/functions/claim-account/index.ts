// Legacy endpoint intentionally disabled.
// Account activation and password resets are now handled by the authenticated
// admin-only `manage-user` function, which generates a temporary password and
// forces the user to replace it after sign-in.

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

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  return jsonResponse(
    {
      error:
        "L’activation publique a été désactivée. Demande à l’admin de réinitialiser ton mot de passe.",
    },
    410,
  );
});
