#!/usr/bin/env python3
"""Sanitize and reject secret-like material in local Supabase CI artifacts.

This script only reads and rewrites the disposable GitHub Actions artifact
directory. It never connects to Supabase or any external service.
"""

from __future__ import annotations

from pathlib import Path
import argparse
import re


SUBSTITUTIONS: tuple[tuple[re.Pattern[str], str], ...] = (
    (
        re.compile(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"),
        "[REDACTED_LOCAL_JWT]",
    ),
    (
        re.compile(r"sb_(?:publishable|secret)_[A-Za-z0-9_-]+"),
        "[REDACTED_LOCAL_KEY]",
    ),
    (
        re.compile(r"postgresql://[^:\s/]+:[^@\s]+@"),
        "postgresql://[REDACTED_LOCAL_CREDENTIALS]@",
    ),
    (
        re.compile(r"CI-Local-Only-Password-[^\s'\"]+"),
        "[REDACTED_LOCAL_PASSWORD]",
    ),
    (
        re.compile(r"(?im)^(\s*Access Key\s*│\s*).+$"),
        r"\1[REDACTED_LOCAL_S3_ACCESS_KEY]",
    ),
    (
        re.compile(r"(?im)^(\s*Secret Key\s*│\s*).+$"),
        r"\1[REDACTED_LOCAL_S3_SECRET_KEY]",
    ),
    (
        re.compile(
            r"(?im)^((?:ANON_KEY|SERVICE_ROLE_KEY|SECRET_KEY_BASE|"
            r"S3_PROTOCOL_ACCESS_KEY_ID|S3_PROTOCOL_ACCESS_KEY_SECRET)=).+$"
        ),
        r"\1[REDACTED_LOCAL_SECRET]",
    ),
)

FORBIDDEN: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "JWT",
        re.compile(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"),
    ),
    (
        "Supabase key",
        re.compile(r"sb_(?:publishable|secret)_[A-Za-z0-9_-]+"),
    ),
    (
        "credential-bearing PostgreSQL URL",
        re.compile(r"postgresql://[^:\s/]+:[^@\s]+@"),
    ),
    (
        "local CI password",
        re.compile(r"CI-Local-Only-Password-[^\s'\"]+"),
    ),
    (
        "S3 access key",
        re.compile(r"(?im)^\s*Access Key\s*│\s*[A-Fa-f0-9]{16,}\s*$"),
    ),
    (
        "S3 secret key",
        re.compile(r"(?im)^\s*Secret Key\s*│\s*[A-Fa-f0-9]{32,}\s*$"),
    ),
    (
        "secret environment assignment",
        re.compile(
            r"(?im)^(?:ANON_KEY|SERVICE_ROLE_KEY|SECRET_KEY_BASE|"
            r"S3_PROTOCOL_ACCESS_KEY_ID|S3_PROTOCOL_ACCESS_KEY_SECRET)="
            r"(?!\[REDACTED)[^\s]+$"
        ),
    ),
)


def sanitize(path: Path) -> None:
    text = path.read_text(encoding="utf-8", errors="replace")
    for pattern, replacement in SUBSTITUTIONS:
        text = pattern.sub(replacement, text)
    path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact_dir", type=Path)
    args = parser.parse_args()

    root: Path = args.artifact_dir
    root.mkdir(parents=True, exist_ok=True)
    scan_log = root / "artifact-secret-scan.log"
    scan_log.unlink(missing_ok=True)

    files = sorted(path for path in root.rglob("*") if path.is_file())
    for path in files:
        sanitize(path)

    failures: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        for label, pattern in FORBIDDEN:
            if pattern.search(text):
                failures.append(f"{path.relative_to(root)}: {label}")

    if failures:
        scan_log.write_text(
            "FAIL: secret-like material remains in the artifact:\n"
            + "\n".join(f"- {failure}" for failure in failures)
            + "\n",
            encoding="utf-8",
        )
        for failure in failures:
            print(failure)
        return 1

    scan_log.write_text(
        "PASS: artifact sanitized; no JWT, Supabase key, local password, "
        "credential-bearing PostgreSQL URL, local S3 key, or secret environment "
        "assignment remains.\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
