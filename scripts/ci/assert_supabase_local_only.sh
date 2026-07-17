#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  files=(
    .github/workflows/supabase_local_validation.yml
    scripts/ci/run_supabase_local_validation.sh
    scripts/ci/normalize_local_migration_versions.py
    scripts/ci/generate_historical_match_fixtures.py
    scripts/ci/supabase_legacy_baseline.sql
    scripts/ci/supabase_legacy_match_status_text.sql
    scripts/ci/supabase_legacy_postmatch.sql
    scripts/ci/supabase_legacy_coach_tables.sql
    scripts/ci/supabase_legacy_analytics_views.sql
    scripts/ci/supabase_legacy_claim_transition.sql
    scripts/ci/supabase_legacy_post_goals_views.sql
    scripts/ci/supabase_legacy_named_roster_transition.sql
    scripts/ci/supabase_legacy_match_location.sql
    scripts/ci/supabase_legacy_season_rpcs.sql
    scripts/ci/supabase_legacy_odds_v3.sql
    supabase/tests/phase1_ci_seed.sql
    supabase/tests/phase1_ci_snapshot.sql
    supabase/tests/phase1_ci_permissions.sql
    supabase/tests/phase1_ci_rollback_assertions.sql
    supabase/tests/phase1_security_hardening.sql
  )
else
  files=("$@")
fi

for file in "${files[@]}"; do
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
  if grep -nEi -- "$pattern" "${files[@]}"; then
    echo "Forbidden remote-capable Supabase command or credential reference detected: $pattern" >&2
    failed=1
  fi
done

if grep -nE -- 'https://[a-z]{20}\.supabase\.co|db\.[a-z]{20}\.supabase\.co' "${files[@]}"; then
  echo "Remote Supabase project endpoint detected." >&2
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "Local-only guard passed: no remote Supabase command, project endpoint, or credential reference found."
