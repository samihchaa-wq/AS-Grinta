import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

type Reminder = {
  device_id: string;
  token: string;
  platform: "web" | "ios" | "android";
  match_id: string;
  profile_id: string;
  reminder_type: "24h" | "2h";
  opponent_name: string;
};

type FirebaseServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

const jsonHeaders = { "Content-Type": "application/json" };

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

async function getGoogleAccessToken(
  credentials: FirebaseServiceAccount,
): Promise<string> {
  const tokenUri = credentials.token_uri ?? "https://oauth2.googleapis.com/token";
  const privateKey = await importPKCS8(credentials.private_key, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(credentials.client_email)
    .setSubject(credentials.client_email)
    .setAudience(tokenUri)
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(privateKey);

  const tokenResponse = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const payload = await tokenResponse.json();
  if (!tokenResponse.ok || typeof payload.access_token !== "string") {
    throw new Error(`Firebase OAuth failed: ${JSON.stringify(payload)}`);
  }
  return payload.access_token;
}

function notificationFor(reminder: Reminder) {
  if (reminder.reminder_type === "24h") {
    return {
      title: "Pronostics ouverts",
      body: `Les pronostics pour AS Grinta - ${reminder.opponent_name} sont ouverts.`,
    };
  }
  return {
    title: "Rappel pronostic",
    body: `Plus que 2 heures pour pronostiquer AS Grinta - ${reminder.opponent_name}.`,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return response({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return response({ error: "Missing Supabase runtime configuration" }, 500);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const cronSecret = req.headers.get("x-cron-secret") ?? "";
  const { data: secretIsValid, error: secretError } = await supabase.rpc(
    "validate_prediction_reminder_cron_secret",
    { p_secret: cronSecret },
  );
  if (secretError || secretIsValid !== true) {
    return response({ error: "Unauthorized" }, 401);
  }

  const serviceAccountRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!serviceAccountRaw) {
    console.error("FIREBASE_SERVICE_ACCOUNT_JSON is not configured");
    return response({ configured: false, sent: 0 });
  }

  let credentials: FirebaseServiceAccount;
  try {
    credentials = JSON.parse(serviceAccountRaw) as FirebaseServiceAccount;
  } catch {
    return response({ error: "Invalid FIREBASE_SERVICE_ACCOUNT_JSON" }, 500);
  }
  if (!credentials.project_id || !credentials.client_email || !credentials.private_key) {
    return response({ error: "Incomplete Firebase service account" }, 500);
  }

  const { data, error } = await supabase.rpc("due_prediction_reminders");
  if (error) return response({ error: error.message }, 500);
  const reminders = (data ?? []) as Reminder[];
  if (reminders.length === 0) return response({ configured: true, sent: 0 });

  const accessToken = await getGoogleAccessToken(credentials);
  let sent = 0;
  const failures: Array<{ deviceId: string; status: number; body: string }> = [];

  for (const reminder of reminders) {
    const notification = notificationFor(reminder);
    const fcmResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: reminder.token,
            notification,
            data: {
              match_id: reminder.match_id,
              reminder_type: reminder.reminder_type,
              route: `/matches/${reminder.match_id}`,
            },
            webpush: {
              fcm_options: {
                link: `${Deno.env.get("APP_PUBLIC_URL") ?? "https://samihchaa-wq.github.io/AS-Grinta/"}matches/${reminder.match_id}`,
              },
            },
          },
        }),
      },
    );

    if (fcmResponse.ok) {
      const { error: deliveryError } = await supabase.rpc(
        "record_prediction_reminder_delivery",
        {
          p_match_id: reminder.match_id,
          p_profile_id: reminder.profile_id,
          p_device_id: reminder.device_id,
          p_reminder_type: reminder.reminder_type,
        },
      );
      if (deliveryError) {
        failures.push({
          deviceId: reminder.device_id,
          status: 500,
          body: deliveryError.message,
        });
      } else {
        sent++;
      }
      continue;
    }

    const body = await fcmResponse.text();
    failures.push({ deviceId: reminder.device_id, status: fcmResponse.status, body });
    if (
      fcmResponse.status === 404 ||
      body.includes("UNREGISTERED") ||
      body.includes("registration-token-not-registered")
    ) {
      await supabase
        .from("push_devices")
        .update({ is_active: false, updated_at: new Date().toISOString() })
        .eq("id", reminder.device_id);
    }
  }

  return response({ configured: true, due: reminders.length, sent, failures });
});
