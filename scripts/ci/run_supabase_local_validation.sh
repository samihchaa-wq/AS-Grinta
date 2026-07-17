#!/usr/bin/env bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
WORK="${RUNNER_TEMP:-/tmp}/as-grinta-supabase-local-${GITHUB_RUN_ID:-manual}"
LOG_DIR="$ROOT/ci-artifacts/supabase-local"
DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
MIGRATION_DIR="$WORK/supabase/migrations"
PHASE1_DIR="$WORK/.phase1-migrations"
STATUS_ENV="${RUNNER_TEMP:-/tmp}/supabase-local-status.env"
NORMAL_RESPONSE="${RUNNER_TEMP:-/tmp}/ci-normal-signup.json"
ADMIN_RESPONSE="${RUNNER_TEMP:-/tmp}/ci-admin-signup.json"

mkdir -p "$LOG_DIR"
rm -rf "$WORK"
mkdir -p "$WORK"

cleanup() {
  set +e
  if [ -d "$WORK" ]; then
    (cd "$WORK" && supabase stop --no-backup >/dev/null 2>&1) || true
  fi
  rm -f "$STATUS_ENV" "$NORMAL_RESPONSE" "$ADMIN_RESPONSE"
  rm -rf "$WORK"
}
trap cleanup EXIT

sanitize_log() {
  python3 - "$1" "$2" <<'PY'
import re
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding='utf-8', errors='replace').read()
text = re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '[REDACTED_LOCAL_JWT]', text)
text = re.sub(r'sb_(?:publishable|secret)_[A-Za-z0-9_-]+', '[REDACTED_LOCAL_KEY]', text)
open(dst, 'w', encoding='utf-8').write(text)
PY
}

rsync -a --exclude '.git' --exclude 'ci-artifacts' "$ROOT/" "$WORK/"
cd "$WORK"

# Use a CI-only local identifier. This changes only the temporary copy.
python3 - <<'PY'
from pathlib import Path
path = Path('supabase/config.toml')
lines = path.read_text(encoding='utf-8').splitlines()
lines = ['project_id = "as-grinta-ci-local"' if line.startswith('project_id = ') else line for line in lines]
path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY

mkdir -p "$PHASE1_DIR"
for file in \
  20260719010000_harden_public_rpc_execute_privileges.sql \
  20260719011000_statistics_view_security_invoker.sql \
  20260719012000_add_fk_supporting_indexes.sql; do
  test -f "$MIGRATION_DIR/$file"
  mv "$MIGRATION_DIR/$file" "$PHASE1_DIR/$file"
done

supabase --version > "$LOG_DIR/supabase-version.log"
supabase start > "${RUNNER_TEMP:-/tmp}/supabase-start.raw.log" 2>&1
sanitize_log "${RUNNER_TEMP:-/tmp}/supabase-start.raw.log" "$LOG_DIR/supabase-start.log"

supabase db reset --local 2>&1 | tee "$LOG_DIR/supabase-db-reset.log"
supabase status -o env > "$STATUS_ENV"
# shellcheck disable=SC1090
source "$STATUS_ENV"

: "${API_URL:?Missing local API_URL}"
: "${ANON_KEY:?Missing local ANON_KEY}"
echo "::add-mask::$ANON_KEY"

PASSWORD='CI-Local-Only-Password-42!'

curl --fail-with-body --silent --show-error \
  "$API_URL/auth/v1/signup" \
  -H "apikey: $ANON_KEY" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"ci-normal@example.invalid\",\"password\":\"$PASSWORD\",\"data\":{\"first_name\":\"CI Normal\",\"last_name\":\"Player\"}}" \
  > "$NORMAL_RESPONSE"

curl --fail-with-body --silent --show-error \
  "$API_URL/auth/v1/signup" \
  -H "apikey: $ANON_KEY" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"ci-admin@example.invalid\",\"password\":\"$PASSWORD\",\"data\":{\"first_name\":\"CI Admin\",\"last_name\":\"Keeper\"}}" \
  > "$ADMIN_RESPONSE"

