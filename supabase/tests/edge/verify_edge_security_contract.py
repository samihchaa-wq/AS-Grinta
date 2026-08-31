#!/usr/bin/env python3
"""Static, fail-closed security contract for deployed Edge Function sources."""

from __future__ import annotations

import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONFIG_PATH = ROOT / "supabase" / "config.toml"
FUNCTIONS_DIR = ROOT / "supabase" / "functions"


class ContractError(AssertionError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def source(slug: str) -> str:
    path = FUNCTIONS_DIR / slug / "index.ts"
    require(path.is_file(), f"source Edge manquante: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def function_file(slug: str, filename: str) -> str:
    path = FUNCTIONS_DIR / slug / filename
    require(path.is_file(), f"source Edge manquante: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def require_in_order(text: str, first: str, second: str, message: str) -> None:
    first_index = text.find(first)
    second_index = text.find(second)
    require(first_index >= 0, f"marqueur absent: {first!r}")
    require(second_index >= 0, f"marqueur absent: {second!r}")
    require(first_index < second_index, message)


def main() -> int:
    config = tomllib.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    functions = config.get("functions", {})

    expected_jwt = {
        "manage-user": True,
        "claim-account": True,
        "register-account": False,
        "send-push": False,
        "send-prediction-reminders": True,
        "calendar-feed": False,
    }
    versioned_functions = {
        path.name
        for path in FUNCTIONS_DIR.iterdir()
        if path.is_dir() and (path / "index.ts").is_file()
    }
    require(
        versioned_functions == set(expected_jwt),
        "inventaire Edge inattendu: "
        f"présent={sorted(versioned_functions)}, "
        f"attendu={sorted(expected_jwt)}",
    )
    require(
        set(functions) == set(expected_jwt),
        "configuration Edge inattendue: "
        f"présent={sorted(functions)}, attendu={sorted(expected_jwt)}",
    )
    for slug, expected in expected_jwt.items():
        actual = functions[slug].get("verify_jwt")
        require(
            actual is expected,
            f"{slug}: verify_jwt={actual!r}, attendu {expected!r}",
        )

    manage = source("manage-user")
    for marker in (
        'req.method !== "POST"',
        'authHeader?.startsWith("Bearer ")',
        "contentLength > 16_384",
        "callerClient.auth.getUser(token)",
        'String(callerProfile?.role) !== "admin"',
        'callerProfile?.status !== "active"',
        'targetProfile.role === "admin"',
        '.eq("role", "admin")',
        '"The last active admin cannot be deleted"',
        "deleteProfileWithRetry(admin, userId)",
    ):
        require(marker in manage, f"manage-user: garde absente: {marker}")
    require(
        'String(callerProfile?.role) !== "moderateur"' not in manage,
        "manage-user ne doit plus référencer le rôle moderateur retiré",
    )
    require_in_order(
        manage,
        "callerClient.auth.getUser(token)",
        "createClient(supabaseUrl, serviceRoleKey",
        "manage-user doit valider le JWT avant de créer le client privilégié",
    )
    require_in_order(
        manage,
        'callerProfile?.status !== "active"',
        "const body = await req.json()",
        "manage-user doit vérifier l’admin actif avant de traiter le corps",
    )
    require_in_order(
        manage,
        'targetProfile.role === "admin"',
        'admin.rpc(\n        "prepare_profile_for_hard_deletion"',
        "manage-user doit protéger le dernier admin avant toute suppression",
    )

    register = source("register-account")
    for marker in (
        'req.method !== "POST"',
        "MAX_BODY_BYTES = 4_096",
        "RequestBodyTooLargeError",
        'req.headers.get("content-length")',
        "req.body.getReader()",
        "totalBytes > maxBytes",
        "await reader.cancel()",
        "readBoundedJson<Record<string, unknown>>(req, MAX_BODY_BYTES)",
        '"consume_registration_rate_limit"',
        "validatePassword(password)",
        "SUPABASE_SERVICE_ROLE_KEY",
        "admin.auth.admin.deleteUser",
    ):
        require(marker in register, f"register-account: garde absente: {marker}")
    require(
        "body = await req.json()" not in register,
        "register-account ne doit pas revenir à une lecture non bornée avec req.json()",
    )
    require_in_order(
        register,
        "readBoundedJson<Record<string, unknown>>(req, MAX_BODY_BYTES)",
        "validatePassword(password)",
        "register-account doit lire de façon bornée puis valider la demande avant la création Auth",
    )
    require_in_order(
        register,
        "validatePassword(password)",
        '"consume_registration_rate_limit"',
        "register-account doit rejeter les demandes invalides avant de consommer le quota partagé",
    )
    require_in_order(
        register,
        '"consume_registration_rate_limit"',
        "admin.auth.admin.createUser",
        "register-account doit limiter le débit avant la création Auth",
    )

    push = source("send-push")
    for marker in (
        'req.method !== "POST"',
        'req.headers.get("x-push-token")',
        '"internal_push_config"',
        "await secretsEqual(token, String(config.token))",
        "readBoundedJson<PushRequestBody>(req)",
        "RequestBodyTooLargeError",
        'return new Response("non autorisé", { status: 401 })',
        'return new Response("corps trop volumineux", { status: 413 })',
    ):
        require(marker in push, f"send-push: garde absente: {marker}")
    require(
        "token !== config.token" not in push,
        "send-push ne doit plus comparer le secret interne directement",
    )
    require_in_order(
        push,
        "await secretsEqual(token, String(config.token))",
        "readBoundedJson<PushRequestBody>(req)",
        "send-push doit valider le secret interne avant de traiter le corps",
    )
    require_in_order(
        push,
        "await secretsEqual(token, String(config.token))",
        'supabase.rpc("internal_push_dispatch"',
        "send-push doit valider le secret interne avant toute distribution",
    )

    push_security = function_file("send-push", "request_security.ts")
    for marker in (
        "MAX_BODY_BYTES = 16_384",
        'crypto.subtle.digest("SHA-256"',
        "difference |= candidateDigest[index] ^ expectedDigest[index]",
        'req.headers.get("content-length")',
        "req.body.getReader()",
        "totalBytes > maxBytes",
        "await reader.cancel()",
    ):
        require(
            marker in push_security,
            f"send-push/request_security: garde absente: {marker}",
        )

    calendar = source("calendar-feed")
    for marker in (
        'req.method !== "GET" && req.method !== "HEAD"',
        'searchParams.get("token")',
        "UUID_RE.test(token)",
        'from("calendar_subscriptions")',
        '.eq("token", token)',
        '.eq("profiles.status", "active")',
        'Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")',
        'from("matches")',
        'String(row.status ?? "") === "annule"',
        'STATUS:CONFIRMED',
        'Cache-Control": "no-cache, no-store, must-revalidate"',
    ):
        require(marker in calendar, f"calendar-feed: garde absente: {marker}")
    require(
        'from("calendar_match_tombstones")' not in calendar,
        "calendar-feed ne doit pas republier les matchs supprimés comme événements annulés",
    )
    require(
        'STATUS:CANCELLED' not in calendar and 'ANNULÉ —' not in calendar,
        "calendar-feed ne doit pas exposer d’événement annulé dans le calendrier synchronisé",
    )
    require_in_order(
        calendar,
        "UUID_RE.test(token)",
        'from("calendar_subscriptions")',
        "calendar-feed doit valider le token avant toute lecture privilégiée",
    )
    require_in_order(
        calendar,
        '.eq("profiles.status", "active")',
        'from("matches")',
        "calendar-feed doit vérifier le profil actif avant de charger le calendrier",
    )

    for slug in ("claim-account", "send-prediction-reminders"):
        retired = source(slug)
        require('req.method !== "POST"' in retired, f"{slug}: méthode non filtrée")
        require(
            'status: 410' in retired and '"Endpoint retired"' in retired,
            f"{slug}: l’endpoint neutralisé doit répondre 410",
        )

    print("Edge security contract: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ContractError as error:
        print(f"Edge security contract: FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
