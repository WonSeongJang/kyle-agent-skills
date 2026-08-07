#!/bin/bash
# 중계기(relay)가 남긴 순찰 일기를 읽어, 감독 정체를 슈퍼 우편함에 올리는 전용 프로세스다.
#
# Why: 중계기는 화면을 보고 정체를 판정하지만 규칙상 상위 보고가 금지돼 있다. 그래서
# 2026-08-07에 판 receipt-hardening-1의 감독이 1시간 30분 동안 얼어 있었는데도, 중계기는
# 그 사실을 18번 일기에만 적고 아무에게도 알리지 못했다. 판단은 이미 일기에 있으므로
# 새로 판단할 AI가 필요한 게 아니라, 그 줄을 읽어 편지 한 통을 보내는 멍청한 프로세스가
# 필요하다. companion이 우편함을 보고 감독을 깨우는 것의 거울상이다.
#
# 이 스크립트는 판정하지 않는다. 중계기가 쓴 숫자만 읽는다.
set -u

usage() {
  echo "usage: stall-reporter.sh --project <project> --board <board> --relay-log <path> --super-run <run_id> [--project-run <run_id>] [--relay-role <role>] [--thresholds 3,12,36] [--poll-sec 60] [--relay-silence-sec 900] [--once]" >&2
  exit 2
}

PROJECT=""
BOARD=""
RELAY_LOG=""
SUPER_RUN_ID=""
PROJECT_RUN_ID=""
RELAY_ROLE="relay"
THRESHOLDS="3,12,36"
POLL_SEC=60
RELAY_SILENCE_SEC=900
ONCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project) [ $# -ge 2 ] || usage; PROJECT="$2"; shift 2 ;;
    --board) [ $# -ge 2 ] || usage; BOARD="$2"; shift 2 ;;
    --relay-log) [ $# -ge 2 ] || usage; RELAY_LOG="$2"; shift 2 ;;
    --super-run) [ $# -ge 2 ] || usage; SUPER_RUN_ID="$2"; shift 2 ;;
    --project-run) [ $# -ge 2 ] || usage; PROJECT_RUN_ID="$2"; shift 2 ;;
    --relay-role) [ $# -ge 2 ] || usage; RELAY_ROLE="$2"; shift 2 ;;
    --thresholds) [ $# -ge 2 ] || usage; THRESHOLDS="$2"; shift 2 ;;
    --poll-sec) [ $# -ge 2 ] || usage; POLL_SEC="$2"; shift 2 ;;
    --relay-silence-sec) [ $# -ge 2 ] || usage; RELAY_SILENCE_SEC="$2"; shift 2 ;;
    --once) ONCE=1; shift ;;
    *) echo "UNKNOWN_FLAG $1" >&2; usage ;;
  esac
done

[ -n "$PROJECT" ] || { echo "REQUIRED project" >&2; usage; }
[ -n "$BOARD" ] || { echo "REQUIRED board" >&2; usage; }
[ -n "$RELAY_LOG" ] || { echo "REQUIRED relay-log" >&2; usage; }
[ -n "$SUPER_RUN_ID" ] || { echo "REQUIRED super-run" >&2; usage; }

# orca CLI 위치 해석은 companion과 같은 규칙을 따른다.
REQUESTED_ORCA_BIN="${ORCA_BIN:-}"
if [ -n "$REQUESTED_ORCA_BIN" ] && [ -x "$REQUESTED_ORCA_BIN" ]; then
  ORCA_BIN="$REQUESTED_ORCA_BIN"
elif [ -n "$REQUESTED_ORCA_BIN" ]; then
  ORCA_BIN=$(command -v "$REQUESTED_ORCA_BIN" 2>/dev/null || true)
elif command -v orca >/dev/null 2>&1; then
  ORCA_BIN=$(command -v orca)
elif [ -x /usr/local/bin/orca ]; then
  ORCA_BIN=/usr/local/bin/orca
elif [ -x /opt/homebrew/bin/orca ]; then
  ORCA_BIN=/opt/homebrew/bin/orca
else
  ORCA_BIN=""
fi
if [ -z "$ORCA_BIN" ] || [ ! -x "$ORCA_BIN" ]; then
  echo "ORCA_BIN_UNAVAILABLE requested=${REQUESTED_ORCA_BIN:-auto}" >&2
  exit 3
