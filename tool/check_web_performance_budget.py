#!/usr/bin/env python3
"""Fail CI when the application JavaScript bundle exceeds its web budget."""

from __future__ import annotations

import gzip
import os
from pathlib import Path

MAIN_JS_PATH = Path(os.environ.get("WEB_MAIN_JS_PATH", "build/web/main.dart.js"))

# Le plafond n'est pas une limite technique : c'est un garde-fou choisi, relevé
# le 27 août 2026 de 5 600 000 / 1 600 000 octets. Le bundle atteignait alors
# 91 % du plafond brut, marge trop courte pour absorber une fonctionnalité sans
# bloquer la publication au mauvais moment. Les valeurs actuelles laissent
# environ 15 % de marge tout en gardant l'alerte utile.
#
# Ce qui compte pour les joueurs est la taille gzip : c'est elle qui est
# réellement téléchargée à la première visite. Relever ce plafond achète du
# temps, cela n'allège pas l'application.
#
# Les workflows répètent ces valeurs pour rester lisibles ; toute évolution doit
# les mettre à jour ensemble.
RAW_LIMIT = int(os.environ.get("MAX_MAIN_DART_JS_BYTES", "6000000"))
GZIP_LIMIT = int(os.environ.get("MAX_MAIN_DART_JS_GZIP_BYTES", "1700000"))
SUMMARY_PATH = Path(
    os.environ.get("WEB_PERFORMANCE_SUMMARY", "web-performance-summary.txt")
)


def main() -> int:
    if not MAIN_JS_PATH.is_file():
        raise SystemExit(f"Bundle Web absent : {MAIN_JS_PATH}")

    payload = MAIN_JS_PATH.read_bytes()
    raw_size = len(payload)
    gzip_size = len(gzip.compress(payload, compresslevel=9, mtime=0))

    summary = (
        f"Bundle : {MAIN_JS_PATH}\n"
        f"Taille brute : {raw_size} / {RAW_LIMIT} octets\n"
        f"Taille gzip : {gzip_size} / {GZIP_LIMIT} octets\n"
        f"Marge brute : {RAW_LIMIT - raw_size} octets\n"
        f"Marge gzip : {GZIP_LIMIT - gzip_size} octets\n"
    )
    SUMMARY_PATH.write_text(summary, encoding="utf-8")
    print(summary, end="")

    failures: list[str] = []
    if raw_size > RAW_LIMIT:
        failures.append(f"brut {raw_size} > {RAW_LIMIT}")
    if gzip_size > GZIP_LIMIT:
        failures.append(f"gzip {gzip_size} > {GZIP_LIMIT}")
    if failures:
        raise SystemExit(
            "Budget de performance Web dépassé : " + ", ".join(failures)
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