NORMAL_TOKEN=$(jq -r '.access_token // empty' "$NORMAL_RESPONSE")
ADMIN_TOKEN=$(jq -r '.access_token // empty' "$ADMIN_RESPONSE")
test -n "$NORMAL_TOKEN"
test -n "$ADMIN_TOKEN"
echo "::add-mask::$NORMAL_TOKEN"
echo "::add-mask::$ADMIN_TOKEN"

psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase1_ci_seed.sql \
  2>&1 | tee "$LOG_DIR/seed.log"

# Confirm the vulnerable baseline before applying the three prepared migrations.
psql "$DB_URL" -v ON_ERROR_STOP=1 <<'SQL' 2>&1 | tee "$LOG_DIR/baseline-security.log"
do $$
begin
  if not has_function_privilege('anon', 'public.featured_badges()', 'execute') then
    raise exception 'Expected baseline anon execution on featured_badges()';
  end if;
  if to_regclass('public.profile_badges_awarded_by_idx') is not null
     or to_regclass('public.profile_badges_badge_id_idx') is not null
     or to_regclass('public.season_awards_profile_id_idx') is not null then
    raise exception 'Phase 1 indexes unexpectedly exist in baseline';
  end if;
end
$$;
SQL

psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase1_ci_snapshot.sql \
  | tr -d '\r' > "$LOG_DIR/snapshot-before.json"

for file in \
  20260719010000_harden_public_rpc_execute_privileges.sql \
  20260719011000_statistics_view_security_invoker.sql \
  20260719012000_add_fk_supporting_indexes.sql; do
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$PHASE1_DIR/$file" \
    2>&1 | tee -a "$LOG_DIR/migrations-up.log"
done

psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase1_security_hardening.sql \
  2>&1 | tee "$LOG_DIR/security-test.log"
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase1_ci_permissions.sql \
  2>&1 | tee "$LOG_DIR/security-definer-permissions.log"

psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase1_ci_snapshot.sql \
  | tr -d '\r' > "$LOG_DIR/snapshot-after.json"
diff -u "$LOG_DIR/snapshot-before.json" "$LOG_DIR/snapshot-after.json" \
  | tee "$LOG_DIR/snapshot-diff.log"

# Direct database role checks.
if psql "$DB_URL" -v ON_ERROR_STOP=1 -c 'set role anon; select * from public.featured_badges();' \
  > "$LOG_DIR/anon-rpc-unexpected.log" 2>&1; then
  echo 'anon unexpectedly executed featured_badges()' >&2
  exit 1
fi
rm -f "$LOG_DIR/anon-rpc-unexpected.log"
psql "$DB_URL" -v ON_ERROR_STOP=1 -c 'set role authenticated; select count(*) from public.featured_badges();' \
  > "$LOG_DIR/authenticated-rpc.log"
psql "$DB_URL" -v ON_ERROR_STOP=1 -c 'set role service_role; select count(*) from public.featured_badges();' \
  > "$LOG_DIR/service-role-rpc.log"

# PostgREST checks with local, ephemeral credentials only.
ANON_RPC_CODE=$(curl --silent --output "$LOG_DIR/anon-rpc-response.json" --write-out '%{http_code}' \
  "$API_URL/rest/v1/rpc/featured_badges" \
  -X POST -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' --data '{}')
case "$ANON_RPC_CODE" in 401|403|404) ;; *) echo "Unexpected anon RPC status: $ANON_RPC_CODE" >&2; exit 1;; esac

