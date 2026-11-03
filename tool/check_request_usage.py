#!/usr/bin/env python3
"""Alarme quotidienne sur le volume de requêtes de la production Supabase.

Le 3 novembre 2026, une boucle invisible dans l'application (la cloche des
alertes de buts) a généré plus de 90 % des requêtes du projet pendant des
semaines, et l'organisation a dépassé les quotas gratuits de Supabase
(données sortantes, journaux) sans que personne ne s'en aperçoive avant
l'avertissement de blocage.

Ce script compare deux instantanés de `pg_stat_statements` (voir
`supabase/diagnostics/request_usage_snapshot.sql`), ramène l'écart à 24 heures
et échoue si un seuil est franchi. Le workflow
`.github/workflows/supabase_usage_guard.yml` le lance chaque jour : un échec
envoie un e-mail de GitHub, avec le détail dans le résumé du run.

Les seuils sont volontairement larges (plusieurs fois l'usage normal) et
restent nettement sous le quota gratuit de 5 Go de données sortantes par mois.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

# Requêtes reçues par l'API de la base (PostgREST) : chaque requête commence
# par cette instruction de préparation, quel que soit son contenu.
API_MARKER = "select set_config('search_path'"
# Chaque exécution d'une tâche planifiée (pg_cron) écrit une ligne ici.
CRON_MARKER = "insert into cron.job_run_details"

# Usage normal constaté après correction de la cloche : quelques milliers de
# requêtes API par jour, environ 25 000 exécutions de tâches planifiées.
DEFAULT_MAX_API_PER_DAY = 40_000
DEFAULT_MAX_STATEMENT_PER_DAY = 15_000
DEFAULT_MAX_CRON_RUNS_PER_DAY = 40_000

# Rôles dont les requêtes viennent de l'extérieur de la base (application,
# fonctions serveur). Les rôles internes (Realtime, pg_cron, Storage…) font
# leur propre travail de fond et ne sont pas comparés au seuil par requête.
CLIENT_ROLES = {"authenticated", "anon", "authenticator", "service_role"}

MIN_ELAPSED_HOURS = 1.0

# Code de sortie réservé au dépassement de seuil, distinct d'un plantage du
# script (1) ou d'une erreur d'arguments (2) : le workflow ne doit pas annoncer
# un volume anormal quand c'est le contrôle lui-même qui a échoué.
EXIT_THRESHOLD_EXCEEDED = 3
MAX_ELAPSED_HOURS = 24.0 * 7


def load_snapshot(path: Path) -> dict:
    raw = json.loads(path.read_text(encoding="utf-8"))
    # L'API de gestion renvoie une liste de lignes : [{"snapshot": {...}}].
    if isinstance(raw, dict) and "result" in raw:
        raw = raw["result"]
    if isinstance(raw, list) and raw and isinstance(raw[0], dict) and "snapshot" in raw[0]:
        raw = raw[0]["snapshot"]
    if isinstance(raw, str):
        raw = json.loads(raw)
    if not isinstance(raw, dict) or "taken_at" not in raw or "entries" not in raw:
        raise ValueError(f"Instantané illisible : {path}")
    return raw


def parse_time(value: str) -> datetime:
    value = value.strip().replace(" ", "T", 1)
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    # PostgreSQL écrit le fuseau sur deux chiffres (+00) : Python veut +00:00.
    if len(value) >= 3 and value[-3] in "+-" and value[-2:].isdigit():
        value += ":00"
    return datetime.fromisoformat(value)


def strip_snapshot(snapshot: dict) -> dict:
    """Version conservée d'un jour à l'autre : clés et compteurs, sans texte."""
    return {
        "taken_at": snapshot["taken_at"],
        "entries": [
            {"key": e["key"], "calls": int(e["calls"])} for e in snapshot["entries"]
        ],
    }


def compare(previous: dict, current: dict) -> dict:
    hours = (
        parse_time(current["taken_at"]) - parse_time(previous["taken_at"])
    ).total_seconds() / 3600
    before = {e["key"]: int(e["calls"]) for e in previous["entries"]}

    deltas = []
    reset_detected = False
    for entry in current["entries"]:
        calls = int(entry["calls"])
        old = before.get(entry["key"])
        if old is None:
            # Nouvelle requête, ou compteur évincé puis recréé : l'écart réel
            # est au plus le compteur actuel.
            delta = calls
        elif calls < old:
            # Compteurs remis à zéro (redémarrage, mise à jour de Postgres).
            reset_detected = True
            delta = calls
        else:
            delta = calls - old
        if delta > 0:
            deltas.append(
                {
                    "delta": delta,
                    "role": entry.get("role", "?"),
                    "query": entry.get("query", ""),
                }
            )

    scale = 24 / hours if hours > 0 else 0
    api = sum(d["delta"] for d in deltas if d["query"].startswith(API_MARKER))
    cron = sum(d["delta"] for d in deltas if d["query"].startswith(CRON_MARKER))

    # Une même requête de l'application peut exister en plusieurs variantes
    # (colonnes, filtres) : elles sont regroupées sous le nom de la fonction ou
    # de la table appelée.
    grouped: dict[tuple[str, str], int] = {}
    for d in deltas:
        if d["role"] not in CLIENT_ROLES:
            continue
        if d["query"].startswith(API_MARKER) or d["query"].startswith("<"):
            continue
        label = (d["role"], d["query"])
        grouped[label] = grouped.get(label, 0) + d["delta"]
    statements = sorted(
        ({"role": role, "query": query, "delta": delta}
         for (role, query), delta in grouped.items()),
        key=lambda d: d["delta"],
        reverse=True,
    )
    return {
        "hours": hours,
        "reset_detected": reset_detected,
        "api_per_day": round(api * scale),
        "cron_per_day": round(cron * scale),
        "top_statements": [
            {**d, "per_day": round(d["delta"] * scale)} for d in statements[:10]
        ],
    }


def evaluate(result: dict, limits: dict) -> list[str]:
    problems = []
    if result["api_per_day"] > limits["api"]:
        problems.append(
            f"{result['api_per_day']:,} requêtes API par jour "
            f"(seuil {limits['api']:,})".replace(",", " ")
        )
    if result["cron_per_day"] > limits["cron"]:
        problems.append(
            f"{result['cron_per_day']:,} exécutions de tâches planifiées par jour "
            f"(seuil {limits['cron']:,})".replace(",", " ")
        )
    for statement in result["top_statements"]:
        if statement["per_day"] > limits["statement"]:
            problems.append(
                f"une même requête appelée {statement['per_day']:,} fois par jour "
                f"(seuil {limits['statement']:,}) : `{statement['query'][:120]}`".replace(",", " ")
            )
    return problems


def fmt(n: int) -> str:
    return f"{n:,}".replace(",", " ")


def render_summary(result: dict | None, problems: list[str], note: str | None) -> str:
    lines = ["## Volume de requêtes Supabase (production)", ""]
    if note:
        lines += [note, ""]
    if result is None:
        return "\n".join(lines) + "\n"

    verdict = "🔴 Seuil dépassé" if problems else "🟢 Dans les clous"
    lines += [
        f"**{verdict}** — période mesurée : {result['hours']:.1f} h, ramenée à 24 h.",
        "",
        "| Mesure | Par jour |",
        "|---|---:|",
        f"| Requêtes API (application, fonctions serveur) | {fmt(result['api_per_day'])} |",
        f"| Exécutions de tâches planifiées | {fmt(result['cron_per_day'])} |",
        "",
    ]
    if result["reset_detected"]:
        lines += [
            "_Les compteurs ont été remis à zéro pendant la période "
            "(redémarrage de la base) : les chiffres sont sous-estimés._",
            "",
        ]
    if problems:
        lines += ["### Problèmes", ""] + [f"- {p}" for p in problems] + [""]
    if result["top_statements"]:
        lines += ["### Requêtes les plus appelées", "", "| Par jour | Rôle | Requête |", "|---:|---|---|"]
        for s in result["top_statements"]:
            query = s["query"].replace("|", "\\|")[:120]
            lines.append(f"| {fmt(s['per_day'])} | {s['role']} | `{query}` |")
        lines.append("")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current", type=Path, required=True)
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--output", type=Path, required=True,
                        help="Instantané allégé à conserver pour le lendemain.")
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--max-api-per-day", type=int, default=DEFAULT_MAX_API_PER_DAY)
    parser.add_argument("--max-statement-per-day", type=int, default=DEFAULT_MAX_STATEMENT_PER_DAY)
    parser.add_argument("--max-cron-runs-per-day", type=int, default=DEFAULT_MAX_CRON_RUNS_PER_DAY)
    args = parser.parse_args(argv)

    current = load_snapshot(args.current)
    args.output.write_text(json.dumps(strip_snapshot(current)), encoding="utf-8")

    previous = None
    unreadable_previous = False
    if args.previous and args.previous.exists():
        try:
            previous = load_snapshot(args.previous)
        except (ValueError, KeyError, TypeError):
            unreadable_previous = True

    result = None
    problems: list[str] = []
    note = None
    if previous is None:
        note = (
            "Relevé précédent illisible : celui du jour sert de nouveau point de départ."
            if unreadable_previous
            else "Premier relevé : il sert de point de départ, la comparaison commencera demain."
        )
    else:
        result = compare(previous, current)
        if result["hours"] < MIN_ELAPSED_HOURS or result["hours"] > MAX_ELAPSED_HOURS:
            note = (
                f"Relevé précédent trop {'proche' if result['hours'] < MIN_ELAPSED_HOURS else 'ancien'} "
                f"({result['hours']:.1f} h) : nouveau point de départ, pas de verdict."
            )
            result = None
        else:
            problems = evaluate(
                result,
                {
                    "api": args.max_api_per_day,
                    "statement": args.max_statement_per_day,
                    "cron": args.max_cron_runs_per_day,
                },
            )

    summary = render_summary(result, problems, note)
    print(summary)
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as handle:
            handle.write(summary)
    return EXIT_THRESHOLD_EXCEEDED if problems else 0


if __name__ == "__main__":
    sys.exit(main())
