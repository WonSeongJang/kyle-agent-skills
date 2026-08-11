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
  echo "usage: stall-reporter.sh --project <project> --board <board> --relay-log <path> --super-run <run_id> [--project-run <run_id>] [--relay-role <role>] [--thresholds 3,12,36] [--poll-sec 60] [--relay-silence-sec 900] [--board-idle-sec 300] [--once]" >&2
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
    # B8 시험 호환: --board-idle-sec(B7 인자)를 값만 저장한다. main엔 사건3~5가 없어 쓰는 곳은 없지만,
    # 이 인자를 모르면 UNKNOWN_FLAG 로 사건6 경로가 아예 실행되지 않는다(코디네이터 결정 A).
    --board-idle-sec) [ $# -ge 2 ] || usage; BOARD_IDLE_SEC="$2"; shift 2 ;;
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

# B8(2026-08-10): 감독 깨우기(supervisor-waker.sh)의 심박을 읽어 그것이 끊기면 신고한다.
#
# Why: 깨우기는 감독을 주기적으로 깨우는 유일한 장치다. 그것이 죽으면 감독은 편지가 올 때만
# 깨어나고, 편지가 안 오면 영원히 안 깨어난다 — 2026-08-09 열한 시간 정지가 그 상태였다.
# 그러면 깨우기는 누가 보는가. **새 프로세스를 만들지 않는다.** 깨우기가 매 주기 심박을 적고,
# 이미 판을 보고 있는 이 신고기가 그 줄이 끊긴 것을 본다. 감시는 여기서 한 겹으로 끝난다.
#
# 심박 경로는 --relay-log 와 --board 에서 **유도**한다(waker-heartbeat-path.sh 한 곳에서 계산).
# 인자로 받지 않는 이유: 안 주면 안 켜지는 방어는 방어가 아니기 때문이다. 끄는 방법이 없다.
# shellcheck source=./waker-heartbeat-path.sh
. "$(cd "$(dirname "$0")" && pwd)/waker-heartbeat-path.sh"
WAKER_HEARTBEAT_LOG=$(waker_heartbeat_path "$RELAY_LOG" "$BOARD") || {
  echo "HEARTBEAT_PATH_UNRESOLVED relay_log=$RELAY_LOG board=$BOARD" >&2
  exit 3
}
# 심박이 끊겼다고 볼 시간. 깨우기가 자기 주기(interval=)를 심박 줄에 적어 주므로 그 3배로
# 잡는다 — 임계값을 여기 상수로 또 적으면 주기를 바꿀 때 한쪽만 바뀌어 오보가 난다.
# 심박 파일이 아예 없으면(깨우기가 한 번도 안 돌았으면) 주기를 알 수 없으므로 기본 주기
# 1800초의 3배인 5400초를 쓴다. 신고기가 갓 떴을 때 바로 외치지 않도록 이 경우의 기준 시각은
# 심박 시각이 아니라 신고기 자신의 기동 시각이다.
WAKER_SILENCE_FACTOR=3
WAKER_DEFAULT_INTERVAL=1800
WAKER_SILENCE_OVERRIDE="${STALL_REPORTER_WAKER_SILENCE_SEC:-}"
case "$WAKER_SILENCE_OVERRIDE" in *[!0-9]*) WAKER_SILENCE_OVERRIDE="" ;; esac

STATE_DIR="${STALL_REPORTER_STATE_DIR:-$HOME/.cache/rottie/stall-reporter}"
mkdir -p "$STATE_DIR" 2>/dev/null || { echo "STATE_DIR_UNWRITABLE $STATE_DIR" >&2; exit 3; }
SAFE_BOARD=$(printf '%s' "$BOARD" | tr -c 'A-Za-z0-9._-' '_')
STATE_FILE="$STATE_DIR/$SAFE_BOARD.state"

# 상태: 이번 정체 사건에서 이미 알린 최고 임계값, 그리고 중계기 침묵 알림 여부.
ALERTED_LEVEL=0
RELAY_SILENT_ALERTED=0
# B8: 감독 깨우기 심박 침묵을 이 사건에서 이미 알렸는지.
WAKER_SILENT_ALERTED=0
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE" 2>/dev/null || true
fi

