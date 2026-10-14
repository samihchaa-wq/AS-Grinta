// Envoi des notifications Web Push (VAPID) et jobs internes protégés.
// Appelée par la base via pg_net avec le jeton interne x-push-token.
import { createClient } from "npm:@supabase/supabase-js@2.95.0";
import webpush from "npm:web-push@3.6.7";
import { optionalMatchId, targetedDeliveryLogKind } from "./delivery_log.ts";
import {
  executePushDelivery,
  PUSH_DELIVERY_TTL_SECONDS,
} from "./delivery_policy.ts";
import {
  historyKind,
  historyRecipients,
  payloadForProfile,
  payloadText,
  profileIdList,
  shouldRecordHistory,
  unreadCounts,
} from "./history.ts";
import {
  readBoundedJson,
  RequestBodyTooLargeError,
  safeNotificationUrl,
  secretsEqual,
} from "./request_security.ts";
import { refreshMatchWeather } from "./weather_refresh.ts";

type SubscriptionRow = {
  profile_id?: string;
  endpoint: string;
  p256dh: string;
  auth: string;
};

type DeliveryLogRow = {
  match_id: string | null;
  kind: string;
  profile_id: string | null;
  endpoint_host: string | null;
  success: boolean;
  status_code: number | null;
  error_message: string | null;
  attempts: number;
};

type PushRequestBody = {
  kind?: string;
  match_id?: string;
  profile_ids?: string[];
  notification_event_id?: number;
  live_notification_id?: string;
  display_name?: string;
  title?: string;
  message?: string;
  url?: string;
  log_kind?: string;
  record_history?: boolean;
};

type HistoryEntry = {
  kind: string;
  matchId: string | null;
  profileIds: string[];
  payload: Record<string, unknown>;
  dedupeKey?: string | null;
};

const sportsAvailabilityKinds = new Set([
  "availability_open",
  "availability_j3",
  "availability_j1",
  "availability_manual",
]);

function endpointHost(endpoint: string): string | null {
  try {
    return new URL(endpoint).host;
  } catch {
    return null;
  }
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message.slice(0, 500);
  return String(error).slice(0, 500);
}

// Range l'envoi dans l'historique de chaque destinataire et rend leur nombre
// de notifications non lues. L'historique ne doit jamais empêcher un envoi :
// en cas d'échec, la notification part sans nombre (la pastille de l'icône
// reste alors inchangée).
async function recordHistory(
  supabase: ReturnType<typeof createClient>,
  entry: HistoryEntry,
): Promise<Map<string, number>> {
  if (entry.profileIds.length === 0) return new Map();
  try {
    const { data, error } = await supabase.rpc(
      "internal_record_notification_history",
      {
        p_kind: entry.kind,
        p_match_id: entry.matchId,
        p_profile_ids: entry.profileIds,
        p_title: payloadText(entry.payload.title),
        p_body: payloadText(entry.payload.body),
        p_url: payloadText(entry.payload.url),
        p_tag: payloadText(entry.payload.tag),
        p_dedupe_key: entry.dedupeKey ?? null,
      },
    );
    if (error) {
      console.error("send-push history failure", { kind: entry.kind, error });
      return new Map();
    }
    return unreadCounts(data);
  } catch (error) {
    console.error("send-push history failure", {
      kind: entry.kind,
      message: errorMessage(error),
    });
    return new Map();
  }
}

