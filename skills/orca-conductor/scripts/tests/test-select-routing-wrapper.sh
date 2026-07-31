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
EXPLORATION_LEDGER_FILE="$QA_DIR/exploration-routing.jsonl"
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
jq -e 'has("exploration") | not' "$QA_DIR/actual.json" >/dev/null
jq -e '.payload.shadow.task_class == "frontend"' "$LEDGER_FILE" >/dev/null
jq -s -e '.[0].developer == .[1].payload.developer' "$QA_DIR/actual.json" "$LEDGER_FILE" >/dev/null
printf 'PASS routing wrapper records shadow scoring without changing stdout\n'

ROUTING_LEDGER_FILE="$EXPLORATION_LEDGER_FILE" "$WRAPPER" \
  --quota-file "$QUOTA_FILE" \
  --rottie-quota-file "$QA_DIR/missing.json" \
  --unavailable-provider anthropic \
  --experiment-key '[explore]:card-2' \
  --task-size light \
  --task-class frontend \
  --risk-assessment-complete \
  --exploration-share-percent 10 > "$QA_DIR/explored.json"

jq -e '.developer.provider == "kimi"' "$QA_DIR/explored.json" >/dev/null
jq -e '.exploration.selected == true and .exploration.base.developer.provider == "zai"' "$QA_DIR/explored.json" >/dev/null
jq -e '.payload.exploration.chosen.developer.provider == "kimi"' "$EXPLORATION_LEDGER_FILE" >/dev/null
jq -e '.payload.shadow.task_class == "frontend"' "$EXPLORATION_LEDGER_FILE" >/dev/null
printf 'PASS routing wrapper applies an explicitly enabled safe exploration slot\n'

ROUTING_LEDGER_FILE="$QA_DIR/risk-routing.jsonl" "$WRAPPER" \
  --quota-file "$QUOTA_FILE" \
  --rottie-quota-file "$QA_DIR/missing.json" \
  --unavailable-provider anthropic \
  --experiment-key '[explore]:card-2' \
  --task-size light \
  --task-class frontend \
  --risk-flag user_visible \
  --risk-assessment-complete \
  --exploration-share-percent 10 > "$QA_DIR/risk-blocked.json"

jq -e '.developer.provider == "zai"' "$QA_DIR/risk-blocked.json" >/dev/null
jq -e '.exploration.selected == false and .exploration.reason == "risk_flagged"' "$QA_DIR/risk-blocked.json" >/dev/null
printf 'PASS routing wrapper blocks exploration for a risk-flagged card\n'

ROUTING_LEDGER_FILE="$QA_DIR/unreviewed-routing.jsonl" "$WRAPPER" \
  --quota-file "$QUOTA_FILE" \
  --rottie-quota-file "$QA_DIR/missing.json" \
  --unavailable-provider anthropic \
  --experiment-key '[explore]:card-2' \
  --task-size light \
  --task-class frontend \
  --exploration-share-percent 10 > "$QA_DIR/unreviewed.json"

jq -e '.developer.provider == "zai"' "$QA_DIR/unreviewed.json" >/dev/null
jq -e '.exploration.selected == false and .exploration.reason == "risk_assessment_required"' "$QA_DIR/unreviewed.json" >/dev/null
printf 'PASS routing wrapper fails closed without a completed risk assessment\n'
