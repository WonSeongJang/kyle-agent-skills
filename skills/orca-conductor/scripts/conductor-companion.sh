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
SEEN_RELAY_ALERTS="|"

emit_signal() {
  local signal_line="$1"
  local wake_instruction="${2:-판 상태를 확인하고 중복 카드 없이 처리하세요.}"
  echo "$signal_line"
  [ -n "$WAKE_TERMINAL_HANDLE" ] || return 0
  if ! "$ORCA_BIN" terminal send --terminal "$WAKE_TERMINAL_HANDLE" --text "[ORCA_INBOX_WAKE] $signal_line $wake_instruction" --json >/dev/null 2>&1 || \
     ! "$ORCA_BIN" terminal send --terminal "$WAKE_TERMINAL_HANDLE" --enter --json >/dev/null 2>&1; then
    echo "WAKE_FAIL $WAKE_TERMINAL_HANDLE"
  fi
}

read_relay_legacy_alerts() {
  local relay_out
  relay_out=$("$ORCA_BIN" terminal read --terminal "$RELAY_HANDLE" --json 2>/dev/null || true)
  printf '%s' "$relay_out" | python3 -c '
import json,re,sys
try:
    data=json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
result=data.get("result") or {}
terminal=result.get("terminal") or {}
tail=terminal.get("tail") or result.get("tail") or result.get("output") or ""
if isinstance(tail,list):
    tail="\n".join(str(part) for part in tail)
else:
    tail=str(tail)
flat=re.sub(r"\s+", " ", tail)
for match in re.finditer(r"ORCA_LEGACY_READ_ONLY_REPORT\s+task=(task_[A-Za-z0-9]+)\s+dispatch=(ctx_[A-Za-z0-9]+)\s+type=([^\s]+)\s+summary=(.{0,240})", flat):
    task_id,dispatch_id,report_type,summary=match.groups()
    key=f"structured:{task_id}:{dispatch_id}:{report_type}"
    line=f"ORCA_LEGACY_READ_ONLY_REPORT task={task_id} dispatch={dispatch_id} type={report_type} summary={summary.strip()}"
    print(key+"\t"+line[:500])
lower=flat.lower()
if "legacy_read_only" in lower and ("effectsapplied=false" in lower or "no effects were applied" in lower):
    task_ids=re.findall(r"task_[A-Za-z0-9]+", flat)
    dispatch_ids=re.findall(r"ctx_[A-Za-z0-9]+", flat)
    event_suffix=(task_ids[-1]+":"+dispatch_ids[-1]) if task_ids and dispatch_ids else "unknown"
    print("raw:"+event_suffix+"\t기존 중계기 출력에서 legacy_read_only 및 effectsApplied=false 확인")
'
}

