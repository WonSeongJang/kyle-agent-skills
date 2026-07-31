#!/bin/bash
# routing-ledger-append.sh — 라우팅 원장 자동 append 공용 헬퍼 (2026-07-27 kyle 승인 시스템화)
# 사용: routing-ledger-append.sh <eventType> <board> <taskId> <payload-json>
# 원장 경로 결정: $ROUTING_LEDGER_FILE 우선, 없으면 PWD의 git root/.orca/routing-events/<board>.jsonl
# 경로를 못 정하면 조용히 스킵한다(exit 0) — 자동 기록은 실패해도 본 작업을 막지 않는다.
set -uo pipefail

EVENT_TYPE="${1:-}"; BOARD="${2:-unknown}"; TASK_ID="${3:-unknown}"; PAYLOAD="${4:-}"
[[ -z "$PAYLOAD" ]] && PAYLOAD="{}"
[[ -z "$EVENT_TYPE" ]] && exit 0

LEDGER="${ROUTING_LEDGER_FILE:-}"
if [[ -z "$LEDGER" ]]; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  [[ -z "$ROOT" ]] && exit 0
  SAFE_BOARD=$(echo "$BOARD" | tr -cd 'a-zA-Z0-9._-')
  [[ -z "$SAFE_BOARD" ]] && SAFE_BOARD="ledger"
  LEDGER="$ROOT/.orca/routing-events/${SAFE_BOARD}.jsonl"
fi

mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || exit 0

EVENT_TYPE="$EVENT_TYPE" BOARD="$BOARD" TASK_ID="$TASK_ID" PAYLOAD="$PAYLOAD" LEDGER="$LEDGER" python3 - <<'PY' || exit 0
import json, os, uuid, datetime
payload_raw = os.environ.get("PAYLOAD", "{}")
try:
    payload = json.loads(payload_raw)
except Exception:
    payload = {"raw": payload_raw[:2000]}
event = {
    "schemaVersion": 1,
    "eventId": str(uuid.uuid4()),
    "eventType": os.environ["EVENT_TYPE"],
    "occurredAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "board": os.environ.get("BOARD", "unknown"),
    "repoId": (lambda L: os.path.basename(L.split("/.orca/")[0]) if "/.orca/" in L else "unknown")(os.environ["LEDGER"]),
    "taskId": os.environ.get("TASK_ID", "unknown"),
    "runId": "auto",
    "roundId": "auto",
    "payload": payload,
}
with open(os.environ["LEDGER"], "a") as f:
    f.write(json.dumps(event, ensure_ascii=False) + "\n")
PY
exit 0
