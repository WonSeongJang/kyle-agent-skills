#!/usr/bin/env bash
set -euo pipefail

SOURCE_FILE="${1:-$(cd "$(dirname "$0")/../references" && pwd)/source-index.md}"

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "SOURCE FILE NOT FOUND: $SOURCE_FILE" >&2
  exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep(rg) is required." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 1
fi

URLS_RAW="$(rg -o --no-filename 'https?://[^) >"]+' "$SOURCE_FILE" | sort -u || true)"

if [[ -z "$URLS_RAW" ]]; then
  echo "No URLs found in $SOURCE_FILE"
  exit 0
fi

URL_COUNT="$(printf '%s\n' "$URLS_RAW" | sed '/^$/d' | wc -l | tr -d ' ')"

echo "Checking ${URL_COUNT} URLs from: $SOURCE_FILE"
echo

failed=0

while IFS= read -r url; do
  [[ -z "$url" ]] && continue
  status="$(curl -L -sS -o /dev/null -w '%{http_code}' "$url" || true)"
  if [[ "$status" =~ ^2|3 ]]; then
    printf '[OK]   %s -> %s\n' "$status" "$url"
  else
    printf '[FAIL] %s -> %s\n' "${status:-000}" "$url"
    failed=1
  fi
done <<< "$URLS_RAW"

echo
if [[ "$failed" -eq 0 ]]; then
  echo "All source links look reachable."
else
  echo "Some source links failed. Re-check URLs and update source-index.md."
fi

exit "$failed"
