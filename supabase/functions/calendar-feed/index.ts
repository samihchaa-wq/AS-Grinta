import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.95.0";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function escapeIcs(value: unknown): string {
  return String(value ?? "")
    .replaceAll("\\", "\\\\")
    .replaceAll(";", "\\;")
    .replaceAll(",", "\\,")
    .replaceAll("\r\n", "\\n")
    .replaceAll("\n", "\\n")
    .replaceAll("\r", "\\n");
}

function foldLine(value: string): string {
  const maxChars = 72;
  if (value.length <= maxChars) return `${value}\r\n`;
  let result = "";
  for (let offset = 0; offset < value.length; offset += maxChars) {
    result += `${offset === 0 ? "" : " "}${value.slice(offset, offset + maxChars)}\r\n`;
  }
  return result;
}

function formatUtc(value: string | Date): string {
  const date = value instanceof Date ? value : new Date(value);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getUTCFullYear()}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}T${pad(date.getUTCHours())}${pad(date.getUTCMinutes())}${pad(date.getUTCSeconds())}Z`;
}

function sequenceFor(value: string | null | undefined): number {
  const ms = value ? Date.parse(value) : Date.now();
  return Number.isFinite(ms) ? Math.max(0, Math.floor(ms / 1000)) : 0;
}

function summaryFor(row: Record<string, unknown>): string {
  const opponentRaw = row.opponents;
  const opponent = opponentRaw && typeof opponentRaw === "object"
    ? String((opponentRaw as Record<string, unknown>).name ?? "").trim()
    : String(row.opponent_name ?? "").trim();
  const matchType = String(row.match_type ?? "championnat");
  const location = String(row.location ?? "");
  if (matchType === "entre_nous") {
    return "AS Grinta — Match entre nous";
  }
  const other = opponent || "Adversaire";
  return location === "domicile" ? `AS Grinta - ${other}` : `${other} - AS Grinta`;
}

function descriptionFor(row: Record<string, unknown>): string {
  const matchType = String(row.match_type ?? "championnat");
  if (matchType === "entre_nous") return "AS La Grinta — Match entre nous";
  if (matchType === "amical") return "AS La Grinta — Match amical";
  const round = row.championship_round;
  return round == null ? "AS La Grinta — Championnat" : `AS La Grinta — Championnat · J${round}`;
}

function eventLines(row: Record<string, unknown>): string {
  if (String(row.status ?? "") === "annule") return "";

  const kickoff = String(row.kickoff_at ?? "");
  if (!kickoff || Number.isNaN(Date.parse(kickoff))) return "";
  const start = new Date(kickoff);
  const duration = Number(row.planned_duration_minutes ?? 90);
  const end = new Date(start.getTime() + (Number.isFinite(duration) ? duration : 90) * 60_000);
  const changedAt = String(row.updated_at ?? row.created_at ?? kickoff);
  const id = String(row.id ?? "");
  if (!id) return "";

  let out = "BEGIN:VEVENT\r\n";
  out += foldLine(`UID:${escapeIcs(id)}@sporteasy-grinta`);
  out += `DTSTAMP:${formatUtc(new Date())}\r\n`;
  out += `LAST-MODIFIED:${formatUtc(changedAt)}\r\n`;
  out += `SEQUENCE:${sequenceFor(changedAt)}\r\n`;
  out += `DTSTART:${formatUtc(start)}\r\n`;
  out += `DTEND:${formatUtc(end)}\r\n`;
  out += foldLine(`SUMMARY:${escapeIcs(summaryFor(row))}`);
  out += foldLine(`DESCRIPTION:${escapeIcs(descriptionFor(row))}`);
  const address = String(row.address ?? "").trim();
  if (address) out += foldLine(`LOCATION:${escapeIcs(address)}`);
  out += "STATUS:CONFIRMED\r\n";
  out += "END:VEVENT\r\n";
  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
  }

  const token = new URL(req.url).searchParams.get("token")?.trim() ?? "";
  if (!UUID_RE.test(token)) return new Response("Not found", { status: 404 });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return new Response("Server configuration error", { status: 500 });

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: subscription, error: subscriptionError } = await admin
    .from("calendar_subscriptions")
    .select("profile_id, profiles!inner(status)")
    .eq("token", token)
    .eq("profiles.status", "active")
    .maybeSingle();

  if (subscriptionError) {
    console.error("calendar-feed subscription lookup failed", subscriptionError);
    return new Response("Calendar unavailable", { status: 500 });
  }
  if (!subscription) return new Response("Not found", { status: 404 });

  const { data: matches, error: matchesError } = await admin
    .from("matches")
    .select("id,kickoff_at,planned_duration_minutes,status,location,address,match_type,championship_round,created_at,updated_at,opponents(name),seasons!inner(name,status)")
    .eq("seasons.status", "open")
    .order("kickoff_at", { ascending: true });

  if (matchesError) {
    console.error("calendar-feed data fetch failed", matchesError);
    return new Response("Calendar unavailable", { status: 500 });
  }

  const now = new Date();
  let ics = "BEGIN:VCALENDAR\r\n";
  ics += "VERSION:2.0\r\n";
  ics += "PRODID:-//AS La Grinta//Calendrier dynamique//FR\r\n";
  ics += "CALSCALE:GREGORIAN\r\n";
  ics += "METHOD:PUBLISH\r\n";
  ics += foldLine("X-WR-CALNAME:AS La Grinta");
  ics += "REFRESH-INTERVAL;VALUE=DURATION:PT15M\r\n";
  ics += "X-PUBLISHED-TTL:PT15M\r\n";

  for (const row of matches ?? []) {
    ics += eventLines(row as Record<string, unknown>);
  }
  ics += "END:VCALENDAR\r\n";

  const headers = {
    "Content-Type": "text/calendar; charset=utf-8",
    "Content-Disposition": "inline; filename=\"as-grinta.ics\"",
    "Cache-Control": "no-cache, no-store, must-revalidate",
    "ETag": `W/\"${sequenceFor(now.toISOString())}\"`,
  };
  return new Response(req.method === "HEAD" ? null : ics, { status: 200, headers });
});
