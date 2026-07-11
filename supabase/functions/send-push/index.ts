// Envoi des notifications Web Push (VAPID).
// Appelée par la base via pg_net avec le jeton interne x-push-token :
// { kind: 'new_match' | 'closing_soon' | 'result_validated', match_id: uuid }
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

type SubscriptionRow = { endpoint: string; p256dh: string; auth: string };

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: config, error: configError } = await supabase.rpc(
    "internal_push_config",
  );
  if (configError || !config?.token) {
    return new Response("configuration indisponible", { status: 500 });
  }

  const token = req.headers.get("x-push-token") ?? "";
  if (token !== config.token) {
    return new Response("non autorisé", { status: 401 });
  }

  let body: { kind?: string; match_id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response("corps invalide", { status: 400 });
  }
  if (!body.kind || !body.match_id) {
    return new Response("kind et match_id requis", { status: 400 });
  }

  const { data: dispatch, error: dispatchError } = await supabase.rpc(
    "internal_push_dispatch",
    { p_kind: body.kind, p_match_id: body.match_id },
  );
  if (dispatchError || !dispatch) {
    return new Response(
      `préparation impossible: ${dispatchError?.message ?? "inconnue"}`,
      { status: 500 },
    );
  }

  const subscriptions: SubscriptionRow[] = dispatch.subscriptions ?? [];
  if (subscriptions.length === 0) {
    return Response.json({ sent: 0, pruned: 0 });
  }

  webpush.setVapidDetails(
    "mailto:contact@as-grinta.example",
    config.vapid_public,
    config.vapid_private,
  );

  const payload = JSON.stringify(dispatch.payload);
  const dead: string[] = [];
  let sent = 0;

  await Promise.all(
    subscriptions.map(async (sub) => {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          payload,
          { TTL: 3600, urgency: "high" },
        );
        sent += 1;
      } catch (error) {
        const statusCode = (error as { statusCode?: number }).statusCode;
        if (statusCode === 404 || statusCode === 410) {
          dead.push(sub.endpoint);
        }
      }
    }),
  );

  let pruned = 0;
  if (dead.length > 0) {
    const { data } = await supabase.rpc("internal_push_prune", {
      p_endpoints: dead,
    });
    pruned = data ?? 0;
  }

  return Response.json({ sent, pruned });
});
