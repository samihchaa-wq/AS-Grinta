#!/usr/bin/env python3
"""Rename duplicate migration versions only in an ephemeral CI checkout.

The repository contains historical migrations with an identical numeric prefix.
Supabase CLI stores the numeric prefix as a primary key and cannot replay such a
chain from an empty database. This utility preserves lexical file order while
assigning a unique, longer suffix to the second and later duplicates.
"""

from __future__ import annotations

import collections
import pathlib
import re
import sys


MIGRATION_RE = re.compile(r"^(?P<version>\d+)_(?P<name>.+\.sql)$")


def main() -> int:
    directory = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "supabase/migrations")
    files = sorted(path for path in directory.glob("*.sql") if path.is_file())
    grouped: dict[str, list[pathlib.Path]] = collections.defaultdict(list)

    for path in files:
        match = MIGRATION_RE.match(path.name)
        if match:
            grouped[match.group("version")].append(path)

    used_versions = {
        match.group("version")
        for path in files
        if (match := MIGRATION_RE.match(path.name))
    }

    changes: list[tuple[str, str]] = []
    for version, duplicates in sorted(grouped.items()):
        if len(duplicates) < 2:
            continue

        for index, path in enumerate(duplicates[1:], start=1):
            match = MIGRATION_RE.match(path.name)
            assert match is not None
            suffix = index
            while True:
                candidate_version = f"{version}{suffix:02d}"
                if candidate_version not in used_versions:
                    break
                suffix += 1

            destination = path.with_name(f"{candidate_version}_{match.group('name')}")
            path.rename(destination)
            used_versions.add(candidate_version)
            changes.append((path.name, destination.name))

    if changes:
        for source, destination in changes:
            print(f"CI-only migration version normalization: {source} -> {destination}")
    else:
        print("No duplicate migration versions found.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