save_state() {
  printf 'ALERTED_LEVEL=%s\nRELAY_SILENT_ALERTED=%s\nWAKER_SILENT_ALERTED=%s\n' \
    "$ALERTED_LEVEL" "$RELAY_SILENT_ALERTED" "${WAKER_SILENT_ALERTED:-0}" > "$STATE_FILE"
}

# B8: 감독 깨우기가 살아 있는지. 심박 파일의 마지막 갱신 시각만 본다 — 이 파일에는 깨우기만 쓴다.
#
# 두 경우를 구분해서 내보낸다. 감독이 해야 할 행동이 다르기 때문이다.
#   stopped - 심박이 있다가 끊겼다     -> 죽은 깨우기를 다시 띄워라
#   absent  - 심박이 한 번도 없었다    -> 깨우기를 아직 안 띄웠다(2026-08-09 열한 시간 정지의 상태)
# 둘을 "깨우기 이상" 하나로 접으면 "아직 안 만들었다"가 "죽었다"로 읽혀 엉뚱한 곳을 보게 된다.
WAKER_STATE=absent
WAKER_SILENT_FOR=0
WAKER_LIMIT=0
check_waker_heartbeat() {
  local interval=""
  if [ -f "$WAKER_HEARTBEAT_LOG" ]; then
    WAKER_STATE=stopped
    WAKER_SILENT_FOR=$(( NOW - $(file_mtime "$WAKER_HEARTBEAT_LOG") ))
    # 주기는 깨우기가 심박 줄에 직접 적는다. 여기 상수로 베끼지 않는다.
    interval=$(grep 'SUPERVISOR_WAKER_ALIVE' "$WAKER_HEARTBEAT_LOG" 2>/dev/null | tail -n 1 \
      | sed -n 's/.*interval=\([0-9][0-9]*\).*/\1/p' | head -1)
  else
    # 기준 시각이 심박이 아니라 내 기동 시각이다. 갓 뜬 신고기가 즉시 외치지 않게 한다.
    WAKER_STATE=absent
    WAKER_SILENT_FOR=$(( NOW - REPORTER_START ))
  fi
  case "$interval" in ''|*[!0-9]*) interval="$WAKER_DEFAULT_INTERVAL" ;; esac
  [ "$interval" -ge 1 ] || interval="$WAKER_DEFAULT_INTERVAL"
  WAKER_LIMIT=$(( interval * WAKER_SILENCE_FACTOR ))
  [ -n "$WAKER_SILENCE_OVERRIDE" ] && WAKER_LIMIT="$WAKER_SILENCE_OVERRIDE"
  [ "$WAKER_SILENT_FOR" -ge 0 ] || WAKER_SILENT_FOR=0
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
  # 중계기는 감독 화면만 본다. 작업자가 도는 동안 감독이 조용한 것은 정상이므로,
  # 중계기가 active_dispatched를 써 주면 그 경우의 임계값을 높인다(2026-08-07 오탐 1건).
  ACTIVE_DISPATCHED=$(printf '%s' "$LAST_LINE" | sed -n 's/.*active_dispatched=\([0-9][0-9]*\).*/\1/p' | head -1)
  [ -n "$NO_PROGRESS" ] || NO_PROGRESS=0
  [ -n "$JUDGEMENT" ] || JUDGEMENT=unknown
  [ -n "$BANNER" ] || BANNER=unknown
  [ -n "$ACTIVE_DISPATCHED" ] || ACTIVE_DISPATCHED=""
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

