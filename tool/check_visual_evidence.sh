#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"

api="https://api.github.com/repos/${GITHUB_REPOSITORY}"
files="$(mktemp)"
trap 'rm -f "$files"' EXIT
page=1

while :; do
  response="$(curl -LfsS \
    -H 'Accept: application/vnd.github+json' \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "${api}/pulls/${PR_NUMBER}/files?per_page=100&page=${page}")"
  count="$(jq 'length' <<<"$response")"
  jq -r '.[].filename' <<<"$response" >> "$files"
  if [ "$count" -lt 100 ]; then
    break
  fi
  page=$((page + 1))
done

visual_change=false
while IFS= read -r path; do
  case "$path" in
    lib/*/presentation/*|lib/core/theme/*|lib/core/widgets/*|assets/*|web/*)
      visual_change=true
      echo "Visual-impact file: $path"
      ;;
  esac
done < "$files"

if [ "$visual_change" != true ]; then
  echo 'No visual-impact files detected; before/after evidence is not required.'
  exit 0
fi

body="$(curl -LfsS \
  -H 'Accept: application/vnd.github+json' \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  "${api}/pulls/${PR_NUMBER}" | jq -r '.body // ""')"

before="$(printf '%s\n' "$body" | sed -nE 's/^[[:space:]]*-[[:space:]]*Avant:[[:space:]]*(https?:\/\/[^[:space:]]+).*$/\1/p' | head -n 1)"
after="$(printf '%s\n' "$body" | sed -nE 's/^[[:space:]]*-[[:space:]]*Après:[[:space:]]*(https?:\/\/[^[:space:]]+).*$/\1/p' | head -n 1)"

if [ -z "$before" ] || [ -z "$after" ]; then
  echo '::error::Cette PR touche l’interface. Ajoutez deux liens de captures dans la description, exactement sous la forme « - Avant: https://… » et « - Après: https://… ».'
  exit 1
fi

echo "Before evidence: $before"
echo "After evidence: $after"
echo 'Before/after visual evidence detected.'
