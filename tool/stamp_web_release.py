#!/usr/bin/env python3
"""Version critical Web shell scripts inside the built deployment artifact."""

from __future__ import annotations

import os
from pathlib import Path

INDEX_PATH = Path(os.environ.get("WEB_INDEX_PATH", "build/web/index.html"))
WEB_VERSION = os.environ.get("WEB_VERSION", "").strip()


def main() -> int:
    if not WEB_VERSION:
        raise SystemExit("WEB_VERSION est requis pour versionner le shell Web.")
    if not INDEX_PATH.is_file():
        raise SystemExit(f"Index Web absent : {INDEX_PATH}")

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
    print(f"Shell Web versionné pour {WEB_VERSION}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
