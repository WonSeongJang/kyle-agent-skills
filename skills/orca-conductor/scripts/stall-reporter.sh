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
BOARD_IDLE_SEC=300

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
# B7(2026-08-09): 판 비움 감지 상태. 세 경우의 관측 시작 시각과 알림 여부.
#   경우 A: 대기 카드 있음 + 발령 0        -> 감독이 발령을 안 한다
#   경우 B: 판 비움 + 미결 카드 0          -> 감독이 다음 카드를 만들지 않는다
#   경우 C: 판 비움 + 미결 카드 있음       -> 다음 요청은 남아 있는데 아무도 안 돈다
# F-B7(2026-08-09 수정 1): 예전에는 경우 C가 경우 B로 접혔다. 그러면 "할 일이 남았는데
# 안 도는 상태"가 "할 일이 없어 끝난 상태"로 보고된다 — 이 신고기가 막으려던 바로 그 오보다.
BOARD_CASE_A_SINCE=0
BOARD_CASE_A_ALERTED=0
BOARD_CASE_B_SINCE=0
BOARD_CASE_B_ALERTED=0
BOARD_CASE_C_SINCE=0
BOARD_CASE_C_ALERTED=0
# F-B7(수정 2): 카드 장부 조회 실패 상태. 실패는 "카드 0장"이 아니라 "판정 불가"다.
CARD_QUERY_FAIL_STREAK=0
CARD_QUERY_FAIL_ALERTED=0
CARD_CLASSIFICATION_UNAVAILABLE_STREAK=0
CARD_CLASSIFICATION_UNAVAILABLE_ALERTED=0
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE" 2>/dev/null || true
fi

save_state() {
  printf 'ALERTED_LEVEL=%s\nRELAY_SILENT_ALERTED=%s\nWAKER_SILENT_ALERTED=%s\nBOARD_CASE_A_SINCE=%s\nBOARD_CASE_A_ALERTED=%s\nBOARD_CASE_B_SINCE=%s\nBOARD_CASE_B_ALERTED=%s\nBOARD_CASE_C_SINCE=%s\nBOARD_CASE_C_ALERTED=%s\nCARD_QUERY_FAIL_STREAK=%s\nCARD_QUERY_FAIL_ALERTED=%s\nCARD_CLASSIFICATION_UNAVAILABLE_STREAK=%s\nCARD_CLASSIFICATION_UNAVAILABLE_ALERTED=%s\n' \
    "$ALERTED_LEVEL" "$RELAY_SILENT_ALERTED" "${WAKER_SILENT_ALERTED:-0}" "${BOARD_CASE_A_SINCE:-0}" "${BOARD_CASE_A_ALERTED:-0}" "${BOARD_CASE_B_SINCE:-0}" "${BOARD_CASE_B_ALERTED:-0}" "${BOARD_CASE_C_SINCE:-0}" "${BOARD_CASE_C_ALERTED:-0}" "${CARD_QUERY_FAIL_STREAK:-0}" "${CARD_QUERY_FAIL_ALERTED:-0}" "${CARD_CLASSIFICATION_UNAVAILABLE_STREAK:-0}" "${CARD_CLASSIFICATION_UNAVAILABLE_ALERTED:-0}" > "$STATE_FILE"
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
# B7: 임계값 검증. --board-idle-sec 가 숫자가 아니면 기본값으로 돌아간다.
case "$BOARD_IDLE_SEC" in ''|*[!0-9]*) BOARD_IDLE_SEC=300 ;; esac

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
  # B7 요구 4: companion이 찍는 gate_nudge_suppressed 줄이 시간당 약 2160줄 늘어나서
  # tail -n 1 이 거의 항상 잡음 줄을 잡는다. 그래서 순찰 데이터가 있는 줄만 걸러 그중
  # 마지막 줄을 쓴다.
  #
  # F-B7(2026-08-09 수정 3): 예전 주석은 "역순으로 찾는다"였는데 실제 코드는 정방향
  # 전체 스캔이었다. 주석을 코드에 맞췄다. 코드를 역순(`tail -r | grep -m1`)으로 바꾸지
  # 않은 이유: (1) 잡음 홍수는 순찰 줄 "뒤"에 쌓이므로 역순으로 찾아도 결국 파일 전체를
  # 훑는다 — 실측한 홍수 모양에서 이득이 0이다. (2) `tail -r` 은 파일을 통째로 메모리에
  # 올려 뒤집으므로, 흘려보내며 읽는 지금의 한 번 스캔보다 오히려 비싸다. (3) `tail -r`
  # 은 BSD 전용이라 GNU(`tac`) 분기가 하나 더 늘어난다. 10만 줄 홍수 시험이 지금 방식으로
  # 통과하므로 성능 목적의 역순 전환은 근거가 없다.
  LAST_LINE=$(grep -E 'consecutive_no_progress=|no_progress_streak=' "$RELAY_LOG" 2>/dev/null | tail -n 1)
  if [ -z "$LAST_LINE" ]; then
    LAST_LINE=$(tail -n 1 "$RELAY_LOG" 2>/dev/null || printf '')
  fi
  # 순찰 줄은 consecutive_no_progress 또는 no_progress_streak 중 어느 쪽 필드명을 쓸 수 있다.
  # BSD sed 는 BRE 에서 \| 를 지원하지 않으므로 두 패턴으로 나누어 찾는다.
  NO_PROGRESS=$(printf '%s' "$LAST_LINE" | sed -n 's/.*consecutive_no_progress=\([0-9][0-9]*\).*/\1/p' | head -1)
  [ -n "$NO_PROGRESS" ] || NO_PROGRESS=$(printf '%s' "$LAST_LINE" | sed -n 's/.*no_progress_streak=\([0-9][0-9]*\).*/\1/p' | head -1)
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