fi

STATE_DIR="${STALL_REPORTER_STATE_DIR:-$HOME/.cache/rottie/stall-reporter}"
mkdir -p "$STATE_DIR" 2>/dev/null || { echo "STATE_DIR_UNWRITABLE $STATE_DIR" >&2; exit 3; }
SAFE_BOARD=$(printf '%s' "$BOARD" | tr -c 'A-Za-z0-9._-' '_')
STATE_FILE="$STATE_DIR/$SAFE_BOARD.state"

# 상태: 이번 정체 사건에서 이미 알린 최고 임계값, 그리고 중계기 침묵 알림 여부.
ALERTED_LEVEL=0
RELAY_SILENT_ALERTED=0
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE" 2>/dev/null || true
fi

save_state() {
  printf 'ALERTED_LEVEL=%s\nRELAY_SILENT_ALERTED=%s\n' "$ALERTED_LEVEL" "$RELAY_SILENT_ALERTED" > "$STATE_FILE"
}

log() {
  printf '%s stall-reporter board=%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$BOARD" "$*" >&2
}

# 중계기 handle을 그때그때 다시 찾는다. 못 찾으면 --from 없이 보낸다.
# handle은 임시 라우팅 값이므로 캐시하지 않는다.
resolve_relay_handle() {
  local output handle
  [ -n "$PROJECT_RUN_ID" ] || { printf ''; return 0; }
  output=$( "$ORCA_BIN" roster resolve --project "$PROJECT" --board "$BOARD" --role "$RELAY_ROLE" --run "$PROJECT_RUN_ID" --json 2>/dev/null ) || { printf ''; return 0; }
  handle=$(printf '%s' "$output" | python3 -c '
import json,sys
try:
    result=(json.load(sys.stdin).get("result") or {})
except Exception:
    raise SystemExit(0)
print(result.get("currentHandle") or result.get("current_handle") or "")
' 2>/dev/null)
  printf '%s' "$handle"
}

send_alert() {
  local subject="$1" body="$2" payload="$3" from_handle
  from_handle=$(resolve_relay_handle)
  if [ -n "$from_handle" ]; then
    "$ORCA_BIN" orchestration send --run "$SUPER_RUN_ID" --from "$from_handle" \
      --type escalation --priority high --subject "$subject" --body "$body" --payload "$payload" --json >/dev/null 2>&1
  else
    "$ORCA_BIN" orchestration send --run "$SUPER_RUN_ID" \
      --type escalation --priority high --subject "$subject" --body "$body" --payload "$payload" --json >/dev/null 2>&1
  fi
}

file_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# 중계기 일기의 마지막 줄에서 숫자만 뽑는다. 여기서 새로 판정하지 않는다.
parse_last_line() {
  LAST_LINE=$(tail -n 1 "$RELAY_LOG" 2>/dev/null || printf '')
  NO_PROGRESS=$(printf '%s' "$LAST_LINE" | sed -n 's/.*consecutive_no_progress=\([0-9][0-9]*\).*/\1/p' | head -1)
  JUDGEMENT=$(printf '%s' "$LAST_LINE" | sed -n 's/.*judgement=\([A-Za-z_]*\).*/\1/p' | head -1)
  BANNER=$(printf '%s' "$LAST_LINE" | sed -n 's/.*banner=\([A-Za-z_-]*\).*/\1/p' | head -1)
  [ -n "$NO_PROGRESS" ] || NO_PROGRESS=0
  [ -n "$JUDGEMENT" ] || JUDGEMENT=unknown
  [ -n "$BANNER" ] || BANNER=unknown
}

# 이번 정체 사건에서 알려야 할 임계값을 고른다. 이미 알린 것보다 큰 것만 고른다.
next_threshold_reached() {
  local n="$1" t highest=0
  local old_ifs="$IFS"
  IFS=','
  for t in $THRESHOLDS; do
    case "$t" in ''|*[!0-9]*) continue ;; esac
    if [ "$n" -ge "$t" ] && [ "$t" -gt "$highest" ]; then highest="$t"; fi
  done
  IFS="$old_ifs"
  printf '%s' "$highest"
}

MIN_THRESHOLD=$(printf '%s' "$THRESHOLDS" | cut -d, -f1)
case "$MIN_THRESHOLD" in ''|*[!0-9]*) MIN_THRESHOLD=3 ;; esac