# 컴퓨터가 절전에 들어가면 중계기도 이 스크립트도 함께 얼었다가 함께 깨어난다.
# 그때 일기 파일만 보면 "감시자가 죽었다"와 구분되지 않는다(2026-08-07 오탐 3건 — 세 판이
# 동시에 약 28분 침묵했고 실제 원인은 맥 절전이었다). 그래서 이 스크립트 자신의 루프가
# 얼었는지를 함께 본다. 내 잠이 예정보다 훨씬 길었다면 시스템이 멈춘 것이다.
LAST_TICK=$(date +%s)
# B8: 심박 파일이 아예 없을 때 "얼마나 없었는가"의 기준 시각. 신고기 자신의 기동 시각이다.
REPORTER_START="$LAST_TICK"
FREEZE_FACTOR=3
# 갓 뜬 신고기는 비교할 과거 시각이 없어서 절전을 감지하지 못한다. 그래서 맥이
# 자는 동안 낡은 일기를 보고 "감시자 사망"으로 오보한다(2026-08-08 실사고 — kyle이
# 노트북을 들고 나가 5시간 잠들었는데 새로 띄운 신고기가 중계기 고장으로 신고했다).
# 시작 직후에는 일기가 이미 낡아 있어도 몇 주기 지켜본다. 중계기가 깨어나 다시 쓰면
# 그것으로 끝이고, 그때까지도 멎어 있으면 그때 진짜로 신고한다.
STARTUP_GRACE_CYCLES="${STALL_REPORTER_STARTUP_CYCLES:-4}"
GRACE_UNTIL=$(( LAST_TICK + POLL_SEC * STARTUP_GRACE_CYCLES ))
log "startup_grace 적용 ${POLL_SEC}s x ${STARTUP_GRACE_CYCLES}주기 동안 침묵 판정 보류"

while :; do
  NOW=$(date +%s)
  DRIFT=$(( NOW - LAST_TICK ))
  if [ "$DRIFT" -gt $(( POLL_SEC * FREEZE_FACTOR )) ]; then
    # 중계기가 다시 순찰을 쌓을 시간을 준 뒤에야 침묵을 다시 판정한다.
    # 유예는 멈춘 길이에 비례해야 한다. 맥이 3시간 자면 일기도 3시간 낡는데,
    # 고정 4분만 봐주면 깨어나자마자 "감시자 사망"으로 오보한다(2026-08-08 실사고 — 4회 연속 오보).
    GRACE_SPAN=$(( DRIFT + POLL_SEC * 4 ))
    [ "$GRACE_SPAN" -lt $(( POLL_SEC * 4 )) ] && GRACE_SPAN=$(( POLL_SEC * 4 ))
    GRACE_UNTIL=$(( NOW + GRACE_SPAN ))
    if [ "$RELAY_SILENT_ALERTED" -ne 0 ]; then
      RELAY_SILENT_ALERTED=0
      save_state
    fi
    log "system_pause_detected drift=${DRIFT}s expected=${POLL_SEC}s grace_until=$GRACE_UNTIL (절전·정지 추정, 침묵 판정 보류)"
  fi
  LAST_TICK="$NOW"

  if [ ! -f "$RELAY_LOG" ]; then
    log "relay_log_missing"
  else
    MTIME=$(file_mtime "$RELAY_LOG")
    SILENT_FOR=$(( NOW - MTIME ))

    # 사건 1. 중계기 자체가 멈춘 경우. 감시자가 죽으면 정체도 못 잡는다.
    if [ "$SILENT_FOR" -ge "$RELAY_SILENCE_SEC" ] && [ "$NOW" -ge "$GRACE_UNTIL" ]; then
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
    # 작업자가 실제로 돌고 있으면 감독의 침묵은 정상 대기다. 첫 임계값을 건너뛰고
    # 더 높은 단계에서만 알린다. 중계기가 숫자를 안 써 주면 기존 동작 그대로다.
    EFFECTIVE_MIN="$MIN_THRESHOLD"
    WORKER_NOTE=""
    if [ -n "$ACTIVE_DISPATCHED" ] && [ "$ACTIVE_DISPATCHED" -gt 0 ]; then
      EFFECTIVE_MIN=$(printf '%s' "$THRESHOLDS" | cut -d, -f2)
      case "$EFFECTIVE_MIN" in ''|*[!0-9]*) EFFECTIVE_MIN="$MIN_THRESHOLD" ;; esac
      WORKER_NOTE="작업자 ${ACTIVE_DISPATCHED}개가 실행 중이다. 감독의 침묵이 정상 대기일 수 있으므로 첫 임계값은 건너뛰었다."
    fi
    if [ "$NO_PROGRESS" -lt "$EFFECTIVE_MIN" ]; then
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
진행 중 발령: ${ACTIVE_DISPATCHED:-중계기가 기록하지 않음}
일기 파일: $RELAY_LOG
$WORKER_NOTE

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

  # 사건 6. 감독 깨우기 심박 끊김 (2026-08-10 B8).
  # 중계기 일기가 있든 없든 따로 본다. 깨우기는 중계기와 다른 프로세스이고, 중계기가 죽어도
  # 깨우기는 살아 있어야 하기 때문이다(그 분리가 B8 의 핵심이다).
  check_waker_heartbeat
  if [ "$WAKER_SILENT_FOR" -ge "$WAKER_LIMIT" ] && [ "$NOW" -ge "$GRACE_UNTIL" ]; then
    if [ "$WAKER_SILENT_ALERTED" -eq 0 ]; then
      if [ "$WAKER_STATE" = absent ]; then
        WAKER_SUBJECT="[정체신고] 감독 깨우기가 아예 없다 — $BOARD"
        WAKER_HEAD="이 판에 감독 주기적 자가 점검 깨우기(supervisor-waker)가 한 번도 심박을 적지 않았다. 깨우기가 떠 있지 않다는 뜻이다."
        WAKER_ACTION="깨우기를 띄워라: supervisor-waker.sh --board $BOARD --supervisor <감독 핸들> --run <프로젝트 Run> --relay-log $RELAY_LOG --runtime-dir <판 런타임 폴더>"
      else
        WAKER_SUBJECT="[정체신고] 감독 깨우기가 멈췄다 — $BOARD"
        WAKER_HEAD="감독 주기적 자가 점검 깨우기(supervisor-waker)의 심박이 ${WAKER_SILENT_FOR}초 동안 갱신되지 않았다. 깨우기 프로세스가 죽었다."
        WAKER_ACTION="죽은 깨우기를 다시 띄워라. 심박 파일의 마지막 줄에 죽기 직전 pid 와 주기가 남아 있다."
      fi
      send_alert "$WAKER_SUBJECT" \