# B7(2026-08-09): 판의 카드 장부(task-list)를 읽어 대기·발령·미결 카드 수를 센다.
# Why: 작업자가 다 끝났는데 감독이 다음 행동을 안 하면 중계기는 순찰 일기를 갱신하지
# 않는다. 신고기가 숫자를 읽을 수 없어 조용해진다. 그래서 신고기가 판 장부를 직접 본다.
#
# F-B7(2026-08-09 수정 2): 예전에는 `ok` 를 보지 않고 `result.tasks` 를 그대로 믿었다.
# 그래서 조회가 실패해 `ok=false` 로 돌아와도 "카드 0장"으로 읽혀 "판이 비었다"는 경고가
# 나갔다. 오늘 이 판이 열한 시간 멈춘 부류가 정확히 이것이다 — 없다고 읽혀서 조용히
# 넘어가는 것. 그래서 fail-closed 로 바꾼다: 조회가 조금이라도 수상하면 판정하지 않고
# 판정 불가(CARD_QUERY_STATE=failed)로 내보낸다.
#
# CARD_QUERY_STATE 세 값:
#   disabled - --project-run 이 없어 카드 감시 자체를 안 켰다(정상, 조용히 넘어감)
#   failed   - 조회했지만 믿을 수 없다(판정 금지)
#   ok       - 숫자를 믿어도 된다
CARD_QUERY_STATE=disabled
CARD_IDLE_COUNT=0
CARD_DISPATCHED_COUNT=0
CARD_OUTSTANDING_COUNT=0
CARD_TOTAL_COUNT=0
CARD_QUERY_REASON=""
CARD_QUERY_UNKNOWN_STATUSES_JSON="[]"
# 카드 판정의 정식 값 집합이다. unavailable은 오류 코드가 아니라 A/B/C/active와
# 나란히 놓이는 결과값이다. 소비자는 이 값을 보고 다시 측정하며 A/B/C로 추정하지 않는다.
CARD_CLASSIFICATION=not_measured
count_cards() {
  CARD_QUERY_STATE=disabled
  CARD_IDLE_COUNT=0
  CARD_DISPATCHED_COUNT=0
  CARD_OUTSTANDING_COUNT=0
  CARD_TOTAL_COUNT=0
  CARD_QUERY_REASON=""
  CARD_QUERY_UNKNOWN_STATUSES_JSON="[]"
  CARD_CLASSIFICATION=not_measured
  [ -n "$PROJECT_RUN_ID" ] || return 0
  # 여기부터는 "조회를 시도했다". 무엇 하나라도 어긋나면 failed 로 남긴 채 돌아간다.
  CARD_QUERY_STATE=failed
  local output parsed
  CARD_QUERY_REASON="cli_error"
  output=$( "$ORCA_BIN" orchestration task-list --run "$PROJECT_RUN_ID" --json 2>/dev/null ) || return 0
  CARD_QUERY_REASON="empty_output"
  [ -n "$output" ] || return 0
  CARD_QUERY_REASON="unusable_response"
  parsed=$(printf '%s' "$output" | python3 -c '
import json,sys
try:
    root=json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
if not isinstance(root,dict):
    raise SystemExit(1)
# fail-closed 1: ok 가 참이 아니면(거짓이든 아예 없든) 응답 내용을 쓰지 않는다.
if root.get("ok") is not True:
    raise SystemExit(1)
result=root.get("result")
if not isinstance(result,dict):
    raise SystemExit(1)
tasks=result.get("tasks")
if not isinstance(tasks,list):
    raise SystemExit(1)
IDLE={"pending","ready"}
# 종결 상태: 판의 진행 루프가 더 이상 기다리지 않는 카드.
TERMINAL={"completed","failed","cancelled","canceled","skipped","superseded"}
OUTSTANDING={"blocked"}
KNOWN=IDLE | {"dispatched"} | TERMINAL | OUTSTANDING
idle=dispatched=outstanding=0
unknown=[]
for t in tasks:
    # fail-closed 2: 줄 하나라도 모양이 깨졌으면 전체를 못 믿는다.
    if not isinstance(t,dict):
        raise SystemExit(1)
    s=t.get("status")
    if not isinstance(s,str) or not s:
        raise SystemExit(1)
    if s not in KNOWN:
        unknown.append(s)
    elif s in IDLE:
        idle+=1
    elif s=="dispatched":
        dispatched+=1
    elif s in TERMINAL:
        pass
    elif s in OUTSTANDING:
        outstanding+=1
if unknown:
    # 상태 미상은 미결로 추정하지 않는다. 원문 값을 JSON으로 보존해 호출자가
    # 조회 실패와 구분해 기록하고, A/B/C 어느 판정도 하지 못하게 한다.
    print("unknown_status")
    print(json.dumps(sorted(set(unknown)),ensure_ascii=True,separators=(",",":")))
else:
    print("ok")
    print("%d\n%d\n%d\n%d" % (idle,dispatched,outstanding,len(tasks)))
' 2>/dev/null) || return 0
  local parse_state idle dispatched outstanding total _n
  parse_state=$(printf '%s' "$parsed" | sed -n '1p')
  if [ "$parse_state" = unknown_status ]; then
    CARD_QUERY_REASON="unknown_status"
    CARD_QUERY_UNKNOWN_STATUSES_JSON=$(printf '%s' "$parsed" | sed -n '2p')
    [ -n "$CARD_QUERY_UNKNOWN_STATUSES_JSON" ] || CARD_QUERY_UNKNOWN_STATUSES_JSON='["unavailable"]'
    CARD_QUERY_STATE=ok
    CARD_CLASSIFICATION=unavailable
    return 0
  fi
  [ "$parse_state" = ok ] || return 0
  idle=$(printf '%s' "$parsed" | sed -n '2p')
  dispatched=$(printf '%s' "$parsed" | sed -n '3p')
  outstanding=$(printf '%s' "$parsed" | sed -n '4p')
  total=$(printf '%s' "$parsed" | sed -n '5p')
  CARD_QUERY_REASON="unparsable_counts"
  for _n in "$idle" "$dispatched" "$outstanding" "$total"; do
    case "$_n" in ''|*[!0-9]*) return 0 ;; esac
  done
  CARD_IDLE_COUNT="$idle"
  CARD_DISPATCHED_COUNT="$dispatched"
  CARD_OUTSTANDING_COUNT="$outstanding"
  CARD_TOTAL_COUNT="$total"
  CARD_QUERY_REASON=""
  CARD_QUERY_STATE=ok
  if [ "$CARD_DISPATCHED_COUNT" -gt 0 ]; then
    CARD_CLASSIFICATION=active
  elif [ "$CARD_IDLE_COUNT" -gt 0 ]; then
    CARD_CLASSIFICATION=A
  elif [ "$CARD_OUTSTANDING_COUNT" -gt 0 ]; then
    CARD_CLASSIFICATION=C
  else
    CARD_CLASSIFICATION=B
  fi
}