read_worker_legacy_alerts() {
  local tasks_out task_id dispatch_id worker_handle worker_out
  tasks_out=$("$ORCA_BIN" orchestration task-list --brief --from "$COORDINATOR_HANDLE" --json 2>/dev/null || true)
  while IFS=$'\t' read -r task_id dispatch_id worker_handle; do
    [ -n "$task_id" ] && [ -n "$dispatch_id" ] && [ -n "$worker_handle" ] || continue
    worker_out=$("$ORCA_BIN" terminal read --terminal "$worker_handle" --json 2>/dev/null || true)
    printf '%s' "$worker_out" | TASK_ID="$task_id" DISPATCH_ID="$dispatch_id" WORKER_HANDLE="$worker_handle" python3 -c '
import json,os,re,sys
try:
    data=json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
result=data.get("result") or {}
terminal=result.get("terminal") or {}
tail=terminal.get("tail") or result.get("tail") or result.get("output") or ""
if isinstance(tail,list):
    tail="\n".join(str(part) for part in tail)
flat=re.sub(r"\s+", " ", str(tail)).strip()
lower=flat.lower()
legacy_code="legacy_read_only" in lower and ("effectsapplied=false" in lower or "no effects were applied" in lower)
legacy_text="retained legacy coordinator" in lower and "no effects were applied" in lower
if not (legacy_code or legacy_text):
    raise SystemExit(0)
task_id=os.environ["TASK_ID"]
dispatch_id=os.environ["DISPATCH_ID"]
worker_handle=os.environ["WORKER_HANDLE"]
key=f"worker:{task_id}:{dispatch_id}"
summary=f"WORKER_LEGACY_READ_ONLY task={task_id} dispatch={dispatch_id} worker={worker_handle} summary=작업자 lifecycle 보고가 적용되지 않음"
print(key+"\t"+summary)
'
  done < <(printf '%s' "$tasks_out" | python3 -c '
import json,sys
try:
    tasks=(json.load(sys.stdin).get("result") or {}).get("tasks") or []
except Exception:
    raise SystemExit(0)
for task in tasks:
    if task.get("status") != "dispatched":
        continue
    task_id=str(task.get("id") or "")
    dispatch_id=str(task.get("dispatch_id") or task.get("dispatchId") or "")
    handle=str(task.get("assignee_handle") or task.get("assigneeHandle") or "")
    if task_id and dispatch_id and handle:
        print("\t".join((task_id,dispatch_id,handle)))
')
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

# nohup으로 분리 실행한 companion은 부모 셸이 닫힐 때 오는 HUP을 무시해야 한다.
# INT/TERM은 운영자가 지정 PID만 안전하게 종료할 수 있도록 정상 종료한다.
trap 'exit 0' INT TERM
trap '' HUP
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

  while IFS=$'\t' read -r alert_key alert_summary; do
    [ -n "$alert_key" ] || continue
    case "$SEEN_RELAY_ALERTS" in
      *"|${alert_key}|"*) continue;;
    esac
    SEEN_RELAY_ALERTS="${SEEN_RELAY_ALERTS}${alert_key}|"
    emit_signal "LEGACY_READ_ONLY $RELAY_HANDLE $alert_summary" "구형 중계기의 lifecycle 보고는 적용되지 않았습니다. 같은 명령을 재시도하지 말고 현재 실행의 Run과 pending 보고를 확인하세요. 원래 감독이 권한을 잃었을 때만 현재 감독의 살아 있는 터미널에서 공식 가이드의 run-use --takeover-legacy 절차를 검토하세요."
  done < <({ read_relay_legacy_alerts; read_worker_legacy_alerts; })

  if [ "$NOW" -ge "$NEXT_KICKER" ]; then
    if ! "$ORCA_BIN" terminal send --terminal "$RELAY_HANDLE" --text "[순찰 알람] 자기 판의 활성 터미널을 확인하세요. 도구 실행 줄 또는 Context% 증가가 없으면 이전 순찰과 비교해 연속 무진행 횟수를 기록하고, 2회 연속이면 정체로 보고하세요. 명확한 오류·확인창·프리징·프로세스 종료는 첫 발견에 즉시 보고하고, 정상 진행은 기록만 하고 보고하지 마세요. lifecycle 보고가 [LEGACY READ-ONLY]로 거부되면 재시도하거나 다른 lifecycle 명령을 쓰지 마세요. 작업자 터미널에 terminal send 하지 말고, 반드시 이 중계기 자신의 응답에 ORCA_LEGACY_READ_ONLY_REPORT task=<taskId> dispatch=<dispatchId> type=<보고종류> summary=<한줄요약> 형식의 정확한 한 줄만 직접 출력한 뒤 끝내세요." --json >/dev/null 2>&1 || \
       ! "$ORCA_BIN" terminal send --terminal "$RELAY_HANDLE" --enter --json >/dev/null 2>&1; then
      echo "KICKER_FAIL"
    fi
    NEXT_KICKER=$(( NOW + KICKER_INTERVAL ))
  fi
  sleep "$POLL_INTERVAL"
done
echo "DEADLINE_REACHED"
exit 1
