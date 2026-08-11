#!/bin/bash
# routing-ledger-append.sh — 라우팅 원장 자동 append 공용 헬퍼 (2026-07-27 kyle 승인 시스템화)
# 사용: routing-ledger-append.sh <eventType> <board> <taskId> [payload-json] \
#     [--run-id <id>] [--round-id <id>] [--dispatch-id <id>] [--quarantine-reason <txt>]
# (2026-08-11 I-COMPANION-MAIN) companion worker_done 원장이 권위 ID(run/round/dispatch)를
# 실제 값으로 기록하도록 선택 인자를 추가했다. 구 호출자(인자 없음)는 종전처럼 runId/roundId
# 가 "auto" 로, dispatchId 필드는 없는 채로 쓰인다 — 하위 호환이다. --quarantine-reason 이
# 붙은 이벤트는 본 원장에 쓰지 않는다(companion worker_done 격리 계약).
# 원장 경로 결정: $ROUTING_LEDGER_FILE 우선, 없으면 PWD의 git root/.orca/routing-events/<board>.jsonl
# 경로를 못 정하면 조용히 스킵한다(exit 0) — 자동 기록은 실패해도 본 작업을 막지 않는다.
set -uo pipefail

EVENT_TYPE="${1:-}"; BOARD="${2:-unknown}"; TASK_ID="${3:-unknown}"; PAYLOAD="${4:-}"
RUN_ID=""; ROUND_ID=""; DISPATCH_ID=""; QUARANTINE_REASON=""
shift 4 2>/dev/null || shift "$#" 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)      RUN_ID="${2:-}";      shift 2 ;;
    --round-id)    ROUND_ID="${2:-}";    shift 2 ;;
    --dispatch-id) DISPATCH_ID="${2:-}"; shift 2 ;;
    --quarantine-reason) QUARANTINE_REASON="${2:-}"; shift 2 ;;
    --quarantine-reason=*) QUARANTINE_REASON="${1#*=}"; shift ;;
    --) shift; [[ $# -gt 0 ]] && PAYLOAD="$1"; break ;;
    *) PAYLOAD="$1"; shift ;;
  esac
done
[[ -z "$PAYLOAD" ]] && PAYLOAD="{}"
[[ -z "$EVENT_TYPE" ]] && exit 0
# 격리 사유가 붙은 이벤트는 본 원장에 쓰지 않는다(companion worker_done 격리 계약).
[[ -n "$QUARANTINE_REASON" ]] && exit 0

LEDGER="${ROUTING_LEDGER_FILE:-}"
if [[ -z "$LEDGER" ]]; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  [[ -z "$ROOT" ]] && exit 0
  SAFE_BOARD=$(echo "$BOARD" | tr -cd 'a-zA-Z0-9._-')
  [[ -z "$SAFE_BOARD" ]] && SAFE_BOARD="ledger"
  LEDGER="$ROOT/.orca/routing-events/${SAFE_BOARD}.jsonl"
fi

mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || exit 0

EVENT_TYPE="$EVENT_TYPE" BOARD="$BOARD" TASK_ID="$TASK_ID" PAYLOAD="$PAYLOAD" LEDGER="$LEDGER" \
RUN_ID="$RUN_ID" ROUND_ID="$ROUND_ID" DISPATCH_ID="$DISPATCH_ID" python3 - <<'PY' || exit 0
import json, os, uuid, datetime
payload_raw = os.environ.get("PAYLOAD", "{}")
try:
    payload = json.loads(payload_raw)
except Exception:
    payload = {"raw": payload_raw[:2000]}
run_id = os.environ.get("RUN_ID") or "auto"
round_id = os.environ.get("ROUND_ID") or "auto"
dispatch_id = os.environ.get("DISPATCH_ID") or ""
event = {
    "schemaVersion": 1,
    "eventId": str(uuid.uuid4()),
    "eventType": os.environ["EVENT_TYPE"],
    "occurredAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "board": os.environ.get("BOARD", "unknown"),
    "repoId": (lambda L: os.path.basename(L.split("/.orca/")[0]) if "/.orca/" in L else "unknown")(os.environ["LEDGER"]),
    "taskId": os.environ.get("TASK_ID", "unknown"),
    "runId": run_id,
    "roundId": round_id,
    "payload": payload,
}
# dispatch-id 가 주어진 경우에만 필드를 넣는다(구 이벤트 스키마를 바꾸지 않는다).
if dispatch_id:
    event["dispatchId"] = dispatch_id
with open(os.environ["LEDGER"], "a") as f:
    f.write(json.dumps(event, ensure_ascii=False) + "\n")
PY
exit 0
