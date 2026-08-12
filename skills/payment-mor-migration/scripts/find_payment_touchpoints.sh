#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

if [[ ! -d "$ROOT" ]]; then
  echo "Root path does not exist: $ROOT" >&2
  exit 1
fi

if command -v rg >/dev/null 2>&1; then
  SEARCH_TOOL="rg"
else
  SEARCH_TOOL="grep"
fi

echo "== Payment touchpoint scan =="
echo "Root: $ROOT"
echo

PATTERN='payment|checkout|webhook|payapp|payup|polar|lemonsqueezy|stripe|credit_ledger|payment_orders'

if [[ "$SEARCH_TOOL" == "rg" ]]; then
  rg -n --hidden --glob '!**/.git/**' --glob '!**/node_modules/**' -S "$PATTERN" \
    "$ROOT/api" "$ROOT/src" "$ROOT/supabase" "$ROOT/docs" 2>/dev/null || true
else
  grep -RInE "$PATTERN" "$ROOT/api" "$ROOT/src" "$ROOT/supabase" "$ROOT/docs" 2>/dev/null || true
fi