for actor in normal admin; do
  if [ "$actor" = normal ]; then token="$NORMAL_TOKEN"; else token="$ADMIN_TOKEN"; fi
  rpc_code=$(curl --silent --output "$LOG_DIR/${actor}-featured-badges.json" --write-out '%{http_code}' \
    "$API_URL/rest/v1/rpc/featured_badges" \
    -X POST -H "apikey: $ANON_KEY" -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' --data '{}')
  test "$rpc_code" = 200

  stats_code=$(curl --silent --output "$LOG_DIR/${actor}-statistics.json" --write-out '%{http_code}' \
    "$API_URL/rest/v1/v_statistics_players?select=period_key,period_label,display_rank,display_order,player_name,is_goalkeeper,matches_played,wins,draws,losses,goals,hdm,clean_sheets&player_name=like.CI%25&order=period_key,display_order,player_name" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $token")
  test "$stats_code" = 200
  jq -S . "$LOG_DIR/${actor}-statistics.json" > "$LOG_DIR/${actor}-statistics.sorted.json"
done

diff -u "$LOG_DIR/normal-statistics.sorted.json" "$LOG_DIR/admin-statistics.sorted.json" \
  | tee "$LOG_DIR/user-admin-statistics-diff.log"

# Validate that the planner selects each new index on representative synthetic data.
NORMAL_ID=$(psql "$DB_URL" -Atc "select id from public.profiles where email='ci-normal@example.invalid'")
BADGE_ID=$(psql "$DB_URL" -Atc 'select id from public.badges order by sort_order, id limit 1')
psql "$DB_URL" -Atc "explain (costs off) select * from public.profile_badges where awarded_by='$NORMAL_ID'::uuid" \
  > "$LOG_DIR/explain-awarded-by.log"
psql "$DB_URL" -Atc "explain (costs off) select * from public.profile_badges where badge_id='$BADGE_ID'::uuid" \
  > "$LOG_DIR/explain-badge-id.log"
psql "$DB_URL" -Atc "explain (costs off) select * from public.season_awards where profile_id='$NORMAL_ID'::uuid" \
  > "$LOG_DIR/explain-season-awards.log"
grep -q 'profile_badges_awarded_by_idx' "$LOG_DIR/explain-awarded-by.log"
grep -q 'profile_badges_badge_id_idx' "$LOG_DIR/explain-badge-id.log"
grep -q 'season_awards_profile_id_idx' "$LOG_DIR/explain-season-awards.log"

# Apply migrations twice to confirm idempotency.
for file in \
  20260719010000_harden_public_rpc_execute_privileges.sql \
  20260719011000_statistics_view_security_invoker.sql \
  20260719012000_add_fk_supporting_indexes.sql; do
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$PHASE1_DIR/$file" \
    2>&1 | tee -a "$LOG_DIR/idempotency.log"
done

# Roll back in reverse order, validate, then reapply and rerun the security suite.
for file in \
  supabase/rollbacks/20260719012000_add_fk_supporting_indexes.down.sql \
  supabase/rollbacks/20260719011000_statistics_view_security_invoker.down.sql \
  supabase/rollbacks/20260719010000_harden_public_rpc_execute_privileges.down.sql; do
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$file" \
    2>&1 | tee -a "$LOG_DIR/rollbacks.log"
done
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase1_ci_rollback_assertions.sql \
  2>&1 | tee "$LOG_DIR/rollback-assertions.log"
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase1_ci_snapshot.sql \
  | tr -d '\r' > "$LOG_DIR/snapshot-after-rollback.json"
diff -u "$LOG_DIR/snapshot-before.json" "$LOG_DIR/snapshot-after-rollback.json" \
  | tee "$LOG_DIR/rollback-snapshot-diff.log"

for file in \
  20260719010000_harden_public_rpc_execute_privileges.sql \
  20260719011000_statistics_view_security_invoker.sql \
  20260719012000_add_fk_supporting_indexes.sql; do
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$PHASE1_DIR/$file" \
    2>&1 | tee -a "$LOG_DIR/reapply.log"
done
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase1_security_hardening.sql \
  2>&1 | tee "$LOG_DIR/security-test-after-reapply.log"
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase1_ci_permissions.sql \
  2>&1 | tee "$LOG_DIR/permissions-after-reapply.log"
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase1_ci_snapshot.sql \
  | tr -d '\r' > "$LOG_DIR/snapshot-after-reapply.json"
diff -u "$LOG_DIR/snapshot-before.json" "$LOG_DIR/snapshot-after-reapply.json" \
  | tee "$LOG_DIR/reapply-snapshot-diff.log"

cat > "$LOG_DIR/verdict.txt" <<'TXT'
PASS: all repository migrations rebuilt locally; phase 1 migrations hardened anonymous access; authenticated/admin/service_role access remained valid; profiles, badges, awards, statistics and ranking snapshots were unchanged; all three indexes were selected; rollback and reapplication succeeded. No remote Supabase project was linked or contacted.
TXT