# 조회가 몇 번 연속 실패하면 사람에게 알릴지. 3회로 잡은 근거: Orca 앱 재시작이나 일시적
# 잠금 때문에 한두 번 어긋나는 것은 다음 순찰에서 저절로 회복된다. 3주기 연속 실패는
# 그 시간 내내 신고기가 판을 못 본 것이므로, 침묵하면 "감시가 있다"는 착각만 남는다.
# 알림은 사건당 한 번이고, 조회가 한 번이라도 성공하면 다시 장전된다.
CARD_QUERY_FAIL_LIMIT=3

# 판 비움 세 경우 중 하나를 재장전한다. 이미 깨끗하면 아무것도 하지 않는다.
# $1 = A|B|C, $2 = 로그에 남길 사유
rearm_board_case() {
  case "$1" in
    A)
      { [ "$BOARD_CASE_A_SINCE" -ne 0 ] || [ "$BOARD_CASE_A_ALERTED" -ne 0 ]; } || return 0
      BOARD_CASE_A_SINCE=0; BOARD_CASE_A_ALERTED=0 ;;
    B)
      { [ "$BOARD_CASE_B_SINCE" -ne 0 ] || [ "$BOARD_CASE_B_ALERTED" -ne 0 ]; } || return 0
      BOARD_CASE_B_SINCE=0; BOARD_CASE_B_ALERTED=0 ;;
    C)
      { [ "$BOARD_CASE_C_SINCE" -ne 0 ] || [ "$BOARD_CASE_C_ALERTED" -ne 0 ]; } || return 0
      BOARD_CASE_C_SINCE=0; BOARD_CASE_C_ALERTED=0 ;;
    *) return 0 ;;
  esac
  save_state
  log "rearm board_case_$1 $2"
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

  # 사건 3~5. 판 비움 감지 (2026-08-09 B7, F-B7에서 세 경우로 분리).
  # Why: 작업자가 다 끝났는데 감독이 다음 행동을 안 하는 상태를 어느 장치도 못 잡았다.
  # 중계기는 active_dispatched=0일 때 순찰 일기를 갱신하지 않으므로 신고기가 숫자를 읽을
  # 수 없어 조용했다. 그래서 신고기가 판의 카드 장부를 직접 본다(판정도 여기서 한다 —
  # pipeline_gap은 랠리 내 공백을 잡는 다른 신호라 재활용하지 않는다, B7 검토 결론).
  count_cards
  if [ "$CARD_QUERY_STATE" = failed ]; then
    # F-B7 수정 2: 조회 실패는 판정하지 않는다. 여기서 경우 A/B/C 상태를 건드리지 않는
    # 것이 핵심이다 — 실패를 "판이 비었다"로도, "정상으로 돌아왔다"로도 접지 않고 그대로
    # 얼려 둔다. 조회가 회복되면 그때 원래 상태에서 이어서 판정한다.
    CARD_QUERY_FAIL_STREAK=$(( CARD_QUERY_FAIL_STREAK + 1 ))
    save_state
    log "card_query_failed reason=${CARD_QUERY_REASON:-unknown} unknown_statuses=$CARD_QUERY_UNKNOWN_STATUSES_JSON streak=$CARD_QUERY_FAIL_STREAK limit=$CARD_QUERY_FAIL_LIMIT (판정 보류)"
    if [ "$CARD_QUERY_FAIL_STREAK" -ge "$CARD_QUERY_FAIL_LIMIT" ] && [ "$CARD_QUERY_FAIL_ALERTED" -eq 0 ]; then
      send_alert "[정체신고] 판 장부를 읽지 못한다 — 판정 불가 — $BOARD" \
