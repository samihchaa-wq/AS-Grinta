#!/usr/bin/env python3
"""Version critical Web shell scripts inside the built deployment artifact."""

from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import quote

INDEX_PATH = Path(os.environ.get("WEB_INDEX_PATH", "build/web/index.html"))
BOOTSTRAP_PATH = Path(
    os.environ.get("WEB_BOOTSTRAP_PATH", "build/web/flutter_bootstrap.js")
)
WEB_VERSION = os.environ.get("WEB_VERSION", "").strip()

# Adresse du programme principal dans la configuration générée par Flutter.
MAIN_JS_REFERENCE = '"mainJsPath":"main.dart.js"'


def encode_version(version: str) -> str:
    """Encode comme `encodeURIComponent` en JavaScript (web/sw.js)."""
    return quote(version, safe="-_.!~*'()")


def stamp_index() -> None:
    html = INDEX_PATH.read_text(encoding="utf-8")
    replacements = {
        'src="build_version.js"': f'src="build_version.js?v={WEB_VERSION}"',
        'src="app_shell.js"': f'src="app_shell.js?v={WEB_VERSION}"',
    }

    for source, stamped in replacements.items():
        if source not in html:
            raise SystemExit(f"Référence de shell introuvable dans {INDEX_PATH}: {source}")
        html = html.replace(source, stamped, 1)

    INDEX_PATH.write_text(html, encoding="utf-8")


def stamp_bootstrap() -> None:
    """Donne au programme principal une adresse propre à la version.

    Le service worker garde alors ce programme sur le téléphone sans risque :
    une page d'une version ne peut jamais recevoir celui d'une autre.
    """
    script = BOOTSTRAP_PATH.read_text(encoding="utf-8")
    if script.count(MAIN_JS_REFERENCE) != 1:
        raise SystemExit(
            f"Adresse du programme principal introuvable ou ambiguë dans "
            f"{BOOTSTRAP_PATH}: {MAIN_JS_REFERENCE}"
        )
    stamped = f'"mainJsPath":"main.dart.js?v={encode_version(WEB_VERSION)}"'
    BOOTSTRAP_PATH.write_text(
        script.replace(MAIN_JS_REFERENCE, stamped, 1), encoding="utf-8"
    )


def main() -> int:
    if not WEB_VERSION:
        raise SystemExit("WEB_VERSION est requis pour versionner le shell Web.")
    if not INDEX_PATH.is_file():
        raise SystemExit(f"Index Web absent : {INDEX_PATH}")
    if not BOOTSTRAP_PATH.is_file():
        raise SystemExit(f"Bootstrap Web absent : {BOOTSTRAP_PATH}")

    stamp_index()
    stamp_bootstrap()
    print(f"Shell Web versionné pour {WEB_VERSION}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
