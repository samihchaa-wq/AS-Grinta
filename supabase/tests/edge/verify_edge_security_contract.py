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
        'String(callerProfile?.role) !== "moderateur"',
        'callerProfile?.status !== "active"',
        'targetProfile.role === "moderateur"',
        '.eq("role", "moderateur")',
        '"The last active moderator cannot be deleted"',
    ):
        require(marker in manage, f"manage-user: garde absente: {marker}")
    require(
        'String(callerProfile?.role) !== "admin"' not in manage,
        "manage-user ne doit jamais revenir à un garde strict admin",
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
        "manage-user doit vérifier le modérateur actif avant de traiter le corps",
    )
    require_in_order(
        manage,
        'targetProfile.role === "moderateur"',
        'admin.rpc(\n        "prepare_profile_for_hard_deletion"',
        "manage-user doit protéger le dernier modérateur avant toute suppression",
    )

    register = source("register-account")
    for marker in (
        'req.method !== "POST"',
        "MAX_BODY_BYTES",
        '"consume_registration_rate_limit"',
        "validatePassword(password)",
        "SUPABASE_SERVICE_ROLE_KEY",
        "admin.auth.admin.deleteUser",
    ):
        require(marker in register, f"register-account: garde absente: {marker}")
    require_in_order(
        register,
        '"consume_registration_rate_limit"',
        "const body = await req.json()",
        "register-account doit limiter le débit avant de lire et traiter la demande",
    )
    require_in_order(
        register,
        "validatePassword(password)",
        "admin.auth.admin.createUser",
        "register-account doit valider le mot de passe avant la création Auth",
    )

    push = source("send-push")
    for marker in (
        'req.method !== "POST"',
        'req.headers.get("x-push-token")',
        '"internal_push_config"',
        "token !== config.token",
        'return new Response("non autorisé", { status: 401 })',
    ):
        require(marker in push, f"send-push: garde absente: {marker}")
    require_in_order(
        push,
        "token !== config.token",
        "body = await req.json()",
        "send-push doit valider le secret interne avant de traiter le corps",
    )
    require_in_order(
        push,
        "token !== config.token",
        'supabase.rpc("internal_push_dispatch"',
        "send-push doit valider le secret interne avant toute distribution",
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