"신고기가 판의 카드 장부(task-list)를 ${CARD_QUERY_FAIL_STREAK}회 연속으로 읽지 못했다. 판이 비었는지 아닌지 판정할 수 없는 상태다.

판: $PROJECT / $BOARD
프로젝트 Run: $PROJECT_RUN_ID
실패 사유(마지막): ${CARD_QUERY_REASON:-불명}
모르는 상태값: $CARD_QUERY_UNKNOWN_STATUSES_JSON
연속 실패 횟수: ${CARD_QUERY_FAIL_STREAK}회 (임계값 ${CARD_QUERY_FAIL_LIMIT}회)

이 알림은 \"판이 비었다\"가 아니다. \"판이 비었는지 알 수 없다\"다. 조회 실패를 카드 0장으로 접으면 멈춘 판이 끝난 판으로 보이므로, 신고기는 실패 동안 판 비움 판정을 아예 하지 않는다.
장부를 직접 확인하라: orca orchestration task-list --run $PROJECT_RUN_ID --json
조회가 한 번이라도 성공하면 자동으로 재장전된다." \
"{\"event\":\"board_scan_unavailable\",\"project\":\"$PROJECT\",\"board\":\"$BOARD\",\"projectRunId\":\"$PROJECT_RUN_ID\",\"reason\":\"${CARD_QUERY_REASON:-unknown}\",\"unknownStatuses\":$CARD_QUERY_UNKNOWN_STATUSES_JSON,\"failStreak\":$CARD_QUERY_FAIL_STREAK}"
      CARD_QUERY_FAIL_ALERTED=1; save_state
      log "alert board_scan_unavailable streak=$CARD_QUERY_FAIL_STREAK reason=${CARD_QUERY_REASON:-unknown} unknown_statuses=$CARD_QUERY_UNKNOWN_STATUSES_JSON"
    fi
  elif [ "$CARD_QUERY_STATE" = ok ]; then
    if [ "$CARD_QUERY_FAIL_STREAK" -ne 0 ] || [ "$CARD_QUERY_FAIL_ALERTED" -ne 0 ]; then
      CARD_QUERY_FAIL_STREAK=0; CARD_QUERY_FAIL_ALERTED=0; save_state
      log "rearm board_scan_recovered"
    fi
    if [ "$CARD_CLASSIFICATION" = unavailable ]; then
      # 상태 미상은 조회 실패가 아니다. 조회는 성공했고, 카드 판정의 정식 결과가
      # unavailable이다. A/B/C 상태를 얼린 채 다음 주기에 다시 측정한다.
      CARD_CLASSIFICATION_UNAVAILABLE_STREAK=$(( CARD_CLASSIFICATION_UNAVAILABLE_STREAK + 1 ))
      save_state
      log "card_classification=unavailable reason=unknown_status unknown_statuses=$CARD_QUERY_UNKNOWN_STATUSES_JSON streak=$CARD_CLASSIFICATION_UNAVAILABLE_STREAK next_action=remeasure"
      if [ "$CARD_CLASSIFICATION_UNAVAILABLE_STREAK" -ge "$CARD_QUERY_FAIL_LIMIT" ] && [ "$CARD_CLASSIFICATION_UNAVAILABLE_ALERTED" -eq 0 ]; then
        send_alert "[정체신고] 모르는 카드 상태 — 판정 불가 — $BOARD" \
"카드 장부 조회는 성공했지만 아는 상태 집합에 없는 값이 있어 판정을 만들 수 없다.

판정값: unavailable (판정 불가)
원인: unknown_status
모르는 상태값: $CARD_QUERY_UNKNOWN_STATUSES_JSON
다음 행동: 장부를 다시 측정한다. A/B/C 어느 경우로도 추정하지 않는다.
장부 확인: orca orchestration task-list --run $PROJECT_RUN_ID --json" \
"{\"event\":\"board_scan_unavailable\",\"classification\":\"unavailable\",\"project\":\"$PROJECT\",\"board\":\"$BOARD\",\"projectRunId\":\"$PROJECT_RUN_ID\",\"reason\":\"unknown_status\",\"unknownStatuses\":$CARD_QUERY_UNKNOWN_STATUSES_JSON,\"nextAction\":\"remeasure\",\"streak\":$CARD_CLASSIFICATION_UNAVAILABLE_STREAK}"
        CARD_CLASSIFICATION_UNAVAILABLE_ALERTED=1; save_state
        log "alert board_scan_unavailable classification=unavailable reason=unknown_status unknown_statuses=$CARD_QUERY_UNKNOWN_STATUSES_JSON"
      fi
    else
    if [ "$CARD_CLASSIFICATION_UNAVAILABLE_STREAK" -ne 0 ] || [ "$CARD_CLASSIFICATION_UNAVAILABLE_ALERTED" -ne 0 ]; then
      CARD_CLASSIFICATION_UNAVAILABLE_STREAK=0; CARD_CLASSIFICATION_UNAVAILABLE_ALERTED=0; save_state
      log "rearm card_classification_recovered classification=$CARD_CLASSIFICATION"
    fi
    # F-B7 수정 1: 세 경우를 명시적으로 가른다. 어느 것도 다른 것으로 접히지 않는다.
    #   발령 > 0            -> 정상 (셋 다 재장전)
    #   대기 > 0, 발령 0    -> 경우 A
    #   대기 0, 발령 0, 미결 > 0 -> 경우 C  (다음 요청이 남아 있다)
    #   대기 0, 발령 0, 미결 0   -> 경우 B  (다음 요청도 없다)
    if [ "$CARD_CLASSIFICATION" = active ]; then
      rearm_board_case A "dispatched=$CARD_DISPATCHED_COUNT"
      rearm_board_case B "dispatched=$CARD_DISPATCHED_COUNT"
      rearm_board_case C "dispatched=$CARD_DISPATCHED_COUNT"
    elif [ "$CARD_CLASSIFICATION" = A ]; then
      # 경우 A: 대기 카드 있음 + 발령 0 → "감독이 발령을 안 하고 있다".
      rearm_board_case B "idle_appeared=$CARD_IDLE_COUNT"
      rearm_board_case C "idle_appeared=$CARD_IDLE_COUNT"
      if [ "$BOARD_CASE_A_SINCE" -eq 0 ]; then
        BOARD_CASE_A_SINCE=$NOW; save_state
        log "board_case_a_start idle=$CARD_IDLE_COUNT dispatched=0"
      fi
      BOARD_A_AGE=$(( NOW - BOARD_CASE_A_SINCE ))
      if [ "$BOARD_A_AGE" -ge "$BOARD_IDLE_SEC" ] && [ "$BOARD_CASE_A_ALERTED" -eq 0 ]; then
        send_alert "[정체신고] 감독이 발령을 안 하고 있다 — $BOARD" \
"대기 카드 ${CARD_IDLE_COUNT}장이 판에 있는데 발령된 카드가 0개다. 감독이 멈춰서 아무에게도 일을 주지 않고 있다.

판: $PROJECT / $BOARD
대기 카드(발령 대기): ${CARD_IDLE_COUNT}장
발령된 카드(실행 중): 0장
미결 카드(끝나지도 대기도 아님): ${CARD_OUTSTANDING_COUNT}장
전체 카드: ${CARD_TOTAL_COUNT:-불명}장
이 상태 지속: ${BOARD_A_AGE}초 (임계값 ${BOARD_IDLE_SEC}초)

중계기는 발령이 없으면 순찰 일기를 갱신하지 않으므로 이 상태를 스스로 잡지 못한다. 신고기가 판 장부를 직접 읽어 보낸다.
감독이 카드를 발령하면 자동으로 재장전된다." \
"{\"event\":\"board_case_a\",\"project\":\"$PROJECT\",\"board\":\"$BOARD\",\"idleCards\":$CARD_IDLE_COUNT,\"dispatchedCards\":0,\"outstandingCards\":$CARD_OUTSTANDING_COUNT,\"totalCards\":${CARD_TOTAL_COUNT:-0},\"ageSec\":$BOARD_A_AGE}"
        BOARD_CASE_A_ALERTED=1; save_state
        log "alert board_case_a idle=$CARD_IDLE_COUNT age=${BOARD_A_AGE}s"
      fi
    elif [ "$CARD_CLASSIFICATION" = C ]; then
      # 경우 C: 대기 0 + 발령 0인데 미결 카드가 남았다 → "다음 요청은 있는데 안 돈다".
      # 이 경우를 경우 B로 접으면 "할 일이 남았는데 안 도는 상태"가 "다 끝난 상태"로
      # 보고된다. 감독이 해야 할 행동도 다르다 — 새 카드를 만드는 게 아니라 막힌 카드를
      # 푸는 것이다. 그래서 문구를 완전히 분리한다.
      rearm_board_case A "outstanding=$CARD_OUTSTANDING_COUNT"
      rearm_board_case B "outstanding=$CARD_OUTSTANDING_COUNT"
      if [ "$BOARD_CASE_C_SINCE" -eq 0 ]; then
        BOARD_CASE_C_SINCE=$NOW; save_state
        log "board_case_c_start outstanding=$CARD_OUTSTANDING_COUNT idle=0 dispatched=0"
      fi
      BOARD_C_AGE=$(( NOW - BOARD_CASE_C_SINCE ))
      if [ "$BOARD_C_AGE" -ge "$BOARD_IDLE_SEC" ] && [ "$BOARD_CASE_C_ALERTED" -eq 0 ]; then
        send_alert "[정체신고] 미결 카드가 남았는데 아무도 안 돌고 있다 — $BOARD" \
"판이 빈 게 아니다. 미결 카드 ${CARD_OUTSTANDING_COUNT}장이 남아 있는데 대기 카드도 발령된 카드도 0개다. 다음 요청은 판에 있는데 아무도 그것을 돌리지 않는다.

판: $PROJECT / $BOARD
대기 카드(발령 대기): 0장
발령된 카드(실행 중): 0장
미결 카드(끝나지도 대기도 아님): ${CARD_OUTSTANDING_COUNT}장
전체 카드: ${CARD_TOTAL_COUNT:-불명}장
이 상태 지속: ${BOARD_C_AGE}초 (임계값 ${BOARD_IDLE_SEC}초)

이것은 \"다 끝났다\"가 아니다. 미결 카드는 막힌 카드(앞 카드 대기)이거나 신고기가 모르는 상태의 카드다. 새 카드를 만들 게 아니라 그 카드가 왜 못 도는지를 먼저 보라.
장부를 직접 확인하라: orca orchestration task-list --run $PROJECT_RUN_ID --json
카드가 발령되거나 대기 상태로 풀리면 자동으로 재장전된다." \
"{\"event\":\"board_case_c\",\"project\":\"$PROJECT\",\"board\":\"$BOARD\",\"idleCards\":0,\"dispatchedCards\":0,\"outstandingCards\":$CARD_OUTSTANDING_COUNT,\"totalCards\":${CARD_TOTAL_COUNT:-0},\"ageSec\":$BOARD_C_AGE}"
        BOARD_CASE_C_ALERTED=1; save_state
        log "alert board_case_c outstanding=$CARD_OUTSTANDING_COUNT age=${BOARD_C_AGE}s"
      fi
    elif [ "$CARD_CLASSIFICATION" = B ]; then
      # 경우 B: 대기 0 + 발령 0 + 미결 0 → 판이 진짜로 비었다.
      rearm_board_case A "board_emptied"
      rearm_board_case C "board_emptied"
      if [ "$BOARD_CASE_B_SINCE" -eq 0 ]; then
        BOARD_CASE_B_SINCE=$NOW; save_state
        log "board_case_b_start idle=0 dispatched=0 outstanding=0"
      fi
      BOARD_B_AGE=$(( NOW - BOARD_CASE_B_SINCE ))
      if [ "$BOARD_B_AGE" -ge "$BOARD_IDLE_SEC" ] && [ "$BOARD_CASE_B_ALERTED" -eq 0 ]; then
        send_alert "[정체신고] 감독이 다음 카드를 요청하지 않고 있다 — $BOARD" \
"판이 완전히 비었다 — 대기 카드도 발령된 카드도 미결 카드도 0개다. 다음 카드 요청이 ${BOARD_B_AGE}초 동안 없었다. 감독이 다음 카드를 만들지 않고 있다.

판: $PROJECT / $BOARD
대기 카드(발령 대기): 0장
발령된 카드(실행 중): 0장
미결 카드(끝나지도 대기도 아님): 0장
전체 카드: ${CARD_TOTAL_COUNT:-불명}장
이 상태 지속: ${BOARD_B_AGE}초 (임계값 ${BOARD_IDLE_SEC}초)

정상 유휴(진짜로 다 끝난 상태)와 구분하기 위해 임계값(${BOARD_IDLE_SEC}초) 동안 기다렸다. 그래도 새 카드가 없으면 이상으로 본다.
감독이 다음 카드를 요청(또는 판 종료)하면 자동으로 재장전된다." \
"{\"event\":\"board_case_b\",\"project\":\"$PROJECT\",\"board\":\"$BOARD\",\"idleCards\":0,\"dispatchedCards\":0,\"outstandingCards\":0,\"totalCards\":${CARD_TOTAL_COUNT:-0},\"ageSec\":$BOARD_B_AGE}"
        BOARD_CASE_B_ALERTED=1; save_state
        log "alert board_case_b age=${BOARD_B_AGE}s"
      fi
    else
      log "card_classification_contract_error value=$CARD_CLASSIFICATION (판정 보류)"
    fi
    fi
  fi

  [ "$ONCE" -eq 1 ] && break
  sleep "$POLL_SEC"
done
