#!/bin/bash
# 지휘자 상주 도우미: 우편함 신호 출력과 중계기 순찰 알람을 한 프로세스로 유지한다.
# 사용: conductor-companion.sh <명패handle> <중계기handle> [순찰주기초=300]
set -u

[ $# -ge 2 ] && [ $# -le 3 ] || { echo "usage: conductor-companion.sh <coordinator-handle> <relay-handle> [kicker-interval-sec]"; exit 2; }
COORDINATOR_HANDLE="$1"
RELAY_HANDLE="$2"
KICKER_INTERVAL="${3:-300}"
POLL_INTERVAL="${COMPANION_POLL_INTERVAL_SEC:-30}"
WAKE_TERMINAL_HANDLE="${COMPANION_WAKE_TERMINAL_HANDLE:-}"
ORCA_BIN="${ORCA_BIN:-orca}"
DEADLINE=$(( $(date +%s) + ${WATCH_DEADLINE_MIN:-720} * 60 ))
NEXT_KICKER=$(( $(date +%s) + KICKER_INTERVAL ))
if [ -n "${WATCH_DEADLINE_SEC:-}" ]; then
  DEADLINE=$(( $(date +%s) + WATCH_DEADLINE_SEC ))
fi
SEEN_IDS="|"
SEEN_EVENT_KEYS="|"

emit_signal() {
  local signal_line="$1"
  echo "$signal_line"
  [ -n "$WAKE_TERMINAL_HANDLE" ] || return 0
  if ! "$ORCA_BIN" terminal send --terminal "$WAKE_TERMINAL_HANDLE" --text "[ORCA_INBOX_WAKE] $signal_line 판 상태를 확인하고 중복 카드 없이 처리하세요." --json >/dev/null 2>&1 || \
     ! "$ORCA_BIN" terminal send --terminal "$WAKE_TERMINAL_HANDLE" --enter --json >/dev/null 2>&1; then
    echo "WAKE_FAIL $WAKE_TERMINAL_HANDLE"
  fi
}

# 시작 시 이미 읽지 않은 옛 편지도 베이스라인으로 삼아 재출력하지 않는다.
BASELINE=$("$ORCA_BIN" orchestration check --terminal "$COORDINATOR_HANDLE" --types worker_done,escalation,decision_gate --unread --json 2>/dev/null || true)
while IFS= read -r message_id; do
  [ -n "$message_id" ] && SEEN_IDS="${SEEN_IDS}${message_id}|"
done < <(printf '%s' "$BASELINE" | python3 -c '
import json,sys
try:
    messages=(json.load(sys.stdin).get("result") or {}).get("messages") or []
    for message in messages:
        if message.get("id"): print(message["id"])
except Exception:
    pass
')

"$ORCA_BIN" orchestration check --terminal "$COORDINATOR_HANDLE" --types status --unread --json >/dev/null 2>&1 || true

trap 'exit 0' INT TERM HUP
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  NOW=$(date +%s)
  "$ORCA_BIN" orchestration check --terminal "$COORDINATOR_HANDLE" --types status --unread --json >/dev/null 2>&1 || true
  OUT=$("$ORCA_BIN" orchestration check --terminal "$COORDINATOR_HANDLE" --types worker_done,escalation,decision_gate --unread --json 2>/dev/null || true)
  while IFS=$'\t' read -r message_id message_type sender task_id dispatch_id summary; do
    [ -n "$message_id" ] || continue
    case "$SEEN_IDS" in
      *"|${message_id}|"*) continue;;
    esac
    SEEN_IDS="${SEEN_IDS}${message_id}|"
    if [ "$sender" = "$RELAY_HANDLE" ] && [ "$message_type" = "worker_done" ]; then
      continue
    fi
    event_key=""
    if [ -n "$task_id" ] && [ -n "$dispatch_id" ]; then
      event_key="${message_type}:${task_id}:${dispatch_id}"
      case "$SEEN_EVENT_KEYS" in
        *"|${event_key}|"*) continue;;
      esac
      SEEN_EVENT_KEYS="${SEEN_EVENT_KEYS}${event_key}|"
    fi
    if [ "$message_type" = "worker_done" ] && [ -n "$task_id" ]; then
      # 라우팅 원장 자동 기록 (2026-07-27) — 실패 무시
      "$(dirname "$0")/routing-ledger-append.sh" "worker_done_auto" "${ROUTING_BOARD:-unknown}" "$task_id" \
        "{\"dispatchId\":\"$dispatch_id\",\"sender\":\"$sender\"}" 2>/dev/null || true
    fi
    emit_signal "SIGNAL $message_type $sender $summary"
  done < <(printf '%s' "$OUT" | python3 -c '
import json,re,sys
try:
    messages=(json.load(sys.stdin).get("result") or {}).get("messages") or []
    for m in messages:
        mid=str(m.get("id") or "")
        typ=str(m.get("type") or "unknown")
        sender=str(m.get("from") or m.get("fromHandle") or m.get("from_handle") or "unknown")
        payload=m.get("payload") or {}
        if isinstance(payload,str):
            try: payload=json.loads(payload)
            except json.JSONDecodeError: payload={}
        task_id=str(payload.get("taskId") or payload.get("task_id") or "")
        dispatch_id=str(payload.get("dispatchId") or payload.get("dispatch_id") or "")
        body=str(m.get("body") or m.get("subject") or "")
        body=re.sub(r"\s+", " ", body).strip()[:120]
        if mid: print("\t".join((mid,typ,sender,task_id,dispatch_id,body)))
except Exception:
    pass
')

  if [ "$NOW" -ge "$NEXT_KICKER" ]; then
    if ! "$ORCA_BIN" terminal send --terminal "$RELAY_HANDLE" --text "[순찰 알람] 자기 판의 활성 터미널을 확인하세요. 도구 실행 줄 또는 Context% 증가가 없으면 이전 순찰과 비교해 연속 무진행 횟수를 기록하고, 2회 연속이면 정체로 보고하세요. 명확한 오류·확인창·프리징·프로세스 종료는 첫 발견에 즉시 보고하고, 정상 진행은 기록만 하고 보고하지 마세요." --json >/dev/null 2>&1 || \
       ! "$ORCA_BIN" terminal send --terminal "$RELAY_HANDLE" --enter --json >/dev/null 2>&1; then
      echo "KICKER_FAIL"
    fi
    NEXT_KICKER=$(( NOW + KICKER_INTERVAL ))
  fi
  sleep "$POLL_INTERVAL"
done
echo "DEADLINE_REACHED"
exit 1
