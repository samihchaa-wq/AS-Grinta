#!/usr/bin/env bash
set -euo pipefail

workflow="${1:-.github/workflows/supabase_local_validation.yml}"
runner="${2:-scripts/ci/run_supabase_local_validation.sh}"

for file in "$workflow" "$runner"; do
  test -f "$file"
done

# Build forbidden expressions from fragments so this guard does not trigger on itself.
patterns=(
  "--lin""ked"
  "supabase[[:space:]]+li""nk"
  "supabase[[:space:]]+db[[:space:]]+pu""sh"
  "supabase[[:space:]]+functions[[:space:]]+de""ploy"
  "supabase[[:space:]]+de""ploy"
  "SUPABASE_ACCESS_""TOKEN"
  "SUPABASE_DB_""PASSWORD"
  "SUPABASE_PROJECT_""ID"
)

failed=0
for pattern in "${patterns[@]}"; do
  if grep -nEi -- "$pattern" "$workflow" "$runner"; then
    echo "Forbidden remote-capable Supabase command or credential reference detected: $pattern" >&2
    failed=1
  fi
done

if grep -nE -- 'https://[a-z]{20}\.supabase\.co|db\.[a-z]{20}\.supabase\.co' "$workflow" "$runner"; then
  echo "Remote Supabase project endpoint detected." >&2
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "Local-only guard passed: no remote Supabase command, project endpoint, or credential reference found."
