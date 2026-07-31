#!/bin/bash
set -euo pipefail
trap 'printf "FAIL routing wrapper QA at line %s\n" "$LINENO" >&2' ERR

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
WRAPPER="$SKILL_DIR/scripts/select-routing-pair.sh"

[ -x "$WRAPPER" ]

QA_DIR=$(mktemp -d)
QUOTA_FILE="$QA_DIR/quota.json"
LEDGER_FILE="$QA_DIR/routing.jsonl"
cat > "$QUOTA_FILE" <<'JSON'
{
  "generatedAt": 1784877896945,
  "reports": [
    {"provider": "kimi", "quota": {"weeklyPercent": 20, "weeklyResetAt": 1785121301935}},
    {"provider": "zai", "quota": {"weeklyPercent": 20, "weeklyResetAt": 1785121301935}},
    {"provider": "openai", "quota": {"weeklyPercent": 20, "weeklyResetAt": 1785121301935}}
  ]
}
JSON

ROUTING_LEDGER_FILE="$LEDGER_FILE" "$WRAPPER" \
  --quota-file "$QUOTA_FILE" \
  --rottie-quota-file "$QA_DIR/missing.json" \
  --unavailable-provider anthropic \
  --experiment-key '[shadow]:frontend-card' \
  --task-class frontend > "$QA_DIR/actual.json"

jq -e 'has("shadow") | not' "$QA_DIR/actual.json" >/dev/null
jq -e '.payload.shadow.task_class == "frontend"' "$LEDGER_FILE" >/dev/null
jq -s -e '.[0].developer == .[1].payload.developer' "$QA_DIR/actual.json" "$LEDGER_FILE" >/dev/null
printf 'PASS routing wrapper records shadow scoring without changing stdout\n'