log "start relay_log=$RELAY_LOG super_run=$SUPER_RUN_ID thresholds=$THRESHOLDS poll=${POLL_SEC}s"

while :; do
  NOW=$(date +%s)

  if [ ! -f "$RELAY_LOG" ]; then
    log "relay_log_missing"
  else
    MTIME=$(file_mtime "$RELAY_LOG")
    SILENT_FOR=$(( NOW - MTIME ))

    # 사건 1. 중계기 자체가 멈춘 경우. 감시자가 죽으면 정체도 못 잡는다.
    if [ "$SILENT_FOR" -ge "$RELAY_SILENCE_SEC" ]; then
      if [ "$RELAY_SILENT_ALERTED" -eq 0 ]; then
        send_alert "[정체신고] 중계기 순찰이 멈췄다 — $BOARD" \
"중계기가 남기는 순찰 일기가 ${SILENT_FOR}초 동안 갱신되지 않았다. 감시자가 멈췄으므로 이 판의 정체를 아무도 볼 수 없는 상태다.

판: $PROJECT / $BOARD
일기 파일: $RELAY_LOG
마지막 기록 이후: ${SILENT_FOR}초

이 알림은 이 사건에 대해 한 번만 보낸다. 중계기가 다시 기록을 시작하면 자동으로 재장전된다." \
"{\"event\":\"relay_patrol_silent\",\"project\":\"$PROJECT\",\"board\":\"$BOARD\",\"silentForSec\":$SILENT_FOR,\"relayLog\":\"$RELAY_LOG\"}"
        RELAY_SILENT_ALERTED=1
        save_state
        log "alert relay_patrol_silent silent_for=${SILENT_FOR}s"
      fi
    else
      if [ "$RELAY_SILENT_ALERTED" -ne 0 ]; then
        RELAY_SILENT_ALERTED=0
        save_state
        log "rearm relay_patrol_recovered"
      fi
    fi

    # 사건 2. 감독 정체. 판정은 중계기가 이미 했고 여기서는 숫자만 본다.
    parse_last_line
    if [ "$NO_PROGRESS" -lt "$MIN_THRESHOLD" ]; then
      if [ "$ALERTED_LEVEL" -ne 0 ]; then
        ALERTED_LEVEL=0
        save_state
        log "rearm supervisor_progress_resumed no_progress=$NO_PROGRESS"
      fi
    else
      LEVEL=$(next_threshold_reached "$NO_PROGRESS")
      if [ "$LEVEL" -gt "$ALERTED_LEVEL" ]; then
        send_alert "[정체신고] 감독 무진행 ${NO_PROGRESS}회 연속 — $BOARD" \
"중계기가 이 판의 감독을 ${NO_PROGRESS}회 연속 무진행으로 판정했다. 중계기는 상위 보고 권한이 없으므로 이 알림은 별도 프로세스가 대신 보낸다.

판: $PROJECT / $BOARD
중계기 판정: $JUDGEMENT
화면 오류 배너: $BANNER
연속 무진행 횟수: $NO_PROGRESS
일기 파일: $RELAY_LOG

중계기가 쓴 마지막 줄 원문:
$LAST_LINE

판정 순서는 오류 배너 먼저, 그다음 판 지문, 마지막이 정상 장고다. 배너가 none이면 화면을 직접 확인하라.
같은 사건에 대해서는 임계값($THRESHOLDS)을 넘을 때만 다시 보낸다. 감독이 다시 움직이면 자동으로 재장전된다." \
"{\"event\":\"supervisor_stall\",\"project\":\"$PROJECT\",\"board\":\"$BOARD\",\"consecutiveNoProgress\":$NO_PROGRESS,\"judgement\":\"$JUDGEMENT\",\"banner\":\"$BANNER\",\"thresholdLevel\":$LEVEL,\"relayLog\":\"$RELAY_LOG\"}"
        ALERTED_LEVEL="$LEVEL"
        save_state
        log "alert supervisor_stall no_progress=$NO_PROGRESS level=$LEVEL judgement=$JUDGEMENT"
      fi
    fi
  fi

  [ "$ONCE" -eq 1 ] && break
  sleep "$POLL_SEC"
done
