#!/usr/bin/env python3
"""Fait échouer le contrôle quand `supabase db lint` trouve une vraie erreur.

Entrée : la sortie de
`supabase db lint --schema public,private --level error --output-format json`.

Seuls les faux positifs connus ci-dessous sont ignorés. Tout autre problème,
y compris une autre erreur dans l'une de ces fonctions, fait échouer le
contrôle.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Ces fonctions créent une table temporaire (`create temporary table ...`) au
# moment où elles s'exécutent, puis la remplissent. L'analyse statique ne voit
# pas cette table et signale « relation "pg_temp.xxx" does not exist » : c'est
# un faux positif. Seule cette erreur précise est ignorée pour elles.
KNOWN_PG_TEMP_FALSE_POSITIVES = {
    "private.create_postmatch_composition",
    "private.finalize_match_sport_postgame",
    "private.publish_match_effectif",
    "private.resequence_sport_waitlist",
    "private.save_match_composition",
    "private.save_match_live_lineup",
    "private.update_postmatch_composition",
    "private.submit_match_sport_report",
}

PG_TEMP_MISSING = re.compile(r'^relation "pg_temp\.[a-z0-9_]+" does not exist$')


def is_known_false_positive(function: str, issue: dict) -> bool:
    return (
        function in KNOWN_PG_TEMP_FALSE_POSITIVES
        and issue.get("sqlState") == "42P01"
        and PG_TEMP_MISSING.match(str(issue.get("message", ""))) is not None
    )


def load_results(raw: str) -> list[dict]:
    if not raw.strip():
        return []
    data = json.loads(raw)
    if isinstance(data, dict):
        data = data.get("results")
    if not isinstance(data, list):
        raise ValueError("sortie de supabase db lint inattendue")
    return data


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: check_db_lint.py <sortie-json-de-db-lint>", file=sys.stderr)
        return 2

    try:
        results = load_results(Path(argv[1]).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(f"::error::Lecture du résultat de db lint impossible : {error}")
        return 1

    ignored = 0
    real_errors: list[str] = []
    for entry in results:
        function = str(entry.get("function", "?"))
        for issue in entry.get("issues") or []:
            if issue.get("level") != "error":
                continue
            if is_known_false_positive(function, issue):
                ignored += 1
                continue
            real_errors.append(
                f"{function} [{issue.get('sqlState', '?')}] "
                f"{issue.get('message', '')}"
            )

    print(f"Faux positifs pg_temp connus ignorés : {ignored}")
    if real_errors:
        for error in real_errors:
            print(f"::error::db lint : {error}")
        print(f"{len(real_errors)} erreur(s) réelle(s) dans les fonctions SQL.")
        return 1

    print("Aucune erreur réelle dans les fonctions des schémas public et private.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