// Envoie un contenu fixe à un ensemble explicite de profils (canal de test,
// alerte admin, contenu préparé par la base), sans passer par le pipeline
// générique de dispatch. Chaque appareil laisse une ligne dans le journal de
// livraison, sous le type et le match indiqués. Avec `history`, l'envoi est
// aussi rangé dans l'historique de chaque profil, téléphone abonné ou non.
async function sendFixedPayloadToProfiles(
  supabase: ReturnType<typeof createClient>,
  profileIds: string[],
  payload: { title: string; body: string; url: string; tag: string },
  vapid: { public: string; private: string },
  log: { kind: string; matchId: string | null },
  history: { kind: string } | null = null,
): Promise<{ attempted: number; sent: number; failed: number }> {
  if (profileIds.length === 0) return { attempted: 0, sent: 0, failed: 0 };
  const unread = history
    ? await recordHistory(supabase, {
      kind: history.kind,
      matchId: log.matchId,
      profileIds: profileIdList(profileIds),
      payload,
    })
    : new Map<string, number>();
  const { data: subs } = await supabase
    .from("push_subscriptions")
    .select("profile_id, endpoint, p256dh, auth")
    .in("profile_id", profileIds);
  const targets: SubscriptionRow[] = subs ?? [];
  if (targets.length === 0) return { attempted: 0, sent: 0, failed: 0 };

  webpush.setVapidDetails(
    "https://samihchaa-wq.github.io/AS-Grinta",
    vapid.public,
    vapid.private,
  );
  const dead: string[] = [];
  const deliveries: DeliveryLogRow[] = [];
  let sent = 0;
  await Promise.all(targets.map(async (sub) => {
    const outcome = await executePushDelivery(() =>
      webpush.sendNotification(
        { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
        payloadForProfile(payload, sub.profile_id, unread),
        { TTL: PUSH_DELIVERY_TTL_SECONDS, urgency: "high" },
      )
    );
    if (outcome.success) {
      sent += 1;
      deliveries.push({
        match_id: log.matchId,
        kind: log.kind,
        profile_id: sub.profile_id ?? null,
        endpoint_host: endpointHost(sub.endpoint),
        success: true,
        status_code: outcome.statusCode ?? 201,
        error_message: null,
        attempts: outcome.attempts,
      });
      return;
    }
    if (outcome.failureClass === "expired") {
      dead.push(sub.endpoint);
    }
    const failure = errorMessage(outcome.error);
    deliveries.push({
      match_id: log.matchId,
      kind: log.kind,
      profile_id: sub.profile_id ?? null,
      endpoint_host: endpointHost(sub.endpoint),
      success: false,
      status_code: outcome.statusCode,
      error_message: failure,
      attempts: outcome.attempts,
    });
    console.error("send-push targeted delivery failure", {
      kind: log.kind,
      profileId: sub.profile_id ?? null,
      endpointHost: endpointHost(sub.endpoint),
      statusCode: outcome.statusCode,
      failureClass: outcome.failureClass,
      attempts: outcome.attempts,
      message: failure,
    });
  }));
  // Le journal ne doit jamais faire échouer un envoi déjà parti.
  if (deliveries.length > 0) {
    const { error } = await supabase.from("push_delivery_log").insert(deliveries);
    if (error) console.error("send-push targeted log failure", error);
  }
  if (dead.length > 0) {
    await supabase.rpc("internal_push_prune", { p_endpoints: dead });
  }
  return { attempted: targets.length, sent, failed: targets.length - sent };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response("configuration indisponible", { status: 500 });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: config, error: configError } = await supabase.rpc(
    "internal_push_config",
  );
  if (configError || !config?.token) {
    console.error("send-push config failure", configError);
    return new Response("configuration indisponible", { status: 500 });
  }

  const token = req.headers.get("x-push-token") ?? "";
  if (!(await secretsEqual(token, String(config.token)))) {
    return new Response("non autorisé", { status: 401 });
  }

  let body: PushRequestBody;
  try {
    body = await readBoundedJson<PushRequestBody>(req);
  } catch (error) {
    if (error instanceof RequestBodyTooLargeError) {
      return new Response("corps trop volumineux", { status: 413 });
    }
    return new Response("corps invalide", { status: 400 });
  }

  // Job interne non-push. Il utilise le même canal serveur authentifié mais
  // reste indépendant du coupe-circuit des notifications.
  if (body.kind === "refresh_match_weather") {
    try {
      const result = await refreshMatchWeather(
        supabase,
        typeof body.match_id === "string" && body.match_id.trim()
          ? body.match_id.trim()
          : null,
      );
      return Response.json(result);
    } catch (error) {
      console.error("match-weather worker failure", error);
      return new Response("météo indisponible", { status: 500 });
    }
  }

  // Coupe-circuit admin : quand actif, aucun envoi ne part (test compris),
  // le temps d'une phase de tests, sans toucher aux préférences des joueurs.
  if (config.notifications_paused === true) {
    return Response.json({ paused: true, attempted: 0, sent: 0, failed: 0 });
  }

  // Buts et fin de match : la base revendique atomiquement un événement Live
  // avant l'envoi. Deux requêtes concurrentes ou un retry du cron ne peuvent
  // donc jamais produire deux notifications pour le même événement.
  if (body.kind === "live_match") {
    const notificationId = typeof body.live_notification_id === "string"
      ? body.live_notification_id.trim()
      : "";
    if (!notificationId) {
      return new Response("live_notification_id requis", { status: 400 });
    }

    const { data: dispatch, error: dispatchError } = await supabase.rpc(
      "internal_claim_match_live_notification",
      { p_notification_id: notificationId },
    );
    if (dispatchError || !dispatch) {
      console.error("send-push live dispatch claim failure", dispatchError);
      return new Response("préparation live impossible", { status: 500 });
    }
    if (dispatch.claimed !== true) {
      return Response.json({
        claimed: false,
        attempted: 0,
        sent: 0,
        failed: 0,
        pruned: 0,
      });
    }

    const subscriptions: SubscriptionRow[] = dispatch.subscriptions ?? [];
    const matchId = typeof dispatch.match_id === "string"
      ? dispatch.match_id
      : "";
    const logKind = typeof dispatch.kind === "string"
      ? dispatch.kind
      : "live_goal_us";

    const markDelivery = async (
      attempted: number,
      sent: number,
      failed: number,
    ) => {
      const { error } = await supabase.rpc(
        "internal_mark_match_live_notification_delivery",
        {
          p_notification_id: notificationId,
          p_attempted: attempted,
          p_sent: sent,
          p_failed: failed,
        },
      );
      if (error) {
        console.error("send-push live event mark failure", error);
      }
    };

    // Rangé au moment de l'envoi (le texte d'un but peut encore changer
    // avant), pour toutes les cibles encore inscrites, téléphone ou non.
    const unread = await recordHistory(supabase, {
      kind: historyKind(logKind),
      matchId: matchId || null,
      profileIds: historyRecipients(dispatch, subscriptions),
      payload: dispatch.payload ?? {},
      dedupeKey: `live:${notificationId}`,
    });

    if (subscriptions.length === 0) {
      await markDelivery(0, 0, 0);
      return Response.json({
        claimed: true,
        attempted: 0,
        sent: 0,
        failed: 0,
        pruned: 0,
      });
    }

    webpush.setVapidDetails(
      "https://samihchaa-wq.github.io/AS-Grinta",
      config.vapid_public,
      config.vapid_private,
    );

    const dead: string[] = [];
    const deliveries: DeliveryLogRow[] = [];
    let sent = 0;

    await Promise.all(
      subscriptions.map(async (sub) => {
        const outcome = await executePushDelivery(() =>
          webpush.sendNotification(
            {
              endpoint: sub.endpoint,
              keys: { p256dh: sub.p256dh, auth: sub.auth },
            },
            payloadForProfile(dispatch.payload ?? {}, sub.profile_id, unread),
            { TTL: PUSH_DELIVERY_TTL_SECONDS, urgency: "high" },
          )
        );

        if (outcome.success) {
          sent += 1;
          deliveries.push({
            match_id: matchId,
            kind: logKind,
            profile_id: sub.profile_id ?? null,
            endpoint_host: endpointHost(sub.endpoint),
            success: true,
            status_code: outcome.statusCode ?? 201,
            error_message: null,
            attempts: outcome.attempts,
          });
          return;
        }

        if (outcome.failureClass === "expired") {
          dead.push(sub.endpoint);
        }

        const message = errorMessage(outcome.error);
        deliveries.push({
          match_id: matchId,
          kind: logKind,
          profile_id: sub.profile_id ?? null,
          endpoint_host: endpointHost(sub.endpoint),
          success: false,
          status_code: outcome.statusCode,
          error_message: message,
          attempts: outcome.attempts,
        });
        console.error("send-push live delivery failure", {
          profileId: sub.profile_id ?? null,
          endpointHost: endpointHost(sub.endpoint),
          statusCode: outcome.statusCode,
          failureClass: outcome.failureClass,
          attempts: outcome.attempts,
          message,
        });
      }),
    );

    if (deliveries.length > 0) {
      const { error } = await supabase.from("push_delivery_log").insert(deliveries);
      if (error) console.error("send-push live log failure", error);
    }

    let pruned = 0;
    if (dead.length > 0) {
      const { data, error } = await supabase.rpc("internal_push_prune", {
        p_endpoints: dead,
      });
      if (error) {
        console.error("send-push live prune failure", error);
      } else {
        pruned = data ?? 0;
      }
    }

    await markDelivery(
      subscriptions.length,
      sent,
      subscriptions.length - sent,
    );

    return Response.json({
      claimed: true,
      attempted: subscriptions.length,
      sent,
      failed: subscriptions.length - sent,
      pruned,
    });
  }

  // Alerte admin : un nouveau compte attend une validation. Envoyée à tous
  // les admins actifs, avec un contenu fixe décrivant le joueur concerné.
  if (body.kind === "admin_pending_signup") {
    const profileIds = Array.isArray(body.profile_ids) ? body.profile_ids : [];
    const displayName = typeof body.display_name === "string" && body.display_name.trim()
      ? body.display_name.trim()
      : "Un joueur";
    const result = await sendFixedPayloadToProfiles(
      supabase,
      profileIds,
      {
        title: "Nouveau compte en attente",
        body: `${displayName} attend ta validation.`,
        url: "admin/administration",
        tag: "admin-pending-signup",
      },
      { public: config.vapid_public, private: config.vapid_private },
      { kind: "admin_pending_signup", matchId: null },
      { kind: "admin_pending_signup" },
    );
    return Response.json(result);
  }

  // Canal de test : envoie une notification fixe UNIQUEMENT aux profils passés
  // (l'admin lui-même), pour valider le rendu sans déranger l'équipe. Jamais
  // rangé dans l'historique.
  if (body.kind === "test") {
    const profileIds = Array.isArray(body.profile_ids) ? body.profile_ids : [];
    if (profileIds.length === 0) {
      return new Response("profile_ids requis", { status: 400 });
    }
    const result = await sendFixedPayloadToProfiles(
      supabase,
      profileIds,
      {
        title: "Test AS Grinta",
        body: "Si tu vois ceci, les notifications fonctionnent 🎉",
        url: ".",
        tag: "test-push",
      },
      { public: config.vapid_public, private: config.vapid_private },
      { kind: "test", matchId: null },
    );
    return Response.json(result);
  }

  // Contenu préparé par la base pour des destinataires précis : message libre
  // d'un administrateur, convocation, composition, résultat HDM, badges…
  // Le titre et le texte viennent de la RPC, qui a déjà vérifié les droits et
  // borné leur longueur. L'écran à ouvrir est facultatif : une route de
  // l'application, sinon l'accueil. Le type et le match servent au journal de
  // livraison et à l'historique ; une notification d'essai demande à ne pas
  // être rangée (record_history = false).
  if (body.kind === "custom") {
    const profileIds = Array.isArray(body.profile_ids) ? body.profile_ids : [];
    const title = typeof body.title === "string" ? body.title.trim() : "";
    const message = typeof body.message === "string" ? body.message.trim() : "";
    if (profileIds.length === 0) {
      return new Response("profile_ids requis", { status: 400 });
    }
    if (!title || !message) {
      return new Response("title et message requis", { status: 400 });
    }
    const result = await sendFixedPayloadToProfiles(
      supabase,
      profileIds,
      {
        title,
        body: message,
        url: safeNotificationUrl(body.url),
        tag: `custom-${Date.now()}`,
      },
      { public: config.vapid_public, private: config.vapid_private },
      {
        kind: targetedDeliveryLogKind(body.log_kind),
        matchId: optionalMatchId(body.match_id),
      },
      shouldRecordHistory(body) ? { kind: historyKind(body.log_kind) } : null,
    );
    return Response.json(result);
  }

  if (!body.kind || !body.match_id) {
    return new Response("kind et match_id requis", { status: 400 });
  }

  const isSportsAvailability = sportsAvailabilityKinds.has(body.kind);
  if (
    isSportsAvailability &&
    (!Array.isArray(body.profile_ids) || body.profile_ids.length === 0)
  ) {
    return new Response("profile_ids requis pour ce type d’envoi", {
      status: 400,
    });
  }

  const dispatchResult = isSportsAvailability
    ? await supabase.rpc("internal_sport_push_dispatch", {
      p_kind: body.kind,
      p_match_id: body.match_id,
      p_profile_ids: body.profile_ids,
    })
    : await supabase.rpc("internal_push_dispatch", {
      p_kind: body.kind,
      p_match_id: body.match_id,
    });

  const { data: dispatch, error: dispatchError } = dispatchResult;
  if (dispatchError || !dispatch) {
    console.error("send-push dispatch failure", dispatchError);
    return new Response("préparation impossible", { status: 500 });
  }

  const markSportsDelivery = async (
    attempted: number,
    sent: number,
    failed: number,
  ) => {
    if (!isSportsAvailability || !body.notification_event_id) return;
    const { error } = await supabase.rpc(
      "internal_mark_sport_notification_delivery",
      {
        p_event_id: body.notification_event_id,
        p_attempted: attempted,
        p_sent: sent,
        p_failed: failed,
      },
    );
    if (error) console.error("send-push sports event mark failure", error);
  };

  const subscriptions: SubscriptionRow[] = dispatch.subscriptions ?? [];

  // Sans titre, rien n'est à envoyer (rappel d'un match « entre nous », vote
  // déjà fermé…) : rien n'est rangé non plus.
  const unread = payloadText(dispatch.payload?.title)
    ? await recordHistory(supabase, {
      kind: historyKind(body.kind),
      matchId: optionalMatchId(body.match_id),
      profileIds: historyRecipients(dispatch, subscriptions),
      payload: dispatch.payload,
      dedupeKey: isSportsAvailability && body.notification_event_id
        ? `sport_event:${body.notification_event_id}`
        : null,
    })
    : new Map<string, number>();

  if (subscriptions.length === 0) {
    await markSportsDelivery(0, 0, 0);
    return Response.json({ attempted: 0, sent: 0, failed: 0, pruned: 0 });
  }

  webpush.setVapidDetails(
    "https://samihchaa-wq.github.io/AS-Grinta",
    config.vapid_public,
    config.vapid_private,
  );

  const dead: string[] = [];
  const deliveries: DeliveryLogRow[] = [];
  let sent = 0;

  await Promise.all(
    subscriptions.map(async (sub) => {
      const outcome = await executePushDelivery(() =>
        webpush.sendNotification(
          {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.p256dh, auth: sub.auth },
          },
          payloadForProfile(dispatch.payload, sub.profile_id, unread),
          { TTL: PUSH_DELIVERY_TTL_SECONDS, urgency: "high" },
        )
      );

      if (outcome.success) {
        sent += 1;
        deliveries.push({
          match_id: body.match_id!,
          kind: body.kind!,
          profile_id: sub.profile_id ?? null,
          endpoint_host: endpointHost(sub.endpoint),
          success: true,
          status_code: outcome.statusCode ?? 201,
          error_message: null,
          attempts: outcome.attempts,
        });
        return;
      }

      if (outcome.failureClass === "expired") {
        dead.push(sub.endpoint);
      }

      const message = errorMessage(outcome.error);
      deliveries.push({
        match_id: body.match_id!,
        kind: body.kind!,
        profile_id: sub.profile_id ?? null,
        endpoint_host: endpointHost(sub.endpoint),
        success: false,
        status_code: outcome.statusCode,
        error_message: message,
        attempts: outcome.attempts,
      });
      console.error("send-push delivery failure", {
        profileId: sub.profile_id ?? null,
        endpointHost: endpointHost(sub.endpoint),
        statusCode: outcome.statusCode,
        failureClass: outcome.failureClass,
        attempts: outcome.attempts,
        message,
      });
    }),
  );

  if (deliveries.length > 0) {
    const { error } = await supabase.from("push_delivery_log").insert(deliveries);
    if (error) console.error("send-push log failure", error);
  }

  let pruned = 0;
  if (dead.length > 0) {
    const { data, error } = await supabase.rpc("internal_push_prune", {
      p_endpoints: dead,
    });
    if (error) {
      console.error("send-push prune failure", error);
    } else {
      pruned = data ?? 0;
    }
  }

  await markSportsDelivery(
    subscriptions.length,
    sent,
    subscriptions.length - sent,
  );

  return Response.json({
    attempted: subscriptions.length,
    sent,
    failed: subscriptions.length - sent,
    pruned,
  });
});