"$WAKER_HEAD

깨우기가 없으면 감독은 편지가 왔을 때만 깨어난다. 편지가 안 오면 영원히 안 깨어난다 — 2026-08-09 열한 시간 정지가 정확히 그 상태였다. 판이 정상인지 아닌지와 무관한 문제다: 판정을 읽을 계기 자체가 없어진 것이다.

판: $PROJECT / $BOARD
심박 파일: $WAKER_HEARTBEAT_LOG
상태: $WAKER_STATE (stopped=있다가 끊김, absent=한 번도 없음)
마지막 심박 이후: ${WAKER_SILENT_FOR}초 (임계값 ${WAKER_LIMIT}초)

$WAKER_ACTION
이 알림은 이 사건에 대해 한 번만 보낸다. 심박이 다시 찍히면 자동으로 재장전된다." \
"{\"event\":\"supervisor_waker_silent\",\"project\":\"$PROJECT\",\"board\":\"$BOARD\",\"wakerState\":\"$WAKER_STATE\",\"silentForSec\":$WAKER_SILENT_FOR,\"limitSec\":$WAKER_LIMIT,\"heartbeatLog\":\"$WAKER_HEARTBEAT_LOG\"}"
      WAKER_SILENT_ALERTED=1
      save_state
      log "alert supervisor_waker_silent state=$WAKER_STATE silent_for=${WAKER_SILENT_FOR}s limit=${WAKER_LIMIT}s"
    fi
  elif [ "$WAKER_SILENT_ALERTED" -ne 0 ]; then
    WAKER_SILENT_ALERTED=0
    save_state
    log "rearm supervisor_waker_recovered silent_for=${WAKER_SILENT_FOR}s"
  fi

  [ "$ONCE" -eq 1 ] && break
  sleep "$POLL_SEC"
done
