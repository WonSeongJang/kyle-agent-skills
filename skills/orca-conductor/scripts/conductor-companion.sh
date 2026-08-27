#!/bin/bash
# 프로젝트 supervisor pane에 붙은 mailbox consumer다. 화면 의미 판정은 relay가 맡고,
# companion은 구조화된 relay 후보와 공식 project Run 장부만 대조한다.
set -u

usage() {
  echo "usage: conductor-companion.sh --project <project> --board <board> --supervisor-role <role> --relay-role <role> --run <project-run> [--super-run <legacy-super-run>] [--relay-log <path>] [--no-kicker] [kicker-interval-sec]" >&2
  echo "       conductor-companion.sh --health-decide <log> [--run <project-run>] [--freshness-sec N]  # 판정 -> 다음 행동" >&2
  exit 2
}
# companion output.log 를 읽어 ALIVE/UNKNOWN/DEAD 를 판정한다(B1 정상 판정 계약).
# 최근에 명시적으로 성공한 wait 신호만 ALIVE 이다. 실패·포화·알 수 없는 최근 로그는
# UNKNOWN 이며, SELF_EXIT 또는 오래된 로그만 DEAD 이다.
#
# 무지와 사실을 가르는 기준 (2026-08-09 F-B1-2). DEAD 는 "죽었다"는 **사실 주장**이고,
# 그 근거는 로그 안에 실제로 있어야 한다 — SELF_EXIT 한 줄(자기가 죽었다고 적음),
# 또는 신선도 창을 넘긴 mtime(살아 있으면 15초마다 찍었어야 할 흔적이 없음). 둘 다
# 파일을 읽어서 얻은 증거다.
#   반대로 **파일을 못 읽은 경우는 죽음의 증거가 아니라 증거의 부재**다. 응답 파일이
# 아직 없는 것(막 띄운 companion 이 첫 줄을 쓰기 전)과 mtime 을 못 얻는 것(stat 실패)은
# 둘 다 "모른다"이지 "죽었다"가 아니다. 예전에는 이 둘이 DEAD 로 접혀서, 모름을 담을
# 값을 만들어 놓고도 정작 모름이 그 값으로 가지 않았다. 그러면 아직 안 죽은 companion
# 이 죽었다고 불리고, 그 판정을 받은 절차는 멀쩡한 것을 내린다.
judge_companion_health() {
  local log="$1" freshness="$2" now="$3"
  local mtime age last_signal
  # 응답 파일 없음 = 무지. 죽음의 증거가 아니므로 DEAD 로 접지 않는다.
  [ -f "$log" ] || { echo "UNKNOWN reason=no_log next_action=remeasure"; return 3; }
  if grep -q '^SELF_EXIT ' "$log" 2>/dev/null; then
    echo "DEAD reason=self_exit next_action=retire_new_companion"; return 2
  fi
  mtime=$(stat -f %m "$log" 2>/dev/null || stat -c %Y "$log" 2>/dev/null || echo 0)
  if [ "$mtime" -le 0 ] 2>/dev/null; then
    # mtime 을 못 읽음 = 무지. 나이를 모르니 신선도 판정 자체가 성립하지 않는다.
    echo "UNKNOWN reason=no_mtime next_action=remeasure"; return 3
  fi
  age=$(( now - mtime ))
  if [ "$age" -gt "$freshness" ]; then
    echo "DEAD reason=log_stale age=$age freshness=$freshness next_action=retire_new_companion"
    return 2
  fi
  last_signal=$(grep -E '^(COMPANION_ALIVE |COMPANION_WAITED |COMPANION_WAIT_FAILED |CHECK_DIAGNOSTIC |WAKE_FAIL |GATE_NUDGE_WAKE_FAIL |GATE_NUDGE_SUPPRESSED |gate_nudge_suppressed )' "$log" 2>/dev/null | tail -1 || true)
  case "$last_signal" in
    COMPANION_ALIVE\ *) echo "ALIVE reason=waiting_keepalive_fresh age=$age next_action=proceed"; return 0 ;;
    COMPANION_WAITED\ *check_status=0*) echo "ALIVE reason=wait_completed_fresh age=$age next_action=proceed"; return 0 ;;
    *) echo "UNKNOWN reason=recent_unhealthy_or_unclassified age=$age next_action=remeasure"; return 3 ;;
  esac
}

# UNKNOWN 재측정 계약 (2026-08-09 F-B1-2).
#
# 모름은 통과도 불합격도 아니다. 모름에 대한 **유일한 다음 행동은 다시 재는 것**이며,
# 재측정 없이 행동해 버리면 UNKNOWN 은 이름만 다른 DEAD 가 된다.
#
# 재측정 횟수와 간격의 근거(실측):
#   - 살아서 막혀 있는 companion 은 15초마다 keepalive 를 찍는다(B1 실측: elapsedMs=15004).
#   - 그래서 간격을 20초로 둔다 — 살아 있다면 어느 20초 창에서도 keepalive 가 최소 1번은
#     들어온다. 간격이 15초보다 짧으면 "살아 있는데 아직 안 찍은" 정상 상태를 모름으로
#     오해하고, 재측정이 같은 무지를 반복하기만 한다.
#   - 재측정은 2회(최초 1회 + 재측정 2회 = 총 3회 관측)다. 20초 창 2개를 연속으로
#     비웠다면 "살아 있는데 조용했을 뿐"이라는 설명이 더는 성립하지 않는다. 그 뒤로
#     더 재도 시간만 늘고 정보가 늘지 않는다.
#   - 총 관측 폭 40초는 기본 신선도 창 60초 안이라, 재측정을 기다리는 행위 자체가
#     로그를 stale 로 만들어 DEAD 를 자초하지 않는다.
#
# 그래도 모르면 판정은 UNRESOLVED 다 — **UNKNOWN 과 다른 이름**이어야 재측정을 이미
# 다 쓴 상태임이 드러난다. UNRESOLVED 의 다음 행동은 종료가 아니라 보고다. 아무것도
# 죽이지 않는다. 죽여도 되는 것은 죽음이 사실로 확인된 DEAD 뿐이다.
HEALTH_REMEASURE_COUNT=2
# 간격만 시험 결정성을 위한 조정 손잡이다. 재측정 횟수는 환경변수로 끌 수 없다 —
# 방어는 선택 인자가 아니라 기본 동작이어야 한다.
HEALTH_REMEASURE_GAP_SEC="${COMPANION_HEALTH_REMEASURE_GAP_SEC:-20}"

judge_companion_health_with_remeasure() {
  local log="$1" freshness="$2" now="$3"
  local attempt=1 total=$(( HEALTH_REMEASURE_COUNT + 1 )) out rc
  while : ; do
    # 이 스크립트는 errexit 를 켜지 않는다(set -u 만). 그래서 여기서 set -e 를 켰다
    # 껐다 하지 않는다 — 껐다 켜면 원래 꺼져 있던 errexit 가 이 뒤로 켜져 버린다.
    out=$(judge_companion_health "$log" "$freshness" "$now")
    rc=$?
    printf 'HEALTH_OBSERVATION attempt=%s/%s %s\n' "$attempt" "$total" "$out"
    # 사실이 확인되면(살았다/죽었다) 더 잴 필요가 없다.
    if [ "$rc" -ne 3 ]; then
      printf '%s\n' "$out"
      return "$rc"
    fi
    [ "$attempt" -lt "$total" ] || break
    attempt=$(( attempt + 1 ))
    sleep "$HEALTH_REMEASURE_GAP_SEC"
    [ -n "$HEALTH_NOW_EPOCH" ] || now=$(date +%s)
  done
  # 재측정을 다 쓰고도 모름: UNKNOWN 과 구분되는 이름으로 닫는다.
  echo "UNRESOLVED reason=unknown_after_remeasure observations=$total gap_sec=$HEALTH_REMEASURE_GAP_SEC next_action=report_no_retire"
  return 4
}

# UNRESOLVED 소비 경로 (2026-08-09 F-B1-3).
#
# 값을 만드는 것 / 밖으로 내는 것 / 소비자가 그 값을 쓰는 것은 각각 다른 일이다.
# 앞 라운드에서 UNRESOLVED(exit 4) 라는 값과 행동표까지 만들었지만, 그 값을 실제로
# 받아서 다음 행동을 고르는 **운영 코드는 하나도 없었다**. 행동표가 문서에만 있으면
# 사람이 매번 기억해서 손으로 고르는 것이고, 그러면 급할 때 "ALIVE 냐 아니냐"로 다시
# 뭉개진다 — 모름이 죽음 취급을 받는 바로 그 자리다.
#
# 이 입구가 그 소비자다. 판정을 받아 다음 행동을 고르고, 그 행동을 한 줄로 남긴다.
#   ALIVE(0)      -> action=proceed
#   DEAD(2)       -> action=retire_new_companion  (내리는 행동이 나오는 유일한 자리)
#   UNRESOLVED(4) -> action=report_no_retire + 감독 보고. 아무것도 내리지 않는다.
#   UNKNOWN(3)    -> 최종 판정으로 나오면 안 되는 값이다. 새어 나오면 계약 위반이므로
#                    조용히 넘기지 않고 표식을 남긴 뒤 report_no_retire 로 접는다.
# 종료 코드는 판정 코드를 그대로 물려준다 — 호출자가 같은 표를 다시 쓸 수 있어야 한다.
# 연속 UNRESOLVED 횟수 (2026-08-09 F-B1-3, 감독 판단 2).
#
# 한 번은 모름이고, 연속 3회는 다른 이야기다. 그래서 횟수를 세어 편지에 적는다.
# 다만 **임계값은 코드에 박지 않는다.** 박는 순간 그 숫자가 또 근거 없는 숫자가 되고,
# 코드가 사람 대신 "이제 심각하다"를 선언하게 된다. 여기서 하는 일은 세어서 넘기는
# 것까지이고, 몇 회부터 다른 이야기인지는 사람이 판단한다.
#
# 끊기는 기준: 사실이 확인되면(ALIVE/DEAD) 0으로 돌린다 — 연속이 실제로 끊긴 것이다.
# 모름 계열(UNRESOLVED, 그리고 계약이 깨져 새어 나온 UNKNOWN)만 이어서 센다.
#
# 상태 파일은 **관찰 대상 로그 옆에 쓰지 않는다.** 관찰이 관찰 대상을 건드리면 그 뒤의
# mtime 신선도 판정이 우리가 만든 흔적을 보게 된다. 그래서 로그 경로로 이름만 유도해
# 임시 디렉터리에 둔다. 환경변수는 시험 결정성을 위한 조정 손잡이지 방어 스위치가 아니다.
health_streak_file() {
  local log="$1" key=""
  if [ -n "${COMPANION_HEALTH_STREAK_FILE:-}" ]; then
    printf '%s\n' "$COMPANION_HEALTH_STREAK_FILE"
    return 0
  fi
  key=$(printf '%s' "$log" | shasum -a 256 2>/dev/null | awk '{print $1}')
  [ -n "$key" ] || key=default
  printf '%s/orca-companion-health-streak-%s\n' "${TMPDIR:-/tmp}" "$key"
}

read_health_streak() {
  local file="$1" value=0
  if [ -f "$file" ]; then
    value=$(cat "$file" 2>/dev/null || printf '0')
  fi
  # 비었거나 숫자가 아니면 0에서 다시 센다(상태를 못 읽은 것은 연속의 근거가 아니다).
  case "$value" in
    ''|*[!0-9]*) value=0 ;;
  esac
  printf '%s\n' "$value"
}

report_health_unresolved() {
  local verdict="$1" streak="$2" bin=""
  # 보고는 조용히 실패하지 않는다. 못 보냈으면 못 보냈다고 남긴다.
  if [ -n "${ORCA_BIN:-}" ] && [ -x "${ORCA_BIN:-}" ]; then
    bin="$ORCA_BIN"
  elif command -v orca >/dev/null 2>&1; then
    bin=$(command -v orca)
  elif [ -x /usr/local/bin/orca ]; then
    bin=/usr/local/bin/orca
  elif [ -x /opt/homebrew/bin/orca ]; then
    bin=/opt/homebrew/bin/orca
  fi
  if [ -z "$PROJECT_RUN_ID" ]; then
    echo "HEALTH_REPORT_UNDELIVERED reason=no_run verdict=${verdict%% *} unresolved_streak=$streak"
    return 1
  fi
  if [ -z "$bin" ]; then
    echo "HEALTH_REPORT_UNDELIVERED reason=orca_bin_unavailable verdict=${verdict%% *} unresolved_streak=$streak"
    return 1
  fi
  # 편지에 연속 횟수를 넣는다. 임계값 판단은 담지 않는다 — 숫자만 넘긴다.
  if "$bin" orchestration send --run "$PROJECT_RUN_ID" --type escalation \
      --subject "companion health unresolved (연속 ${streak}회)" \
      --body "$verdict unresolved_streak=$streak" --json >/dev/null 2>&1; then
    echo "HEALTH_REPORT_SENT run=$PROJECT_RUN_ID verdict=${verdict%% *} unresolved_streak=$streak"
    return 0
  fi
  echo "HEALTH_REPORT_UNDELIVERED reason=send_failed verdict=${verdict%% *} unresolved_streak=$streak"
  return 1
}

decide_companion_health_action() {
  local log="$1" freshness="$2" now="$3"
  local out rc verdict action streak_file streak
  out=$(judge_companion_health_with_remeasure "$log" "$freshness" "$now")
  rc=$?
  printf '%s\n' "$out"
  # 관측 줄(HEALTH_OBSERVATION)이 앞에 붙으므로 판정은 마지막 줄이다.
  verdict=$(printf '%s\n' "$out" | tail -1)
  case "$rc" in
    0) action=proceed ;;
    2) action=retire_new_companion ;;
    4) action=report_no_retire ;;
    3)
      # 재측정 계약이 깨져 맨 UNKNOWN 이 최종 판정으로 새어 나왔다.
      echo "HEALTH_CONTRACT_BREAK reason=unknown_escaped_remeasure rc=3"
      action=report_no_retire
      ;;
    *) echo "HEALTH_CONTRACT_BREAK reason=unclassified_rc rc=$rc"; action=report_no_retire ;;
  esac
  # 연속 횟수를 갱신한다. 사실이 확인되면 끊어서 0으로 돌린다.
  streak_file=$(health_streak_file "$log")
  if [ "$action" = report_no_retire ]; then
    streak=$(( $(read_health_streak "$streak_file") + 1 ))
    printf '%s\n' "$streak" > "$streak_file" 2>/dev/null || true
  else
    streak=0
    # 삭제하지 않고 비운다(파일 삭제 명령을 새로 만들지 않는다).
    if [ -f "$streak_file" ]; then : > "$streak_file" 2>/dev/null || true; fi
  fi
  echo "HEALTH_DECISION action=$action rc=$rc verdict=${verdict%% *} unresolved_streak=$streak"
  # 모름 계열은 내리지 않고 보고한다. 내리는 행동은 위 표에서 DEAD 에만 붙어 있다.
  if [ "$action" = report_no_retire ]; then
    report_health_unresolved "$verdict" "$streak" || true
  fi
  return "$rc"
}
PROJECT=""
BOARD=""
SUPERVISOR_ROLE=""
RELAY_ROLE=""
PROJECT_RUN_ID="${COMPANION_RUN_ID:-}"
SUPER_RUN_ID="${COMPANION_SUPER_RUN_ID:-}"
RELAY_LOG_FILE="${RELAY_LOG_FILE:-}"
KICKER_INTERVAL=300
ENABLE_KICKER=1
POSITIONAL_COUNT=0
# health 판정 서브커맨드(2026-08-09 B1). --health-log 가 주어지면 루프를 돌지 않고
# 로그 파일만 읽어 ALIVE/DEAD 를 판정해 돌려주고 끝난다. 관찰자(relay)와 시험이 같은
# 판정 함수를 공유한다.
HEALTH_LOG=""
# 단발 분류(재측정 없음). 재측정 계약 자체를 시험하거나 분류만 볼 때 쓴다.
# 기본 입구는 --health-log 이고 그쪽은 재측정이 켜져 있다 — 방어는 기본값이지
# 선택 인자가 아니다.
HEALTH_CLASSIFY_ONLY=0
# 판정을 받아 다음 행동까지 고르는 운영 소비 경로(--health-decide). 재측정 계약을 그대로
# 쓰고, UNRESOLVED(exit 4)를 실제로 받아 보고로 연결한다.
HEALTH_DECIDE=0
HEALTH_FRESHNESS_SEC="${COMPANION_HEALTH_FRESHNESS_SEC:-60}"
HEALTH_NOW_EPOCH="${COMPANION_HEALTH_NOW_EPOCH:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --project) [ $# -ge 2 ] || usage; PROJECT="$2"; shift 2 ;;
    --board) [ $# -ge 2 ] || usage; BOARD="$2"; shift 2 ;;
    --supervisor-role) [ $# -ge 2 ] || usage; SUPERVISOR_ROLE="$2"; shift 2 ;;
    --relay-role) [ $# -ge 2 ] || usage; RELAY_ROLE="$2"; shift 2 ;;
    --run) [ $# -ge 2 ] || usage; PROJECT_RUN_ID="$2"; shift 2 ;;
    --super-run) [ $# -ge 2 ] || usage; SUPER_RUN_ID="$2"; shift 2 ;;
    --relay-log) [ $# -ge 2 ] || usage; RELAY_LOG_FILE="$2"; shift 2 ;;
    --health-log) [ $# -ge 2 ] || usage; HEALTH_LOG="$2"; shift 2 ;;
    --health-classify) [ $# -ge 2 ] || usage; HEALTH_LOG="$2"; HEALTH_CLASSIFY_ONLY=1; shift 2 ;;
    --health-decide) [ $# -ge 2 ] || usage; HEALTH_LOG="$2"; HEALTH_DECIDE=1; shift 2 ;;
    --freshness-sec) [ $# -ge 2 ] || usage; HEALTH_FRESHNESS_SEC="$2"; shift 2 ;;
    --now-epoch) [ $# -ge 2 ] || usage; HEALTH_NOW_EPOCH="$2"; shift 2 ;;
    --no-kicker) ENABLE_KICKER=0; shift ;;
    --*) echo "UNKNOWN_FLAG $1" >&2; usage ;;
    *)
      POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
      [ "$POSITIONAL_COUNT" -eq 1 ] || {
        echo "LEGACY_HANDLE_ARGS_REJECTED use role identity and Run IDs" >&2
        usage
      }
      KICKER_INTERVAL="$1"
      shift
      ;;
  esac
done
# health 판정 모드는 역할 신분·Run 없이 로그 파일만 읽는다. 그 외 모드만 신분을 요구한다.
if [ -z "$HEALTH_LOG" ]; then
  [ -n "$PROJECT" ] || { echo "ROLE_IDENTITY_REQUIRED project" >&2; usage; }
  [ -n "$BOARD" ] || { echo "ROLE_IDENTITY_REQUIRED board" >&2; usage; }
  [ -n "$SUPERVISOR_ROLE" ] || { echo "ROLE_IDENTITY_REQUIRED supervisor-role" >&2; usage; }
  [ -n "$RELAY_ROLE" ] || { echo "ROLE_IDENTITY_REQUIRED relay-role" >&2; usage; }
  [ -n "$PROJECT_RUN_ID" ] || { echo "COMPANION_RUN_ID_REQUIRED" >&2; exit 2; }
fi
# health 판정 모드: 루프·ORCA_BIN 없이 로그만 판정하고 끝낸다.
if [ -n "$HEALTH_LOG" ]; then
  _now="${HEALTH_NOW_EPOCH:-$(date +%s)}"
  # 기본 입구(--health-log)는 재측정까지 포함한 완결 계약이다. 그래서 이 입구는
  # 호출자에게 맨 UNKNOWN 을 건네주지 않는다 — 호출자가 모름을 근거로 행동할 여지를
  # 아예 남기지 않는다. 단발 분류가 필요하면 --health-classify 로 명시해야 한다.
  if [ "$HEALTH_DECIDE" = 1 ]; then
    # 운영 소비 경로: 판정을 받아 다음 행동을 고르고, 모름 계열은 보고로 연결한다.
    decide_companion_health_action "$HEALTH_LOG" "$HEALTH_FRESHNESS_SEC" "$_now"
  elif [ "$HEALTH_CLASSIFY_ONLY" = 1 ]; then
    judge_companion_health "$HEALTH_LOG" "$HEALTH_FRESHNESS_SEC" "$_now"
  else
    judge_companion_health_with_remeasure "$HEALTH_LOG" "$HEALTH_FRESHNESS_SEC" "$_now"
  fi
  exit $?
fi

POLL_INTERVAL="${COMPANION_POLL_INTERVAL_SEC:-30}"
# wait 기반 대기(2026-08-09 B1). check --wait 가 지원되면 sleep 폴링 대신 편지가
# 도착할 때까지 막고 기다린다. 대기 중 stderr 로 15초마다 오는 _keepalive 를
# COMPANION_ALIVE 마커로 바꿔 "막혀서 대기 중"과 "죽어서 조용함"을 구분한다(실측).
# --wait 미지원 도구를 만나면 폴백으로 sleep 폴링하되 조용히 강등하지 않고
# COMPANION_WAIT_FALLBACK 로그를 반드시 한 번 남긴다(조용한 폴백은 3라운드 실패 유형).
WAIT_MIN_MS="${COMPANION_WAIT_MIN_MS:-5000}"
WAIT_MAX_MS="${COMPANION_WAIT_MAX_MS:-60000}"
# 비워두면 --types 없이 "아무 편지나 도착하면 깬다"(가장 넓다). 좁히지 않는다(실측 계약).
WAIT_TYPES="${COMPANION_WAIT_TYPES:-}"
WAIT_CAPABLE=""
WAIT_FALLBACK_LOGGED=0
DID_WAIT_THIS_CYCLE=0
LEDGER_SCAN_LIMIT="${PROJECT_LEDGER_SCAN_LIMIT:-100}"
# GATE_NUDGE 전체 편지 조회 한도는 PROJECT_LEDGER_SCAN_LIMIT과 분리한 전용 값이다.
# 현재 inbox CLI에는 페이지 순회가 없고(--limit이 반환 행 최대 개수) --full도 그 한도
# 안에서만 전체 문맥을 포함한다(실물 --help 실측). 그래서 충분히 큰 전용 한도로 한 번에
# 가져오고, count >= 한도(포화)면 "전체를 다 봤다"는 증거가 없으므로 편지 부재를
# 확정하지 않고 전체 스냅샷 wake 0으로 닫는다.
GATE_NUDGE_INBOX_LIMIT="${GATE_NUDGE_INBOX_LIMIT:-2000}"
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

# 기동 시 1회: 이 ORCA_BIN 이 check --wait 를 아는가. 도움말 원문으로만 판정한다(부작용 0).
# PATH 의 다른 orca 가 아닌 판 고정 ORCA_BIN 기준이어야 한다(버전 섞임 금지 계약).
probe_wait_capability() {
  local help_out
  help_out=$("$ORCA_BIN" orchestration check --help 2>&1 || true)
  case "$help_out" in
    *"--wait"*) WAIT_CAPABLE=1 ;;
    *) WAIT_CAPABLE=0 ;;
  esac
}
probe_wait_capability

DEADLINE=$(( $(date +%s) + ${WATCH_DEADLINE_MIN:-720} * 60 ))
NEXT_KICKER=$(( $(date +%s) + KICKER_INTERVAL ))
if [ -n "${WATCH_DEADLINE_SEC:-}" ]; then
  DEADLINE=$(( $(date +%s) + WATCH_DEADLINE_SEC ))
fi
SUPERVISOR_HANDLE=""
SUPERVISOR_PANE=""
RELAY_HANDLE=""
RESOLVED_HANDLE=""
RESOLVED_PANE=""
RESOLVE_REASON=""
SEEN_IDS="|"
SEEN_EVENT_KEYS="|"
SEEN_CANDIDATE_KEYS="|"
SEEN_MALFORMED="|"
# worker_done 완료 원장은 task+dispatch 단위로 1줄만 쓴다(같은 카드의 중복 보고 보호).
SEEN_WD_LEDGER="|"
SEEN_MALFORMED_SHAPE="|"
# F-B11-2: 모양 결함 진단을 실제 감시 Run 으로 올린 기록. 상신이 성공한 뒤에만 채운다
# (실패한 상신을 성공으로 기억하면 아무도 못 읽는 진단이 그대로 묻힌다).
SEEN_SHAPE_REPORTS="|"
# F-B11-3: 상신이 한도까지 실패했을 때 감독을 직접 1회 깨운 기록(같은 프로세스 반복 금지).
SEEN_SHAPE_EMERGENCY="|"
# F-B11-3: 직접 깨우기까지 실패하면 다음 자가점검이 읽는 고정 상태 파일에 남긴다.
# 새 감시 프로세스는 만들지 않는다 — 이 파일을 읽는 소비자는 아래 루프의 자가점검 한 곳이다.
SHAPE_EMERGENCY_STATE_FILE="${COMPANION_SHAPE_EMERGENCY_FILE:-}"
if [ -z "$SHAPE_EMERGENCY_STATE_FILE" ] && [ -n "$RELAY_LOG_FILE" ]; then
  # 판마다 따로 둔다. 실제 배치에서 여러 판의 relay 로그가 한 폴더를 같이 쓰므로,
  # 이름을 고정하면 다른 판의 companion 이 남긴 미해결 상태를 자기 것으로 읽는다.
  SHAPE_EMERGENCY_STATE_FILE="$(dirname "$RELAY_LOG_FILE")/shape-emergency.$(printf '%s' "${BOARD:-unknown}" | tr -c 'A-Za-z0-9_.-' '_').state"
fi
SEEN_ROSTER_DIAGNOSTICS="|"
MISROUTED_SENT_KEYS="|"
MISROUTED_WAKE_KEYS="|"
LATE_RECOVERED_KEYS="|"
SEEN_NUDGE_KEYS="|"
SEEN_MISSING_RELAY_KEYS="|"
SEEN_GATE_NUDGE_KEYS="|"
CHECK_DIAGNOSTIC=""
DELIVERY_OK=1
OWNER_MISMATCH_STREAK=0
ROSTER_FAIL_STREAK=0
SUPER_COORDINATOR_HANDLE=""
SUPER_COORDINATOR_PANE=""
SUPER_RUN_ID_VERIFIED=""
# B6: 같은 편지에서 깨우기가 몇 번 실패했는지 센다. 일시 장애는 Delivery 재시도로 넘기되,
# 무한 재시도로 큐 앞을 영구히 막지 않는다(2026-08-09 11시간 정지 사고의 구조적 원인).
WAKE_FAIL_ATTEMPTS="|"
MAX_WAKE_ATTEMPTS="${COMPANION_MAX_WAKE_ATTEMPTS:-3}"

has_key() {
  case "$1" in *"|$2|"*) return 0 ;; *) return 1 ;; esac
}
diagnose_roster_once() {
  local key="$1:$2"
  has_key "$SEEN_ROSTER_DIAGNOSTICS" "$key" && return 0
  SEEN_ROSTER_DIAGNOSTICS="$SEEN_ROSTER_DIAGNOSTICS$key|"
  echo "ROSTER_FAIL_CLOSED role=$1 reason=$2"
}
# roster resolve 응답은 currentHandle 하나만 믿지 않는다(Track G 551ae18 계약).
# project+board+role+runId+status+lifecycle+live(member/result)+pane+currentHandle 을
# 모두 기대값과 대조하고, 하나라도 빠지거나 어긋나면 identity_mismatch 로 fail-closed 한다.
# currentHandle 만 맞춘 위조 응답은 여기서 막힌다.
resolve_role_current() {
  local role="$1" output status parsed ok handle pane rest
  RESOLVED_HANDLE=""
  RESOLVED_PANE=""
  RESOLVE_REASON=""
  output=$( "$ORCA_BIN" roster resolve --project "$PROJECT" --board "$BOARD" --role "$role" --run "$PROJECT_RUN_ID" --json 2>&1 )
  status=$?
  if [ "$status" -ne 0 ]; then
    case "$output" in
      *role_roster_ambiguous*) RESOLVE_REASON=ambiguous ;;
      *role_roster_not_found*) RESOLVE_REASON=not_found ;;
      *no\ live\ terminal*) RESOLVE_REASON=no_live_terminal ;;
      *) RESOLVE_REASON=resolve_failed ;;
    esac
    return 1
  fi
  parsed=$(printf '%s' "$output" | PROJECT="$PROJECT" BOARD="$BOARD" ROLE="$role" RUN_ID="$PROJECT_RUN_ID" python3 -c '
import json,os,sys
def get(obj,*keys):
    for key in keys:
        if isinstance(obj,dict) and obj.get(key) is not None: return obj.get(key)
    return None
def truthy(raw):
    if isinstance(raw,bool): return raw
    return str(raw or "").strip().lower() in ("true","1","yes")
try:
    root=json.load(sys.stdin)
    result=root.get("result") or {}
    member=result.get("member") or {}
except Exception:
    result={}; member={}
valid=isinstance(result,dict) and isinstance(member,dict) and bool(member)
for expected,aliases in ((os.environ.get("PROJECT",""),("project",)),(os.environ.get("BOARD",""),("board",)),(os.environ.get("ROLE",""),("role",)),(os.environ.get("RUN_ID",""),("runId","run_id"))):
    if str(get(member,*aliases) or "") != expected: valid=False
if str(get(member,"status") or "") != "active": valid=False
if str(get(member,"lifecycle") or "") != "active": valid=False
if not truthy(get(member,"live")) or not truthy(get(result,"live")): valid=False
pane=str(get(member,"pane") or "")
if not pane: valid=False
handle=str(get(member,"currentHandle","current_handle") or "")
if not handle or handle != str(get(result,"currentHandle","current_handle") or ""): valid=False
print(("true" if valid else "false")+"\t"+handle+"\t"+pane)
' 2>/dev/null || true)
  ok="${parsed%%$'\t'*}"
  rest="${parsed#*$'\t'}"
  handle="${rest%%$'\t'*}"
  pane="${rest#*$'\t'}"
  if [ "$ok" != true ] || [ -z "$handle" ]; then
    RESOLVE_REASON=identity_mismatch
    return 1
  fi
  RESOLVED_HANDLE="$handle"
  RESOLVED_PANE="$pane"
}
refresh_supervisor_handle() {
  if ! resolve_role_current "$SUPERVISOR_ROLE"; then
    diagnose_roster_once "$SUPERVISOR_ROLE" "$RESOLVE_REASON"
    return 1
  fi
  SUPERVISOR_HANDLE="$RESOLVED_HANDLE"
  SUPERVISOR_PANE="$RESOLVED_PANE"
}
refresh_relay_handle() {
  if ! resolve_role_current "$RELAY_ROLE"; then
    diagnose_roster_once "$RELAY_ROLE" "$RESOLVE_REASON"
    return 1
  fi
  RELAY_HANDLE="$RESOLVED_HANDLE"
}
# Track G 551ae18: 같은 project+board+run 의 active relay roster 를 fail-closed 로 확인한다.
# 필드 누락·불일치·복수 행은 present 로 반올림하지 않고 unknown/ambiguous 로 남긴다.
relay_active_roster_state() {
  local output status state
  output=$( "$ORCA_BIN" roster list --project "$PROJECT" --board "$BOARD" --role "$RELAY_ROLE" --run "$PROJECT_RUN_ID" --status active --json 2>&1 )
  status=$?
  if [ "$status" -ne 0 ]; then
    echo unknown
    return 0
  fi
  state=$(printf '%s' "$output" | PROJECT="$PROJECT" BOARD="$BOARD" ROLE="$RELAY_ROLE" RUN_ID="$PROJECT_RUN_ID" python3 -c '
import json,os,sys
try:
    root=json.load(sys.stdin)
    members=(root.get("result") or {}).get("members")
    if not isinstance(members,list): raise ValueError
except Exception:
    print("unknown")
    raise SystemExit(0)

def value(row,*names):
    for name in names:
        if isinstance(row,dict) and row.get(name) is not None:
            return row.get(name)
    return None

def truthy(raw):
    if isinstance(raw,bool): return raw
    return str(raw or "").strip().lower() in ("true","1","yes")

if len(members) == 0:
    print("absent")
elif len(members) != 1:
    print("ambiguous")
else:
    row=members[0]
    valid=isinstance(row,dict)
    for expected,aliases in ((os.environ.get("PROJECT",""),("project",)),(os.environ.get("BOARD",""),("board",)),(os.environ.get("ROLE",""),("role",)),(os.environ.get("RUN_ID",""),("runId","run_id"))):
        if str(value(row,*aliases) or "") != expected: valid=False
    if str(value(row,"lifecycle") or "") != "active": valid=False
    if str(value(row,"status") or "") != "active": valid=False
    if not truthy(value(row,"live")): valid=False
    if not value(row,"pane"): valid=False
    if not value(row,"currentHandle","current_handle"): valid=False
    print("present" if valid else "unknown")
')
  case "$state" in
    present|absent|ambiguous|unknown) echo "$state" ;;
    *) echo unknown ;;
  esac
}
# Track G 551ae18: ready 카드 + active dispatch 없음 + coordinator idle 이 모두 true 이고
# board 가 닫히지도 gate 를 기다리지도 않을 때만, 같은 state fingerprint 당 1회 wake 한다.
handle_nudge_observation() {
  local fingerprint="$1" ready_present="$2" active_dispatch_absent="$3" coordinator_idle="$4" board_closed="$5" gate_waiting="$6"
  local signal
  if [ "$ready_present" != true ] || [ "$active_dispatch_absent" != true ] || [ "$coordinator_idle" != true ] || [ "$board_closed" = true ] || [ "$gate_waiting" = true ]; then
    echo "NUDGE_SUPPRESSED fingerprint=${fingerprint:-missing} ready=$ready_present active_dispatch_absent=$active_dispatch_absent coordinator_idle=$coordinator_idle board_closed=$board_closed gate_waiting=$gate_waiting wake=0"
    return 0
  fi
  [ -n "$fingerprint" ] || {
    echo "NUDGE_SUPPRESSED fingerprint=missing reason=state_fingerprint_required wake=0"
    return 0
  }
  if has_key "$SEEN_NUDGE_KEYS" "$fingerprint"; then
    echo "NUDGE_DUPLICATE fingerprint=$fingerprint wake=0"
    return 0
  fi
  signal="NUDGE fingerprint=$fingerprint ready_card_present=true active_dispatch_absent=true coordinator_idle=true"
  emit_signal "$signal" "ready 카드가 있지만 active dispatch가 없고 coordinator가 idle입니다. 같은 지문에서 카드를 중복 생성하지 말고 현재 Run과 발령 대상을 확인하세요." || return 1
  SEEN_NUDGE_KEYS="$SEEN_NUDGE_KEYS$fingerprint|"
  log_relay_event "nudge fingerprint=$fingerprint wake=1"
}
# Track G 551ae18: 개시 선언이 왔는데 같은 판의 유효한 live relay roster 가 없을 때만
# fingerprint 당 1회 MISSING_RELAY 를 보낸다. roster 조회가 모호하면 추측하지 않는다.
handle_start_declaration() {
  local message_id="$1" fingerprint="$2" board_closed="$3" gate_waiting="$4" relay_state
  if [ "$board_closed" = true ] || [ "$gate_waiting" = true ]; then
    echo "MISSING_RELAY_SUPPRESSED fingerprint=${fingerprint:-message:$message_id} board_closed=$board_closed gate_waiting=$gate_waiting wake=0"
    return 0
  fi
  relay_state=$(relay_active_roster_state)
  case "$relay_state" in
    present)
      echo "MISSING_RELAY_SUPPRESSED fingerprint=${fingerprint:-message:$message_id} relay=present wake=0"
      return 0
      ;;
    absent)
      [ -n "$fingerprint" ] || {
        echo "MISSING_RELAY_SUPPRESSED fingerprint=missing reason=state_fingerprint_required wake=0"
        return 0
      }
      if has_key "$SEEN_MISSING_RELAY_KEYS" "$fingerprint"; then
        echo "MISSING_RELAY_DUPLICATE fingerprint=$fingerprint wake=0"
        return 0
      fi
      emit_signal "MISSING_RELAY fingerprint=$fingerprint message=$message_id" "개시 선언은 도착했지만 같은 project+board+run의 active relay roster가 없습니다. 카드나 상태를 추측하지 말고 relay 편성과 roster를 확인하세요." || return 1
      SEEN_MISSING_RELAY_KEYS="$SEEN_MISSING_RELAY_KEYS$fingerprint|"
      log_relay_event "missing_relay fingerprint=$fingerprint message=$message_id wake=1"
      ;;
    ambiguous|unknown)
      echo "MISSING_RELAY_CHECK_UNKNOWN fingerprint=${fingerprint:-message:$message_id} roster=$relay_state wake=0"
      ;;
  esac
}
# 매 검사 시점마다 super Run(run-show)의 현재 coordinator handle/pane을 동적 조회한다.
# coordinator는 교대·재기동으로 바뀌므로 고정 handle을 쓰지 않는다. 새 슈퍼 세션이
# run-use 인수를 수행하면 다음 조회부터 companion이 새 coordinator에 자동 적응한다.
# 응답의 run.id 가 요청한 --super-run 과 정확히 같고 coordinator_handle 과
# coordinator_pane_key 가 둘 다 비어 있지 않을 때만 권위를 인정한다. pane 없는 run-show
# 응답은 안정된 창 신분이 아니므로 지시 권위가 0이다(wake 0).
resolve_super_coordinator() {
  SUPER_COORDINATOR_HANDLE=""
  SUPER_COORDINATOR_PANE=""
  SUPER_RUN_ID_VERIFIED=""
  [ -n "$SUPER_RUN_ID" ] || return 1
  local output parsed run_id rest handle pane
  output=$( "$ORCA_BIN" orchestration run-show --id "$SUPER_RUN_ID" --json 2>/dev/null ) || return 1
  parsed=$(printf '%s' "$output" | python3 -c '
import json,sys
try:
    run=(json.load(sys.stdin).get("result") or {}).get("run") or {}
except Exception:
    raise SystemExit(0)
i=run.get("id") or run.get("runId") or run.get("run_id") or ""
h=run.get("coordinator_handle") or run.get("coordinatorHandle") or ""
p=run.get("coordinator_pane_key") or run.get("coordinatorPaneKey") or ""
print(str(i)+"\t"+str(h)+"\t"+str(p))
') || return 1
  run_id="${parsed%%$'\t'*}"
  rest="${parsed#*$'\t'}"
  handle="${rest%%$'\t'*}"
  pane="${rest#*$'\t'}"
  [ "$run_id" = "$SUPER_RUN_ID" ] || return 1
  # run-show 가 요청한 --super-run 과 같은 run.id 를 돌려줬다: 슈퍼 Run 이 도달 가능하고
  # 정확하다. coordinator handle/pane 유무와 무관하게 GATE_NUDGE 가 이 값을 재사용해
  # 추가 run-show 호출 없이 "run-show 실패/mismatch => wake 0" 계약을 충족한다.
  SUPER_RUN_ID_VERIFIED="$run_id"
  [ -n "$handle" ] || return 1
  [ -n "$pane" ] || return 1
  SUPER_COORDINATOR_HANDLE="$handle"
  SUPER_COORDINATOR_PANE="$pane"
  return 0
}
# 공식 대응 편지의 발신 창 신분은 pane 문자열 집합이 아니라 같은 roster 행의
# pane+허용 handle 쌍이다. 실물 RoleRosterMember 스키마에서 active 행의 권위 핸들은
# currentHandle, inactive/retired 행의 권위 핸들은 lastSeenHandle(last_seen_handle)이다 —
# retired 행의 currentHandle 은 pane 재사용 시 현재 live 핸들을 가리킬 수 있어 신원이
# 아니다. 슈퍼 Run의 decision_gate 편지는 발송 시점의 project supervisor pane+handle 에서
# run:<super-run> 주소로 전달된다. 세션 교대로 supervisor가 바뀌어도 retired member는
# pane+lastSeenHandle 과 함께 roster 이력에 남는다(roster list 도움말 실측).
# 그래서 active+inactive+retired 세 상태의 쌍을 매 조회마다 다시 모은다 — 교대 전 정상
# 발송 편지는 새 감독 인수 뒤에도 계속 대응 편지로 인정된다. 같은 pane 의 다른 handle,
# 다른 pane 의 같은 handle, 이 쌍 밖의 편지는 대응 편지로 세지 않는다.
# 각 roster list 응답은 최상위 ok=true, result.members, 행의 정확 project/board/role/run,
# 요청 status 와 일치하는 status/lifecycle/live 의미, pane, handle 이력을 모두 검증한다.
# active 집합은 정확히 1행이고 roster resolve 가 확인한 pane+currentHandle 과 같아야 한다.
# 하나라도 불명확하면 추측하지 않고 실패로 돌린다(호출부에서 wake 0). 각 권위 쌍을
# "pane\thandle" 한 줄로 낸다.
supervisor_roster_pairs() {
  local resolve_pane="$1" resolve_handle="$2" roster_status output
  for roster_status in active inactive retired; do
    output=$( "$ORCA_BIN" roster list --project "$PROJECT" --board "$BOARD" --role "$SUPERVISOR_ROLE" --run "$PROJECT_RUN_ID" --status "$roster_status" --json 2>/dev/null ) || return 1
    printf '%s' "$output" | REQ_STATUS="$roster_status" RESOLVE_PANE="$resolve_pane" RESOLVE_HANDLE="$resolve_handle" PROJECT="$PROJECT" BOARD="$BOARD" ROLE="$SUPERVISOR_ROLE" RUN_ID="$PROJECT_RUN_ID" python3 -c '
import json,os,sys
REQ=os.environ["REQ_STATUS"]; RP=os.environ["RESOLVE_PANE"]; RH=os.environ["RESOLVE_HANDLE"]
def v(row,*names):
    for name in names:
        if isinstance(row,dict) and row.get(name) is not None: return row.get(name)
    return None
def truthy(raw):
    if isinstance(raw,bool): return raw
    return str(raw or "").strip().lower() in ("true","1","yes")
try:
    root=json.load(sys.stdin)
    if root.get("ok") is not True: raise SystemExit(1)
    members=(root.get("result") or {}).get("members")
    if not isinstance(members,list): raise SystemExit(1)
except Exception:
    raise SystemExit(1)
if REQ=="active" and len(members)!=1: raise SystemExit(1)
for row in members:
    if not isinstance(row,dict): raise SystemExit(1)
    for expected,aliases in ((os.environ["PROJECT"],("project",)),(os.environ["BOARD"],("board",)),(os.environ["ROLE"],("role",)),(os.environ["RUN_ID"],("runId","run_id"))):
        if str(v(row,*aliases) or "") != expected: raise SystemExit(1)
    status=str(v(row,"status") or "")
    lifecycle=str(v(row,"lifecycle") or "")
    pane=str(v(row,"pane") or "")
    if not pane: raise SystemExit(1)
    if REQ=="active":
        if status!="active" or lifecycle!="active" or not truthy(v(row,"live")): raise SystemExit(1)
        handle=str(v(row,"currentHandle","current_handle") or "")
        if not handle or pane!=RP or handle!=RH: raise SystemExit(1)
        print(pane+"\t"+handle)
    else:
        if status!=REQ or lifecycle!=REQ or truthy(v(row,"live")): raise SystemExit(1)
        handle=str(v(row,"lastSeenHandle","last_seen_handle") or "")
        if not handle: raise SystemExit(1)
        print(pane+"\t"+handle)
' || return 1
  done
}
gate_nudge_analyze() {
  local gate_output gate_status inbox_output inbox_status pairs
  # 현재 supervisor pane+currentHandle 은 같은 주기의 신분 확인(refresh_supervisor_handle,
  # roster resolve 성공 + owner 일치)에서 이미 확정한 값을 재사용한다 — 같은 권위를
  # 같은 주기에 두 번 조회하지 않는다. active roster 집합은 이 쌍과 정확히 일치해야
  # 한다(B6). 값이 비어 있으면 신분 자체가 불명확하므로 추측하지 않고 wake 0 으로 닫는다.
  if [ -z "$SUPERVISOR_PANE" ] || [ -z "$SUPERVISOR_HANDLE" ]; then
    printf '%s\n' "STATUS roster_resolve_failed"
    return 0
  fi
  gate_output=$( "$ORCA_BIN" orchestration gate-list --run "$PROJECT_RUN_ID" --status pending --json 2>&1 )
  gate_status=$?
  # B6: 조회 창을 슈퍼 Run 자기 우편함으로 좁힌다. inbox 는 기본이 Run 전역이라 이미 닫힌
  # 다른 판의 편지가 창을 다 먹고 매 주기 inbox_saturated 로 닫히는 포화 실명이 났다
  # (2026-08-09 실측: 전역 2579통 중 우리 창 2000통이 전부 다른 판 것). 여기서 찾는
  # 편지는 정의상 to_handle="run:<슈퍼Run>" 하나뿐이므로 --terminal 로 그 주소만 받으면
  # 다른 판 traffic 과 무관하게 창이 유지된다. 아래 python 의 run_id/to_handle 대조는
  # 그대로 남겨 CLI 가 범위를 안 좁혔을 때도 잘못 세지 않게 한다. --terminal 미지원이면
  # 조용히 전역으로 강등하지 않고 inbox_failed 로 닫힌다(조용한 폴백 금지).
  inbox_output=$( "$ORCA_BIN" orchestration inbox --full --terminal "run:$SUPER_RUN_ID" --limit "$GATE_NUDGE_INBOX_LIMIT" --json 2>&1 )
  inbox_status=$?
  if [ "$gate_status" -ne 0 ]; then
    printf '%s\n' "STATUS gate_list_failed"
    return 0
  fi
  if [ "$inbox_status" -ne 0 ]; then
    printf '%s\n' "STATUS inbox_failed"
    return 0
  fi
  pairs=$(supervisor_roster_pairs "$SUPERVISOR_PANE" "$SUPERVISOR_HANDLE") || {
    printf '%s\n' "STATUS roster_history_failed"
    return 0
  }
  { printf '%s' "$gate_output"; printf '__GATE_NUDGE_BLOB_SPLIT__'; printf '%s' "$inbox_output"; } \
    | SUPER_RUN="$SUPER_RUN_ID" PROJECT="$PROJECT" BOARD="$BOARD" RUN_ID="$PROJECT_RUN_ID" INBOX_LIMIT="$GATE_NUDGE_INBOX_LIMIT" ROSTER_PAIRS="$pairs" python3 -c '
import json,os,sys
SUPER=os.environ["SUPER_RUN"]; PROJECT=os.environ["PROJECT"]; BOARD=os.environ["BOARD"]
RUN_ID=os.environ["RUN_ID"]; LIMIT=int(os.environ["INBOX_LIMIT"])
# 권위 발신 신분: 같은 roster 행의 pane+허용 handle 쌍(active=currentHandle,
# inactive/retired=lastSeenHandle). 같은 pane 의 다른 handle, 다른 pane 의 같은
# handle 은 이 집합에 없으므로 대응 편지가 아니다.
PAIRS=set()
for line in os.environ.get("ROSTER_PAIRS","").splitlines():
    cells=line.split("\t")
    if len(cells)==2 and cells[0] and cells[1]: PAIRS.add((cells[0],cells[1]))
raw=sys.stdin.read()
parts=raw.split("__GATE_NUDGE_BLOB_SPLIT__",1)
if len(parts)!=2:
    print("STATUS unknown"); raise SystemExit(0)
def load(text):
    try:
        return json.loads(text)
    except Exception:
        return None
def first(obj,*names):
    for name in names:
        if isinstance(obj,dict) and obj.get(name) is not None: return obj.get(name)
    return None
def is_int(x):
    return isinstance(x,int) and not isinstance(x,bool)
# gate-list 스냅샷: 최상위 ok=true, result 모양, 요청 Run 일치. count 는 필수이며
# bool 이 아닌 0 이상 정수이고 실제 행 수와 같아야 한다(A1). 전 행은 실제 CLI
# DecisionGateRow 계약(id, task_id, status=pending)을 필수로 갖춰야 한다(A2).
# result가 남아 있어도 ok=false면 닫고, 필드 누락·틀린 형식·정상 행과 잘못된 행이
# 섞이면 전체 스냅샷을 닫는다(부분 신뢰 없음).
gd=load(parts[0])
if not isinstance(gd,dict):
    print("STATUS gate_unknown"); raise SystemExit(0)
if gd.get("ok") is not True:
    print("STATUS gate_untrusted"); raise SystemExit(0)
gres=gd.get("result")
if not isinstance(gres,dict):
    print("STATUS gate_unknown"); raise SystemExit(0)
if str(first(gres,"runId","run_id") or "") != RUN_ID:
    print("STATUS gate_untrusted"); raise SystemExit(0)
gcount=gres.get("count")
if not is_int(gcount) or gcount<0:
    print("STATUS gate_unknown"); raise SystemExit(0)
gates=gres.get("gates")
if not isinstance(gates,list):
    print("STATUS gate_unknown"); raise SystemExit(0)
gate_task={}
for row in gates:
    if not isinstance(row,dict):
        print("STATUS gate_unknown"); raise SystemExit(0)
    gid=str(first(row,"id","gateId","gate_id") or "")
    gtask=str(first(row,"task_id","taskId","task") or "")
    gstatus=str(first(row,"status") or "")
    if not gid or not gtask or gstatus!="pending":
        print("STATUS gate_unknown"); raise SystemExit(0)
    if gid in gate_task:
        print("STATUS gate_duplicate"); raise SystemExit(0)
    gate_task[gid]=gtask
if gcount != len(gate_task):
    print("STATUS gate_unknown"); raise SystemExit(0)
# inbox 스냅샷: 최상위 ok=true, result 모양, count 필수이며 0 이상 정수. 전 행은
# 목록 완전성을 증명하는 id, run_id, type 을 필수로 갖춰야 한다(A3). count 와
# 실제 행 수는 같아야 하고, 둘 중 하나라도 전용 한도에 닿으면 포화다 — 오래된
# 정확한 편지가 잘렸을 수 있어 편지 부재를 확정하지 못한다(A4). count 누락·
# 불일치도 wake 0 이다.
idoc=load(parts[1])
if not isinstance(idoc,dict):
    print("STATUS inbox_unknown"); raise SystemExit(0)
if idoc.get("ok") is not True:
    print("STATUS inbox_untrusted"); raise SystemExit(0)
ires=idoc.get("result")
if not isinstance(ires,dict):
    print("STATUS inbox_unknown"); raise SystemExit(0)
icount=ires.get("count")
if not is_int(icount) or icount<0:
    print("STATUS inbox_unknown"); raise SystemExit(0)
messages=ires.get("messages")
if not isinstance(messages,list):
    print("STATUS inbox_unknown"); raise SystemExit(0)
for row in messages:
    if not isinstance(row,dict):
        print("STATUS inbox_unknown"); raise SystemExit(0)
    if not str(first(row,"id","message_id","messageId") or ""):
        print("STATUS inbox_unknown"); raise SystemExit(0)
    if not str(first(row,"run_id","runId") or ""):
        print("STATUS inbox_unknown"); raise SystemExit(0)
    if not str(first(row,"type") or ""):
        print("STATUS inbox_unknown"); raise SystemExit(0)
if icount != len(messages):
    print("STATUS inbox_unknown"); raise SystemExit(0)
if max(icount,len(messages)) >= LIMIT:
    print("STATUS inbox_saturated"); raise SystemExit(0)
counts={}
for message in messages:
    if str(first(message,"run_id","runId") or "") != SUPER: continue
    if str(first(message,"type") or "") != "decision_gate": continue
    payload=first(message,"payload")
    if isinstance(payload,str):
        try: payload=json.loads(payload)
        except Exception: continue
    if not isinstance(payload,dict): continue
    gid=str(first(payload,"gateId","gate_id") or "")
    if not gid or gid not in gate_task: continue
    # pane+handle 결속(C9): 발신 (sender_pane_key, from_handle) 이 같은 roster 행의
    # 권위 쌍과 정확히 맞아야 하고, 수신 주소는 정확한 슈퍼 Run 이어야 한다.
    sender_pane=str(first(message,"sender_pane_key","senderPaneKey") or "")
    from_handle=str(first(message,"from_handle","fromHandle") or "")
    if (sender_pane,from_handle) not in PAIRS: continue
    if str(first(message,"to_handle","toHandle") or "") != "run:"+SUPER: continue
    # 공식 decision_gate payload 는 gateId, project, board, sourceTaskId 를 모두
    # 필수로 갖고 해당 관문의 id/project/board/task 와 정확히 일치해야 한다(C11).
    # 누락은 대응 편지가 아니다. 제목·본문 키워드·고정 handle은 근거가 아니다.
    if str(first(payload,"project") or "") != PROJECT: continue
    if str(first(payload,"board") or "") != BOARD: continue
    if str(first(payload,"sourceTaskId","sourceTask","taskId") or "") != gate_task[gid]: continue
    counts[gid]=counts.get(gid,0)+1
if len(gate_task)==0:
    print("STATUS empty"); raise SystemExit(0)
print("STATUS ok")
for gid in gate_task:
    valid=counts.get(gid,0)
    if valid==0:
        print("NUDGE "+gid)
    elif valid>1:
        print("AMBIGUOUS "+gid)
' 2>/dev/null || printf '%s\n' "STATUS unknown"
}
emit_gate_nudge() {
  local gate_id="$1" signal caller text
  signal="GATE_NUDGE gate=$gate_id run=$SUPER_RUN_ID"
  echo "$signal"
  if ! refresh_supervisor_handle; then
    echo "GATE_NUDGE_WAKE_FAIL gate=$gate_id reason=roster_$RESOLVE_REASON wake=0"
    return 0
  fi
  caller="${ORCA_TERMINAL_HANDLE:-}"
  if [ -z "$caller" ] || [ "$caller" != "$SUPERVISOR_HANDLE" ]; then
    echo "GATE_NUDGE_WAKE_FAIL gate=$gate_id reason=owner_mismatch wake=0"
    return 0
  fi
  text="[ORCA_INBOX_WAKE] $signal project Run에 pending 결정 관문이 있지만 슈퍼 Run에 대응하는 공식 decision_gate 편지가 없습니다. 슈퍼 Run에 이 관문의 decision_gate 편지를 보내세요. companion이 편지를 대신 만들거나 관문 상태를 바꾸지 않습니다."
  if ! "$ORCA_BIN" terminal send --terminal "$SUPERVISOR_HANDLE" --text "$text" --json >/dev/null 2>&1; then
    echo "GATE_NUDGE_TEXT_FAIL gate=$gate_id text_ok=0 wake=0 retry_possible=1"
    return 0
  fi
  if ! "$ORCA_BIN" terminal send --terminal "$SUPERVISOR_HANDLE" --enter --json >/dev/null 2>&1; then
    echo "GATE_NUDGE_ENTER_FAIL gate=$gate_id text_ok=1 wake=0 retry_possible=1"
    return 0
  fi
  SEEN_GATE_NUDGE_KEYS="$SEEN_GATE_NUDGE_KEYS$gate_id|"
  log_relay_event "gate_nudge gate=$gate_id run=$SUPER_RUN_ID wake=1"
  return 0
}
handle_gate_nudge_check() {
  [ -n "$SUPER_RUN_ID" ] || return 0
  if [ "$SUPER_RUN_ID_VERIFIED" != "$SUPER_RUN_ID" ]; then
    log_relay_event "gate_nudge_suppressed reason=super_run_unverified wake=0"
    return 0
  fi
  local analysis gate_nudge_status line gid
  analysis=$(gate_nudge_analyze)
  gate_nudge_status=$(printf '%s\n' "$analysis" | sed -n 's/^STATUS //p' | head -1)
  case "$gate_nudge_status" in
    ok) ;;
    empty) return 0 ;;
    *) log_relay_event "gate_nudge_suppressed reason=${gate_nudge_status:-unknown} wake=0"; return 0 ;;
  esac
  while IFS= read -r line; do
    case "$line" in
      NUDGE\ *)
        gid="${line#NUDGE }"
        if has_key "$SEEN_GATE_NUDGE_KEYS" "$gid"; then
          echo "GATE_NUDGE_DUPLICATE gate=$gid wake=0"
        else
          emit_gate_nudge "$gid"
        fi
        ;;
      AMBIGUOUS\ *)
        log_relay_event "gate_nudge_ambiguous gate=${line#AMBIGUOUS } wake=0"
        ;;
    esac
  done <<< "$analysis"
  return 0
}
send_text_then_enter() {
  local handle="$1" text="$2"
  "$ORCA_BIN" terminal send --terminal "$handle" --text "$text" --json >/dev/null 2>&1 || return 1
  "$ORCA_BIN" terminal send --terminal "$handle" --enter --json >/dev/null 2>&1 || return 1
}
emit_signal() {
  local signal_line="$1" wake_instruction="${2:-판 상태를 확인하고 중복 카드 없이 처리하세요.}"
  echo "$signal_line"
  refresh_supervisor_handle || {
    echo "WAKE_FAIL roster_resolve role=$SUPERVISOR_ROLE reason=$RESOLVE_REASON"
    return 1
  }
  CALLER_TERMINAL_HANDLE="${ORCA_TERMINAL_HANDLE:-}"
  if [ -z "$CALLER_TERMINAL_HANDLE" ] || [ "$CALLER_TERMINAL_HANDLE" != "$SUPERVISOR_HANDLE" ]; then
    echo "CHECK_DIAGNOSTIC consumer_owner_mismatch expected=$SUPERVISOR_HANDLE actual=${CALLER_TERMINAL_HANDLE:-missing}"
    return 1
  fi
  send_text_then_enter "$SUPERVISOR_HANDLE" "[ORCA_INBOX_WAKE] $signal_line $wake_instruction" || {
    echo "WAKE_FAIL $SUPERVISOR_HANDLE"
    return 1
  }
}
log_relay_event() {
  local event="$1" timestamp
  timestamp=$(date "+%Y-%m-%d %H:%M:%S %z")
  echo "$event"
  [ -n "$RELAY_LOG_FILE" ] || return 0
  mkdir -p "$(dirname "$RELAY_LOG_FILE")" 2>/dev/null || return 1
  printf '%s|%s\n' "$timestamp" "$event" >> "$RELAY_LOG_FILE" || return 1
}
decode_b64() {
  local value="$1"
  printf '%s' "$value" | base64 --decode 2>/dev/null || printf '%s' "$value" | base64 -D 2>/dev/null || true
}
# B6 선두 차단 제거의 핵심. 처리하지 못하는 편지 한 통은 그 편지만 격리하고 큐는 계속
# 흐른다. 격리는 조용한 폐기가 아니다 — stdout 표식과 relay 로그에 반드시 남긴다
# (막지도 말고 삼키지도 않는다). 호출한 쪽은 이어서 SEEN 처리하고 다음 편지로 넘어간다.
quarantine_message() {
  local q_id="$1" q_type="$2" q_sender="$3" q_reason="$4" q_task="${5:-}" q_dispatch="${6:-}"
  log_relay_event "message_quarantined message=$q_id type=$q_type sender=$q_sender reason=$q_reason task=${q_task:-missing} dispatch=${q_dispatch:-missing} blocked_queue=0"
}
# B11: 편지 ID 자체가 없거나 문자열이 아닌 편지는 중복 억제 키를 만들 수 없어 일반 격리
# 경로(quarantine_message)에 태울 수 없다. 그 한 통만 여기서 격리하고 큐는 계속 흐른다.
# 깨우지 않는다(불량 편지로 감독을 깨우면 그것이 오히려 위장 신호다). 대신 조용히 버리지도
# 않는다 — stdout 과 relay 로그에 type·배달 안 위치·이유를 남긴다. 원문(제목·본문·payload)은
# 남기지 않는다.
# 중복 경계: 같은 Delivery(deliveryId) 안 같은 위치의 같은 이유는 1회만 남긴다. ack 이
# 실패해 같은 Delivery 가 재생돼도 진단이 무한 반복되지 않는다. 이 경계는 일반 lifecycle
# 중복 상태와 마찬가지로 프로세스 메모리 한정이며 재시작을 넘지 않는다.
#
# F-B11-2: 여기서 끝내면 진단은 파일에 "써지기만" 하고 아무도 "읽지" 않는다(R-F-B11 중요1).
# 그래서 같은 처리 경로 안에서 project Run 으로 구조화 편지 1통을 올린다. 새 감시 프로세스는
# 만들지 않는다.
# deliveryId 는 원문 해시(deliveryRef)로만 싣는다. 제목·본문·payload·taskId·dispatchId 는
# 절대 싣지 않는다.
delivery_ref() {
  printf '%s' "${1:-missing}" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:12])' 2>/dev/null || printf 'unhashed'
}
# F-B11-3: 알림에 실리는 값은 발신자가 고른 자유 문자열이 아니라 고정 목록 안의 토큰이어야
# 한다. 생산자(여기)와 소비자(끝단 검증)가 같은 목록을 쓰므로, 목록 밖 값은 알림에 실리지도
# 않고 실려 오더라도 인정되지 않는다. 카드가 명시한 message_id_* 5종은 이 목록의 부분집합이고,
# 같은 생산자(parse_delivery)가 만드는 나머지 4종도 함께 고정한다 — 목록을 5종으로만 좁히면
# 진짜 companion 이 만든 sender_missing 알림이 위조로 오인돼 wake 0 이 된다.
SHAPE_REASON_ALLOWED="message_id_empty message_id_missing message_id_null message_id_type message_id_unsafe message_not_object sender_missing type_missing payload_shape"
SHAPE_TYPE_ALLOWED="worker_done escalation decision_gate question ask status relay_candidate heartbeat unknown"
in_word_list() {
  local needle="$1" list="$2" item
  [ -n "$needle" ] || return 1
  for item in $list; do [ "$item" = "$needle" ] && return 0; done
  return 1
}
report_shape_quarantine() {
  local q_delivery="$1" q_index="$2" q_type="$3" q_reason="$4" ref subject body payload
  [ -n "$PROJECT_RUN_ID" ] || return 0
  ref=$(delivery_ref "$q_delivery")
  in_word_list "$q_type" "$SHAPE_TYPE_ALLOWED" || q_type=unknown
  in_word_list "$q_reason" "$SHAPE_REASON_ALLOWED" || q_reason=unknown
  case "$q_index" in ''|*[!0-9]*) q_index=0 ;; esac
  subject="message_shape_quarantined:$BOARD"
  # 본문에는 카드 식별자 낱말(taskId/dispatchId/deliveryId)조차 쓰지 않는다. 끝단 검증이
  # "본문에 원문 필드 낱말이 있으면 위조"로 판정하기 때문이다(원문 밀반입 차단).
  body="companion이 우편함에서 모양이 깨진 편지 1통을 격리했습니다. 원문(제목·본문·payload·카드 식별자)은 싣지 않습니다. board=$BOARD deliveryRef=$ref index=$q_index type=$q_type reason=$q_reason. 정상 형제 편지는 그대로 처리했고 큐는 막히지 않았습니다. 사람 판단 요청이 아니라 구조 이상 알림이므로, 발신자가 구조화된 편지를 다시 보내게 하세요."
  payload="{\"messageShapeQuarantined\":true,\"board\":\"$BOARD\",\"deliveryRef\":\"$ref\",\"index\":\"$q_index\",\"messageType\":\"$q_type\",\"reason\":\"$q_reason\"}"
  "$ORCA_BIN" orchestration send --run "$PROJECT_RUN_ID" --subject "$subject" \
    --body "$body" --type escalation --payload "$payload" --json >/dev/null 2>&1 || return 1
  echo "MESSAGE_SHAPE_REPORT_SENT board=$BOARD deliveryRef=$ref index=$q_index type=$q_type reason=$q_reason"
}
# 반환 0 = 이 편지의 진단 처리가 끝났다(ack 해도 된다).
# 반환 1 = 상신을 아직 못 했다. 호출한 쪽은 Delivery 를 ack 하지 않고 다음 배달에서 다시
# 시도한다(정상 형제는 이미 이 주기에 처리됐고 SEEN 으로 재깨우기가 막힌다).
quarantine_shape() {
  local q_delivery="${1:-missing}" q_index="${2:-unknown}" q_type="${3:-unknown}" q_reason="${4:-unknown}" shape_key report_key
  shape_key="$q_delivery:$q_index:$q_reason"
  if ! has_key "$SEEN_MALFORMED_SHAPE" "$shape_key"; then
    SEEN_MALFORMED_SHAPE="$SEEN_MALFORMED_SHAPE$shape_key|"
    log_relay_event "message_shape_quarantined delivery=$q_delivery index=$q_index type=$q_type reason=$q_reason wake=0 blocked_queue=0"
  fi
  report_key="shape_report:$shape_key"
  has_key "$SEEN_SHAPE_REPORTS" "$report_key" && return 0
  if report_shape_quarantine "$q_delivery" "$q_index" "$q_type" "$q_reason"; then
    SEEN_SHAPE_REPORTS="$SEEN_SHAPE_REPORTS$report_key|"
    return 0
  fi
  # 조용히 넘기지 않는다: 실패 사실을 stdout 진단과 relay 로그에 남기고 재시도한다.
  diagnose_check_once shape_report_send_failed
  log_relay_event "message_shape_report_failed delivery=$q_delivery index=$q_index reason=$q_reason retry=pending"
  if note_wake_failure "$report_key"; then
    # 재시도 한도 소진. 무한 재시도로 큐를 영구히 잡아두지 않는다. 포기 사실도 남긴다.
    SEEN_SHAPE_REPORTS="$SEEN_SHAPE_REPORTS$report_key|"
    log_relay_event "message_shape_report_exhausted delivery=$q_delivery index=$q_index reason=$q_reason attempts=$MAX_WAKE_ATTEMPTS"
    # F-B11-3: 여기서 멈추면 "상신조차 못 했다"는 더 중요한 사실이 파일에만 남는다(소비자 0).
    # 상신 채널이 완전히 막혔으므로 편지가 아닌 독립 경로(감독 terminal)로 정확히 1회 알린다.
    # 편지를 새로 만들지 않으므로 알림이 알림을 부르는 재귀 고리가 생기지 않는다.
    emergency_shape_wake "$(delivery_ref "$q_delivery")" "$q_reason" || true
    return 0
  fi
  return 1
}
# F-B11-3 비상 경로. 싣는 값은 board 와 고정 목록 안의 reason, 그리고 deliveryRef 뿐이다.
# 원 malformed 원문·taskId·dispatchId·deliveryId 원문은 넣지 않는다.
shape_emergency_instruction() {
  printf '%s' "구조 이상 알림을 project Run 편지로 올리지 못해 재시도 한도에서 포기했습니다. 원문은 싣지 않았습니다. 우편함 상신 경로를 직접 확인하세요."
}
emergency_shape_wake() {
  local ref="${1:-unavailable}" reason="${2:-unknown}" key
  in_word_list "$reason" "$SHAPE_REASON_ALLOWED" || reason=unknown
  case "$ref" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; *) ref=unavailable ;; esac
  key="emergency:$ref:$reason"
  has_key "$SEEN_SHAPE_EMERGENCY" "$key" && return 0
  if emit_signal "SIGNAL message_shape_report_exhausted board=$BOARD deliveryRef=$ref reason=$reason" "$(shape_emergency_instruction)"; then
    SEEN_SHAPE_EMERGENCY="$SEEN_SHAPE_EMERGENCY$key|"
    log_relay_event "shape_report_exhausted_wake board=$BOARD deliveryRef=$ref reason=$reason wake=1"
    return 0
  fi
  # 직접 깨우기도 실패했다. 조용히 숨기지 않는다: 다음 자가점검이 읽는 고정 상태 파일에
  # fail-closed 상태로 남긴다(소비 계약은 consume_shape_emergency_state 가 진다).
  echo "CHECK_DIAGNOSTIC shape_emergency_wake_failed ref=$ref reason=$reason"
  log_relay_event "shape_report_exhausted_wake_failed board=$BOARD deliveryRef=$ref reason=$reason wake=0 fail_closed=1"
  [ -n "$SHAPE_EMERGENCY_STATE_FILE" ] || return 1
  mkdir -p "$(dirname "$SHAPE_EMERGENCY_STATE_FILE")" 2>/dev/null || return 1
  printf 'pending|%s|%s\n' "$ref" "$reason" >> "$SHAPE_EMERGENCY_STATE_FILE" 2>/dev/null || return 1
  return 1
}
# F-B11-3 소비 계약. 매 주기 자가점검이 고정 상태 파일을 읽고, 아직 회수되지 않은 pending
# 이 있으면 그 사실을 드러낸 뒤 비상 깨우기를 다시 시도한다. 성공하면 같은 파일에
# recovered 로 닫는다. 새 프로세스도, 새 편지도 만들지 않는다.
consume_shape_emergency_state() {
  [ -n "$SHAPE_EMERGENCY_STATE_FILE" ] || return 0
  [ -f "$SHAPE_EMERGENCY_STATE_FILE" ] || return 0
  local content kind ref reason key
  content=$(cat "$SHAPE_EMERGENCY_STATE_FILE" 2>/dev/null) || return 0
  [ -n "$content" ] || return 0
  while IFS='|' read -r kind ref reason; do
    [ "$kind" = pending ] || continue
    key="emergency:$ref:$reason"
    has_key "$SEEN_SHAPE_EMERGENCY" "$key" && continue
    case "$content" in *"recovered|$ref|$reason"*) SEEN_SHAPE_EMERGENCY="$SEEN_SHAPE_EMERGENCY$key|"; continue ;; esac
    echo "CHECK_DIAGNOSTIC shape_emergency_wake_pending ref=$ref reason=$reason"
    if emit_signal "SIGNAL message_shape_report_exhausted board=$BOARD deliveryRef=$ref reason=$reason" "$(shape_emergency_instruction)"; then
      SEEN_SHAPE_EMERGENCY="$SEEN_SHAPE_EMERGENCY$key|"
      printf 'recovered|%s|%s\n' "$ref" "$reason" >> "$SHAPE_EMERGENCY_STATE_FILE" 2>/dev/null || true
      log_relay_event "shape_report_exhausted_wake board=$BOARD deliveryRef=$ref reason=$reason wake=1 recovered=1"
    fi
  done <<< "$content"
  return 0
}
# 같은 편지에 대한 깨우기 실패 횟수를 1 늘리고, 재시도 여력이 남았는지 알려준다.
# 반환 0(참) = 재시도 소진. 반환 1(거짓) = 아직 Delivery 재시도로 다시 시도할 수 있다.
note_wake_failure() {
  local msg="$1" tally
  WAKE_FAIL_ATTEMPTS="$WAKE_FAIL_ATTEMPTS$msg|"
  tally=$(printf '%s' "$WAKE_FAIL_ATTEMPTS" | tr '|' '\n' | grep -c -x -F -- "$msg")
  [ "${tally:-0}" -ge "$MAX_WAKE_ATTEMPTS" ]
}
# 깨우기 실패 처리 한 곳. 재시도 여력이 남았으면 1(=Delivery 재시도, 큐 유지)을 돌려주고,
# 소진했으면 그 편지만 격리한 뒤 0(=다음 편지로 진행)을 돌려준다.
on_wake_failure() {
  local msg="$1" mtype="$2" msender="$3" mtask="${4:-}" mdispatch="${5:-}"
  note_wake_failure "$msg" || return 1
  quarantine_message "$msg" "$mtype" "$msender" wake_failed_exhausted "$mtask" "$mdispatch"
  return 0
}
# worker_done_auto 원장 기록(P3B R4 중요1/2). 편지의 실제 taskId/dispatchId 와
# PROJECT_RUN_ID 를 쓰고, roster list 에서 handle+pane 으로 후보를 먼저 유일 선택한 뒤
# 공식 필드·형식으로 엄격 검사하고, task-list 공식 필드·상태 집합을 고정해 roundId 를
# 결정적으로 도출한다.
# reviewer/reviewer-* 는 deps 정확히 1개일 때 roundId=deps[0].
# developer/developer-*/researcher/researcher-*/investigator/investigator-* 는 roundId=task.id.
# 공식 필드/상태만 허용: 별칭(run_id/runId 교차 사용, camelCase)과 문자열 live/상태는 거부.
record_worker_done_ledger() {
  local wd_task="$1" wd_dispatch="$2" wd_sender="$3"
  [ -n "$PROJECT_RUN_ID" ] || return 0
  [ -n "$wd_task" ] || [ -n "$wd_dispatch" ] || return 0
  local SCRIPT_HERE; SCRIPT_HERE="$(cd "$(dirname "$0")" && pwd)"
  # (a) dispatch-show: 권위 발령 영수증(R4: 공식 snake_case 필드·completed 상태만).
  local ds_out
  ds_out=$( "$ORCA_BIN" orchestration dispatch-show --task "$wd_task" --json 2>/dev/null ) || ds_out=""
  # (b) task-list: 전체 응답 fail-closed 검증(R4 중요2).
  local tl_out
  tl_out=$( "$ORCA_BIN" orchestration task-list --run "$PROJECT_RUN_ID" --json 2>/dev/null ) || tl_out=""
  # (c) roster list: --role 없이 전체 active 멤버를 가져온다(R4 중요1).
  local rl_out
  rl_out=$( "$ORCA_BIN" roster list --project "$PROJECT" --board "$BOARD" --run "$PROJECT_RUN_ID" --status active --json 2>/dev/null ) || rl_out=""
  # (d) 종합 검증: dispatch-show + task-list + roster → roundId 도출 또는 격리 사유.
  local wd_result
  wd_result=$( DS_OUT="$ds_out" TL_OUT="$tl_out" RL_OUT="$rl_out" \
    TASK_ID="$wd_task" DISPATCH_ID="$wd_dispatch" RUN_ID="$PROJECT_RUN_ID" \
    PROJECT="$PROJECT" BOARD="$BOARD" SENDER="$wd_sender" python3 - <<'PYLEDGER' 2>/dev/null
import json, os, re, sys
tid = os.environ["TASK_ID"]; did = os.environ["DISPATCH_ID"]
rid = os.environ["RUN_ID"]; sender = os.environ["SENDER"]
proj = os.environ["PROJECT"]; board = os.environ["BOARD"]
TASK_ID_RE = re.compile(r"^task_[0-9a-f]{8,}$")
def emit(s): print(s); sys.exit(0)

# --- dispatch-show 검증 (R4 인접: 공식 snake_case, completed 상태만) ---
try:
    d = (json.loads(os.environ.get("DS_OUT", "")).get("result") or {}).get("dispatch") or {}
except Exception:
    d = {}
ds_id = str(d.get("id") or "")
ds_task = str(d.get("task_id") or "")
ds_run = str(d.get("run_id") or "")
ds_status = str(d.get("status") or "")
ds_assignee = str(d.get("assignee_handle") or "")
ds_pane = str(d.get("assignee_pane_key") or "")
if not (re.fullmatch(r"ctx_[0-9a-f]{8,}", ds_id) and ds_id == did
        and ds_task == tid and ds_run == rid):
    emit("FAIL\tdispatch_show_id_mismatch")
if ds_status != "completed":
    emit("FAIL\tdispatch_not_completed")
if ds_assignee != sender:
    emit("FAIL\tassignee_sender_mismatch")
if not ds_pane:
    emit("FAIL\tdispatch_missing_assignee_pane")

# --- roster list: handle+pane 으로 원시 후보를 먼저 유일 선택 (R4 중요1) ---
try:
    rl_root = json.loads(os.environ.get("RL_OUT", ""))
except Exception:
    rl_root = {}
if rl_root.get("ok") is not True:
    emit("FAIL\troster_list_ok_not_true")
rl_result = rl_root.get("result") or {}
rl_members = rl_result.get("members")
if not isinstance(rl_members, list):
    emit("FAIL\troster_list_no_members")
# R4 중요1: 공식 currentHandle + pane 으로 원시 후보를 먼저 고른다(별칭 없음).
# project/board/run 신분의 쌍둥이도 이 단계에서 후보 수에 포함되어 복수로 닫혀야 한다.
raw_candidates = []
for m in rl_members:
    if not isinstance(m, dict):
        emit("FAIL\troster_member_not_dict")
    mh = str(m.get("currentHandle") or "")
    mp = str(m.get("pane") or "")
    if mh == sender and mp == ds_pane and mh and mp:
        raw_candidates.append(m)
if len(raw_candidates) == 0:
    emit("FAIL\troster_no_matching_worker")
if len(raw_candidates) > 1:
    emit("FAIL\troster_multiple_matching_workers:" + str(len(raw_candidates)))
# R4 중요1: 정확히 한 후보에 대해서만 공식 필드를 누락 불가로 엄격 검사.
w = raw_candidates[0]
def check_field(obj, key, expected, fail_reason):
    val = obj.get(key)
    if val is None:
        emit("FAIL\t" + fail_reason + ":missing_" + key)
    if str(val) != expected:
        emit("FAIL\t" + fail_reason + ":" + key + "_mismatch")
check_field(w, "project", proj, "roster")
check_field(w, "board", board, "roster")
check_field(w, "runId", rid, "roster")
check_field(w, "status", "active", "roster")
check_field(w, "lifecycle", "active", "roster")
# live 는 Python bool True 만 허용(문자열 true/yes/1 거부).
if w.get("live") is not True:
    emit("FAIL\troster_live_not_true:" + repr(w.get("live"))[:60])
role = str(w.get("role") or "")
if not role:
    emit("FAIL\troster_member_missing_role")
is_reviewer = role == "reviewer" or role.startswith("reviewer-")
is_dev = (role == "developer" or role.startswith("developer-")
          or role == "researcher" or role.startswith("researcher-")
          or role == "investigator" or role.startswith("investigator-"))
if not (is_reviewer or is_dev):
    emit("FAIL\tunrecognized_role:" + role[:80])

# --- task-list 전체 필수 검증 (R4 중요2: 공식 필드·상태 집합) ---
try:
    root = json.loads(os.environ.get("TL_OUT", ""))
except Exception:
    root = {}
if root.get("ok") is not True:
    emit("FAIL\ttask_list_ok_not_true")
result = root.get("result")
if not isinstance(result, dict):
    emit("FAIL\ttask_list_result_not_object")
# R4 중요2: 공식 result.runId 만 허용(별칭 run_id 단독은 거부).
resp_run = result.get("runId")
if not isinstance(resp_run, str) or resp_run != rid:
    emit("FAIL\ttask_list_runId_missing_or_mismatch")
count = result.get("count")
if not isinstance(count, int) or isinstance(count, bool) or count < 0:
    emit("FAIL\ttask_list_count_invalid")
tasks = result.get("tasks")
if not isinstance(tasks, list):
    emit("FAIL\ttask_list_no_tasks")
if count != len(tasks):
    emit("FAIL\ttask_list_count_mismatch")
# R4 중요2: 공식 Orca Task 상태 6개만 허용.
ALLOWED_STATUS = {"pending", "ready", "dispatched", "completed", "failed", "blocked"}
by_id = {}
parsed_deps = {}
for t in tasks:
    if not isinstance(t, dict):
        emit("FAIL\ttask_list_row_not_dict")
    cid = t.get("id")
    if not isinstance(cid, str) or not TASK_ID_RE.fullmatch(cid):
        emit("FAIL\ttask_list_row_bad_id:" + str(cid)[:80])
    if cid in by_id:
        emit("FAIL\ttask_list_duplicate_id")
    # R4 중요2: 공식 행 run_id 만 허용(별칭 runId 단독은 거부).
    trun = t.get("run_id")
    if not isinstance(trun, str) or trun != rid:
        emit("FAIL\ttask_list_row_run_id_missing_or_mismatch:" + cid)
    tstatus = str(t.get("status") or "")
    if tstatus not in ALLOWED_STATUS:
        emit("FAIL\ttask_list_row_bad_status:" + str(tstatus)[:80])
    raw_deps = t.get("deps")
    if not isinstance(raw_deps, str):
        emit("FAIL\ttask_list_row_deps_not_string:" + cid)
    try:
        dep_list = json.loads(raw_deps)
    except (ValueError, TypeError):
        emit("FAIL\ttask_list_row_deps_bad_json:" + cid)
    if not isinstance(dep_list, list):
        emit("FAIL\ttask_list_row_deps_not_array:" + cid)
    norm_deps = []
    for dep in dep_list:
        if not isinstance(dep, str) or not TASK_ID_RE.fullmatch(dep):
            emit("FAIL\ttask_list_row_deps_bad_element:" + cid)
        norm_deps.append(dep)
    if len(norm_deps) != len(set(norm_deps)):
        emit("FAIL\ttask_list_row_deps_duplicate:" + cid)
    by_id[cid] = t
    parsed_deps[cid] = norm_deps
for cid, dlist in parsed_deps.items():
    for dep in dlist:
        if dep not in by_id:
            emit("FAIL\ttask_list_broken_dep_ref:" + cid + "->" + dep)

# --- 역할 기반 roundId 도출 ---
target = by_id.get(tid)
if not isinstance(target, dict):
    emit("FAIL\ttarget_not_in_task_list")
tdeps = parsed_deps.get(tid, [])
if is_reviewer:
    if len(tdeps) != 1:
        emit("FAIL\treviewer_deps_not_one")
    emit("OK\t" + tdeps[0])
else:
    emit("OK\t" + tid)
PYLEDGER
  ) || wd_result="FAIL\tinternal_error"
  local wd_status="${wd_result%%$'\t'*}"
  local wd_detail="${wd_result#*$'\t'}"
  if [[ "$wd_status" == "OK" ]]; then
    local pay="{\"taskId\":\"$wd_task\",\"dispatchId\":\"$wd_dispatch\",\"sender\":\"$wd_sender\"}"
    "$SCRIPT_HERE/routing-ledger-append.sh" worker_done_auto "$BOARD" "$wd_task" "$pay" --run-id "$PROJECT_RUN_ID" --round-id "$wd_detail" --dispatch-id "$wd_dispatch" 2>/dev/null || true
  else
    "$SCRIPT_HERE/routing-ledger-append.sh" worker_done_auto "$BOARD" "$wd_task" "{\"taskId\":\"$wd_task\",\"dispatchId\":\"$wd_dispatch\",\"sender\":\"$wd_sender\"}" --run-id "$PROJECT_RUN_ID" --dispatch-id "$wd_dispatch" --quarantine-reason "$wd_detail" 2>/dev/null || true
  fi
}




parse_delivery() {
  BOARD="$BOARD" SHAPE_REASON_ALLOWED="$SHAPE_REASON_ALLOWED" SHAPE_TYPE_ALLOWED="$SHAPE_TYPE_ALLOWED" python3 -c '
import base64,json,os,re,sys
U="\x1c"
# B11: 편지 하나의 모양이 깨졌다고 Delivery 전체를 거부하면, 그 뒤에 있는 정상 편지까지
# 같이 막혀 감독이 안 깨어난다(선두 차단). 그래서 delivery 봉투 자체가 깨진 경우만
# 전체 실패로 두고, 편지 한 통의 모양 결함은 그 한 통만 MALFORMED 행으로 격리한다.
ID_KEYS=("id","messageId","message_id")
# messageId 는 중복 억제 키의 재료다. 아래 문자는 셸 쪽 키 구분자(|)와 행/필드 구분자라
# 키를 오염시키므로 정상 ID 로 인정하지 않는다.
BAD_ID_CHARS=("|","\x1c","\n","\r")
def resolve_message_id(message):
    # 비어 있지 않은 문자열만 정상 키로 인정한다. 빈값·누락·null·객체·배열·숫자·불리언은
    # 문자열화하지 않고 이유를 붙여 돌려준다.
    reason=""
    for name in ID_KEYS:
        if name not in message: continue
        value=message[name]
        if value is None:
            reason=reason or "message_id_null"; continue
        if not isinstance(value,str):
            reason=reason or "message_id_type"; continue
        if not value.strip():
            reason=reason or "message_id_empty"; continue
        if any(bad in value for bad in BAD_ID_CHARS):
            reason=reason or "message_id_unsafe"; continue
        return value, ""
    return None, (reason or "message_id_missing")
def safe_type(message):
    # 격리 진단에 남길 type 은 원문 비밀이 아니라 형식 표식이다. 토큰만 남긴다.
    if not isinstance(message,dict): return "unknown"
    raw=message.get("type")
    if not isinstance(raw,str): return "unknown"
    return re.sub(r"[^A-Za-z0-9_.:-]","_",raw.strip())[:40] or "unknown"
# F-B11-3: companion 이 스스로 만든 구조 알림의 정확한 schema 만 인정한다.
# 돌려주는 값은 고정 어휘의 거부 사유 토큰이며 원문은 절대 섞지 않는다(빈 값 = 인정).
SHAPE_BOARD=os.environ.get("BOARD","")
SHAPE_REASON_OK=set((os.environ.get("SHAPE_REASON_ALLOWED") or "").split())
SHAPE_TYPE_OK=set((os.environ.get("SHAPE_TYPE_ALLOWED") or "").split())
SHAPE_PAYLOAD_KEYS={"messageShapeQuarantined","board","deliveryRef","index","messageType","reason"}
SHAPE_RAW_FIELD_WORDS=("taskId","task_id","dispatchId","dispatch_id","deliveryId","delivery_id")
SHAPE_CARD_KEYS=("taskId","task_id","dispatchId","dispatch_id")
def shape_alert_reject(message,payload,marker):
    if marker is not True: return "marker_not_bool"
    if not SHAPE_BOARD: return "board_unknown"
    if str(message.get("type") or "") != "escalation": return "not_escalation"
    if str(message.get("subject") or "") != "message_shape_quarantined:"+SHAPE_BOARD: return "subject_mismatch"
    if set(payload.keys()) != SHAPE_PAYLOAD_KEYS: return "payload_keys"
    for name in SHAPE_CARD_KEYS:
        if message.get(name) is not None: return "card_identifiers_present"
    board=payload.get("board"); ref=payload.get("deliveryRef"); index=payload.get("index")
    mtype=payload.get("messageType"); reason=payload.get("reason")
    if not isinstance(board,str) or board != SHAPE_BOARD: return "board_mismatch"
    if not isinstance(ref,str) or not re.fullmatch(r"[0-9a-f]{12}",ref): return "ref_format"
    if not isinstance(index,str) or not re.fullmatch(r"0|[1-9][0-9]{0,8}",index): return "index_format"
    if not isinstance(mtype,str) or mtype not in SHAPE_TYPE_OK: return "message_type_not_allowed"
    if not isinstance(reason,str) or reason not in SHAPE_REASON_OK: return "reason_not_allowed"
    body=message.get("body")
    if not isinstance(body,str) or not body.strip(): return "body_shape"
    for word in SHAPE_RAW_FIELD_WORDS:
        if word in body: return "body_raw_field"
    if "board=%s deliveryRef=%s index=%s type=%s reason=%s" % (board,ref,index,mtype,reason) not in body:
        return "body_binding"
    return ""
try:
    root=json.load(sys.stdin)
    result=root.get("result") or {}
    messages=result.get("messages") or []
    delivery_id=result.get("deliveryId") or result.get("delivery_id")
    if not delivery_id:
        if messages: raise ValueError("delivery_shape")
        print("EMPTY"); raise SystemExit(0)
    if not isinstance(messages,list): raise ValueError("delivery_shape")
    rows=[]
    for message_index, message in enumerate(messages):
        shape_reason=""
        message_id=None; sender=None; message_type=""; payload={}
        if not isinstance(message,dict):
            shape_reason="message_not_object"
        else:
            message_id, shape_reason=resolve_message_id(message)
        if not shape_reason:
            sender=message.get("from") or message.get("sender") or message.get("fromHandle") or message.get("from_handle") or message.get("senderHandle") or message.get("sender_handle")
            if not isinstance(sender,str) or not sender.strip(): shape_reason="sender_missing"
        if not shape_reason:
            raw_type=message.get("type")
            if not isinstance(raw_type,str) or not raw_type.strip(): shape_reason="type_missing"
            else: message_type=raw_type
        if not shape_reason:
            payload=message.get("payload") or {}
            if isinstance(payload,str):
                try: payload=json.loads(payload)
                except Exception: shape_reason="payload_shape"
            if not shape_reason and not isinstance(payload,dict): shape_reason="payload_shape"
        if shape_reason:
            # 원문(제목·본문·payload)은 싣지 않는다. type·배달 안 위치·이유만 넘긴다.
            rows.append("MALFORMED"+U+shape_reason+U+safe_type(message)+U+str(message_index))
            continue
        task_id=message.get("taskId") or message.get("task_id") or payload.get("taskId") or payload.get("task_id")
        dispatch_id=message.get("dispatchId") or message.get("dispatch_id") or payload.get("dispatchId") or payload.get("dispatch_id")
        upper=payload.get("upperReport")
        if upper is None: upper=payload.get("upper_report")
        upper_report="true" if upper is True or str(upper).strip().lower()=="true" else ""
        super_reply=payload.get("superReply")
        if super_reply is None: super_reply=payload.get("super_reply")
        super_reply="true" if super_reply is True or str(super_reply).strip().lower()=="true" else ""
        target_run_id=payload.get("targetRunId") or payload.get("target_run_id") or ""
        candidate=payload.get("relayCandidate")
        if candidate is None: candidate=payload.get("relay_candidate")
        if candidate is None: candidate=payload.get("candidate")
        kind=payload.get("kind") or payload.get("candidateKind") or payload.get("candidate_kind")
        is_candidate="true" if message_type in ("relay_candidate","relay-candidate") or candidate is True or str(candidate).strip().lower()=="true" or str(kind) in ("relay_candidate","relay-candidate","human_decision_candidate") else ""
        ambiguous=payload.get("contextAmbiguous")
        if ambiguous is None: ambiguous=payload.get("context_ambiguous")
        if ambiguous is None: ambiguous=payload.get("timeAmbiguous")
        if ambiguous is None: ambiguous=payload.get("time_ambiguous")
        candidate_ambiguous="true" if ambiguous is True or str(ambiguous).strip().lower()=="true" else ""
        cursor=payload.get("outputCursor") or payload.get("output_cursor") or payload.get("supervisorOutputCursor") or payload.get("supervisor_output_cursor") or payload.get("cursor") or ""
        snippet=payload.get("boundedSnippet") or payload.get("bounded_snippet") or payload.get("snippet") or payload.get("summary") or ""
        def short(value,limit=120):
            return re.sub(r"\s+"," ",str(value or "")).replace(U," ").strip()[:limit]
        def b64(value): return base64.urlsafe_b64encode(short(value,240).encode()).decode()
        error_code=short(payload.get("errorCode") or payload.get("error_code"),80)
        effects=payload.get("effectsApplied")
        if effects is None: effects=payload.get("effects_applied")
        effects_applied="false" if effects is False or str(effects).strip().lower()=="false" else ""
        outcome=short(payload.get("outcome"),80)
        next_action=short(payload.get("nextAction") or payload.get("next_action"),80)
        state_sources=[payload]
        for state_key in ("boardState","board_state","state","observation","snapshot","statusDetails","status_details"):
            nested=payload.get(state_key)
            if isinstance(nested,dict): state_sources.append(nested)
        def first(names):
            for source in state_sources:
                for name in names:
                    if name in source and source[name] is not None:
                        return source[name]
            return None
        def bool_text(raw):
            if raw is None: return ""
            if isinstance(raw,bool): return "true" if raw else "false"
            value=str(raw).strip().lower()
            if value in ("true","1","yes"): return "true"
            if value in ("false","0","no"): return "false"
            return ""
        ready_raw=first(("readyCardPresent","ready_card_present","readyPresent","ready_present"))
        if ready_raw is None:
            ready_cards=first(("readyCards","ready_cards","readyTasks","ready_tasks"))
            if isinstance(ready_cards,list): ready_raw=len(ready_cards)>0
        if ready_raw is None:
            ready_count=first(("readyCardCount","ready_card_count","readyTaskCount","ready_task_count"))
            if ready_count is not None:
                try: ready_raw=int(ready_count)>0
                except Exception: ready_raw=None
        ready_present=bool_text(ready_raw)
        active_absent_raw=first(("activeDispatchAbsent","active_dispatch_absent"))
        if active_absent_raw is None:
            active_count=first(("activeDispatchCount","active_dispatch_count"))
            if active_count is not None:
                try: active_absent_raw=int(active_count)==0
                except Exception: active_absent_raw=None
        if active_absent_raw is None:
            active_dispatches=first(("activeDispatches","active_dispatches"))
            if isinstance(active_dispatches,list): active_absent_raw=len(active_dispatches)==0
        active_dispatch_absent=bool_text(active_absent_raw)
        coordinator_idle_raw=first(("coordinatorIdle","coordinator_idle"))
        if coordinator_idle_raw is None:
            coordinator_state=first(("coordinatorState","coordinator_state","coordinatorStatus","coordinator_status"))
            if coordinator_state is not None: coordinator_idle_raw=str(coordinator_state).strip().lower()=="idle"
        coordinator_idle=bool_text(coordinator_idle_raw)
        board_closed_raw=first(("boardClosed","board_closed","closed"))
        board_status=first(("boardStatus","board_status"))
        if board_closed_raw is None and board_status is not None:
            board_closed_raw=str(board_status).strip().lower() in ("closed","done","finished","completed","ended")
        board_closed=bool_text(board_closed_raw)
        gate_waiting_raw=first(("gateWaiting","gate_waiting","waitingForGate","waiting_for_gate","decisionGateWaiting","decision_gate_waiting"))
        if gate_waiting_raw is None:
            gate_state=first(("gateState","gate_state"))
            if gate_state is not None: gate_waiting_raw=str(gate_state).strip().lower() in ("waiting","pending","blocked")
        gate_waiting=bool_text(gate_waiting_raw)
        start_raw=first(("startDeclaration","start_declaration","openingDeclaration","opening_declaration"))
        start_declaration=bool_text(start_raw)
        declaration_kind=first(("declarationKind","declaration_kind","kind","event","phase","status","boardStatus","board_status"))
        if start_declaration != "true" and str(declaration_kind or "").strip().lower() in ("start","started","starting","opening","board_start","board-start","start_declaration","start-declaration","started_declaration","started-declaration"):
            start_declaration="true"
        fingerprint=first(("stateFingerprint","state_fingerprint","fingerprint"))
        def token(value):
            return re.sub(r"[^A-Za-z0-9_.:-]","_",str(value or "").strip())[:120]
        # stateFingerprint 가 없으면 어떤 기본값도 합성하지 않는다.
        # 빈 지문은 NUDGE/MISSING_RELAY handler 에서 wake 0 fail-closed 로 처리된다.
        # 합성 지문은 서로 다른 불완전한 상태를 같은 가짜 지문으로 합쳐 중복 억제를
        # 잘못 일으킬 수 있으므로 원본 값만 정규화해 전달한다.
        fingerprint=token(fingerprint)
        is_board_observation="true" if start_declaration == "true" or ready_present != "" or active_dispatch_absent != "" or coordinator_idle != "" else ""
        # F-B11-2: companion 이 올린 모양 결함 알림 편지를 끝단에서 알아본다. 이 표식이
        # 붙은 편지는 카드 보고가 아니므로 taskId/dispatchId 가 없는 것이 정상이다.
        shape_alert_raw=payload.get("messageShapeQuarantined")
        if shape_alert_raw is None: shape_alert_raw=payload.get("message_shape_quarantined")
        shape_alert="true" if shape_alert_raw is True or str(shape_alert_raw).strip().lower()=="true" else ""
        # F-B11-3: 표식 주장(shape_alert)은 넓게 잡되, 인정(shape_reject 없음)은 좁게 준다.
        # 넓게 잡는 이유: 표식만 흉내 낸 escalation 을 여기서 안 잡으면 아래 lifecycle 분기로
        # 흘러 오히려 그대로 감독을 깨운다. 좁게 주는 이유: companion 이 스스로 만든 편지의
        # 정확한 schema 만 구조 알림으로 인정한다. 하나라도 어긋나면 거부 사유 토큰을 남긴다.
        shape_reject=""
        if shape_alert == "true":
            shape_reject=shape_alert_reject(message,payload,shape_alert_raw)
        body=short(message.get("subject") or message.get("body"),120)
        sender_pane_key=short(str(message.get("sender_pane_key") or message.get("senderPaneKey") or message.get("from_pane_key") or message.get("fromPaneKey") or ""),240)
        fields=(message_id,message_type,sender,task_id,dispatch_id,b64(body),upper_report,
                outcome,next_action,error_code,effects_applied,is_candidate,short(cursor,80),
                b64(snippet),candidate_ambiguous,super_reply,short(target_run_id,120),
                sender_pane_key,start_declaration,ready_present,active_dispatch_absent,
                coordinator_idle,board_closed,gate_waiting,fingerprint,is_board_observation,
                shape_alert,shape_reject)
        rows.append("MESSAGE"+U+U.join(str(x or "") for x in fields))
    print("DELIVERY|"+str(delivery_id))
    for row in rows: print(row)
except ValueError as error:
    print("ERROR|"+str(error))
except Exception:
    print("ERROR|delivery_shape")
'
}

project_ledger_state() {
  local task_id="$1" dispatch_id="$2" candidate_ambiguous="${3:-}" data state
  if [ "$candidate_ambiguous" = true ]; then echo ambiguous; return 0; fi
  # B6: gate 조회와 같은 이유로 자기 project Run 우편함으로 좁힌다. 여기는 포화 판정조차
  # 없어서 더 위험하다 — 전역 창이 다른 판 편지로 차면 실제로 있는 공식 편지가 창 밖으로
  # 밀려 "없음"으로 보이고, 그 결과 misrouted_human_decision 오경보로 감독을 깨운다.
  # 아래 python 의 run_id 대조는 그대로 남겨 범위가 안 좁혀졌을 때도 잘못 세지 않게 한다.
  data=$( "$ORCA_BIN" orchestration inbox --full --terminal "run:$PROJECT_RUN_ID" --limit "$LEDGER_SCAN_LIMIT" --json 2>/dev/null ) || {
    echo unknown
    return 0
  }
  state=$(printf '%s' "$data" | env TASK_ID="$task_id" DISPATCH_ID="$dispatch_id" PROJECT_RUN_ID="$PROJECT_RUN_ID" python3 -c '
import json,os,sys
try:
    messages=(json.load(sys.stdin).get("result") or {}).get("messages")
    if not isinstance(messages,list): raise ValueError
except Exception:
    print("unknown"); raise SystemExit(0)
task_id=os.environ["TASK_ID"]; dispatch_id=os.environ["DISPATCH_ID"]; project_run=os.environ["PROJECT_RUN_ID"]
matches=0
for message in messages:
    if not isinstance(message,dict): continue
    run_id=str(message.get("run_id") or message.get("runId") or "")
    if run_id != project_run: continue
    message_type=str(message.get("type") or "")
    if message_type not in {"decision_gate","ask","question","escalation"}: continue
    payload=message.get("payload") or {}
    if isinstance(payload,str):
        try: payload=json.loads(payload)
        except Exception: payload={}
    if not isinstance(payload,dict): payload={}
    relay_candidate=payload.get("relayCandidate")
    if relay_candidate is None: relay_candidate=payload.get("relay_candidate")
    generated=payload.get("misroutedHumanDecision")
    if generated is None: generated=payload.get("misrouted_human_decision")
    subject=str(message.get("subject") or "")
    if str(relay_candidate).lower()=="true" or str(generated).lower()=="true" or subject.startswith("misrouted_human_decision:"):
        continue
    message_task=str(message.get("taskId") or message.get("task_id") or payload.get("taskId") or payload.get("task_id") or "")
    message_dispatch=str(message.get("dispatchId") or message.get("dispatch_id") or payload.get("dispatchId") or payload.get("dispatch_id") or "")
    if message_task==task_id and message_dispatch==dispatch_id:
        matches += 1
        if matches > 1:
            print("ambiguous"); raise SystemExit(0)
print("present" if matches==1 else "absent")
')
  case "$state" in present|absent|ambiguous|unknown) echo "$state" ;; *) echo unknown ;; esac
}

request_relay_context() {
  local message_id="$1" task_id="$2" dispatch_id="$3" output_cursor="$4" snippet="$5"
  refresh_relay_handle || {
    log_relay_event "relay_context_request_failed message=$message_id task=${task_id:-missing} dispatch=${dispatch_id:-missing} reason=roster_$RESOLVE_REASON"
    return 1
  }
  snippet=$(printf '%s' "$snippet" | python3 -c 'import re,sys; print(re.sub(r"\s+"," ",sys.stdin.read()).strip()[:240])')
  local text="[RELAY_CONTEXT_REQUIRED] candidate message=$message_id taskId=${task_id:-missing} dispatchId=${dispatch_id:-missing} outputCursor=${output_cursor:-missing} boundedSnippet=$snippet. Only this bounded snippet may be reconsidered; do not send full output or scrollback. Report a new structured relay_candidate with corrected IDs and cursor."
  send_text_then_enter "$RELAY_HANDLE" "$text" || {
    log_relay_event "relay_context_request_failed message=$message_id task=${task_id:-missing} dispatch=${dispatch_id:-missing} reason=terminal_send"
    return 1
  }
  log_relay_event "relay_context_requested message=$message_id task=${task_id:-missing} dispatch=${dispatch_id:-missing} cursor=${output_cursor:-missing} wake=1"
}

handle_relay_candidate() {
  local message_id="$1" task_id="$2" dispatch_id="$3" body="$4" output_cursor="$5" snippet="$6" candidate_ambiguous="$7"
  local candidate_key pair_key ledger_state subject project_body
  if [ -n "$task_id" ] && [ -n "$dispatch_id" ] && [ -n "$output_cursor" ]; then
    candidate_key="$task_id:$dispatch_id:$output_cursor"
  else
    candidate_key="message:$message_id"
  fi
  if has_key "$SEEN_CANDIDATE_KEYS" "$candidate_key"; then
    echo "RELAY_CANDIDATE_DUPLICATE task=${task_id:-missing} dispatch=${dispatch_id:-missing} cursor=${output_cursor:-missing} wake=0"
    return 0
  fi
  if [ -z "$task_id" ] || [ -z "$dispatch_id" ]; then
    request_relay_context "$message_id" "$task_id" "$dispatch_id" "$output_cursor" "${snippet:-$body}" || return 1
    SEEN_CANDIDATE_KEYS="$SEEN_CANDIDATE_KEYS$candidate_key|"
    return 0
  fi
  ledger_state=$(project_ledger_state "$task_id" "$dispatch_id" "$candidate_ambiguous")
  case "$ledger_state" in
    present)
      pair_key="$task_id:$dispatch_id"
      if has_key "$LATE_RECOVERED_KEYS" "$pair_key"; then
        echo "RELAY_CANDIDATE_DUPLICATE task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing} wake=0"
      else
        LATE_RECOVERED_KEYS="$LATE_RECOVERED_KEYS$pair_key|"
        log_relay_event "late_recovered task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing} wake=0"
      fi
      SEEN_CANDIDATE_KEYS="$SEEN_CANDIDATE_KEYS$candidate_key|"
      ;;
    ambiguous|unknown)
      request_relay_context "$message_id" "$task_id" "$dispatch_id" "$output_cursor" "${snippet:-$body}" || return 1
      SEEN_CANDIDATE_KEYS="$SEEN_CANDIDATE_KEYS$candidate_key|"
      ;;
    absent)
      pair_key="$task_id:$dispatch_id"
      subject="misrouted_human_decision:$task_id"
      project_body="relay가 bounded supervisor 출력에서 사람 판단 후보를 구조화해 보냈지만 같은 taskId+dispatchId의 공식 project Run decision_gate/ask/escalation 편지를 찾지 못했습니다. 카드 상태는 바꾸지 말고 현재 project supervisor가 후보와 장부를 확인하세요. dispatchId=$dispatch_id outputCursor=${output_cursor:-missing} boundedSnippet=${snippet:-$body}"
      if ! has_key "$MISROUTED_SENT_KEYS" "$pair_key"; then
        "$ORCA_BIN" orchestration send --run "$PROJECT_RUN_ID" --subject "$subject" --body "$project_body" --type escalation --task-id "$task_id" --dispatch-id "$dispatch_id" --payload '{"misroutedHumanDecision":true}' --json >/dev/null 2>&1 || {
          log_relay_event "misrouted_human_decision_send_failed task=$task_id dispatch=$dispatch_id reason=project_run_send wake=0"
          return 1
        }
        MISROUTED_SENT_KEYS="$MISROUTED_SENT_KEYS$pair_key|"
        echo "MISROUTED_HUMAN_DECISION_SENT subject=$subject task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing}"
      fi
      if ! has_key "$MISROUTED_WAKE_KEYS" "$pair_key"; then
        emit_signal "MISROUTED_HUMAN_DECISION task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing}" "project Run의 공식 장부에 같은 taskId+dispatchId 편지가 없어서 확인이 필요합니다. 후보 의미를 키워드로 재판정하지 마세요." || {
          log_relay_event "misrouted_human_decision_wake_failed task=$task_id dispatch=$dispatch_id reason=supervisor_send"
          return 1
        }
        MISROUTED_WAKE_KEYS="$MISROUTED_WAKE_KEYS$pair_key|"
        log_relay_event "misrouted_human_decision task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing} wake=1"
      else
        echo "MISROUTED_DUPLICATE task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing} wake=0"
      fi
      SEEN_CANDIDATE_KEYS="$SEEN_CANDIDATE_KEYS$candidate_key|"
      ;;
    *)
      log_relay_event "project_ledger_check_failed task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing} state=$ledger_state"
      return 1
      ;;
  esac
}

diagnose_check_once() {
  local kind="$1"
  [ "$CHECK_DIAGNOSTIC" = "$kind" ] && return 0
  CHECK_DIAGNOSTIC="$kind"
  echo "CHECK_DIAGNOSTIC $kind"
}
# keepalive JSON 한 줄에서 elapsedMs 만 뽑는다. 파싱 실패면 빈칸(마커는 여전히 나간다).
keepalive_elapsed_ms() {
  printf '%s' "$1" | sed -n 's/.*"elapsedMs" *: *\([0-9][0-9]*\).*/\1/p' | head -1
}
# 우편함 확인 한 단계. --wait 지원이면 편지 도착까지 막고 기다리며, 대기 중 오는
# _keepalive 를 실시간 COMPANION_ALIVE 마커로 바꾼다. 미지원·fifo 실패면 폴백으로 즉시
# 확인하되 COMPANION_WAIT_FALLBACK 로그를 반드시 남긴다(조용한 강등 금지).
# 결과: OUT(stdout 본문), CHECK_STATUS(종료코드), DID_WAIT_THIS_CYCLE(진짜 대기했으면 1).
run_mail_step() {
  DID_WAIT_THIS_CYCLE=0
  CHECK_STATUS=0
  if [ "$WAIT_CAPABLE" != 1 ]; then
    if [ "$WAIT_FALLBACK_LOGGED" = 0 ]; then
      WAIT_FALLBACK_LOGGED=1
      echo "COMPANION_WAIT_FALLBACK reason=wait_help_absent poll_interval=$POLL_INTERVAL"
    fi
    OUT=$( "$ORCA_BIN" orchestration check --run "$PROJECT_RUN_ID" --json 2>&1 )
    CHECK_STATUS=$?
    return
  fi
  local now remaining wait_ms wait_dir stdout_file kalive_fifo reader_pid
  now=$(date +%s)
  remaining=$(( NEXT_KICKER - now ))
  [ "$remaining" -lt 1 ] && remaining=1
  wait_ms=$(( remaining * 1000 ))
  [ "$wait_ms" -lt "$WAIT_MIN_MS" ] && wait_ms=$WAIT_MIN_MS
  [ "$wait_ms" -gt "$WAIT_MAX_MS" ] && wait_ms=$WAIT_MAX_MS
  wait_dir=$(mktemp -d "${TMPDIR:-/tmp}/companion_wait.XXXXXX")
  stdout_file="$wait_dir/stdout"
  kalive_fifo="$wait_dir/keepalive.fifo"
  if ! mkfifo "$kalive_fifo" 2>/dev/null; then
    echo "COMPANION_WAIT_FALLBACK reason=fifo_create_failed poll_interval=$POLL_INTERVAL"
    WAIT_FALLBACK_LOGGED=1
    OUT=$( "$ORCA_BIN" orchestration check --run "$PROJECT_RUN_ID" --json 2>&1 )
    CHECK_STATUS=$?
    return
  fi
  # 실시간 keepalive -> COMPANION_ALIVE. "막혀서 대기 중"과 "죽어서 조용함"이 구분된다.
  # fifo 를 읽는 쪽이 먼저 열리면 기다리고, check 가 쓰기 쪽을 열 때 만나 스트림이 시작된다.
  while IFS= read -r kline; do
    case "$kline" in
      *'"_keepalive"'*|*'"_heartbeat"'*)
        echo "COMPANION_ALIVE mode=wait elapsed_ms=$(keepalive_elapsed_ms "$kline") wait_ms=$wait_ms"
        ;;
    esac
  done <"$kalive_fifo" &
  reader_pid=$!
  if [ -n "$WAIT_TYPES" ]; then
    "$ORCA_BIN" orchestration check --run "$PROJECT_RUN_ID" --wait \
      --types "$WAIT_TYPES" --timeout-ms "$wait_ms" --json \
      2>"$kalive_fifo" >"$stdout_file"
  else
    "$ORCA_BIN" orchestration check --run "$PROJECT_RUN_ID" --wait \
      --timeout-ms "$wait_ms" --json \
      2>"$kalive_fifo" >"$stdout_file"
  fi
  CHECK_STATUS=$?
  wait "$reader_pid" 2>/dev/null || true
  OUT=$(cat "$stdout_file")
  if [ "$CHECK_STATUS" -eq 0 ]; then
    DID_WAIT_THIS_CYCLE=1
    echo "COMPANION_WAITED wait_ms=$wait_ms check_status=0"
  else
    # 즉시 오류는 실제 대기가 아니다. 호출부가 poll 간격만큼 쉬도록 0을 유지한다.
    DID_WAIT_THIS_CYCLE=0
    echo "COMPANION_WAIT_FAILED wait_ms=$wait_ms check_status=$CHECK_STATUS"
  fi
}

process_delivery() {
  local delivery="$1" delivery_id="${2:-missing}"
  local record message_id message_type sender task_id dispatch_id summary_b64 upper_report outcome next_action error_code effects_applied
  local super_reply target_run_id
  local is_candidate output_cursor snippet_b64 candidate_ambiguous summary snippet event_key seen_key malformed_key relay_now
  local shape_reason shape_type shape_index
  local is_lifecycle is_structured_upper is_super_reply is_lifecycle_error
  local sender_pane_key
  local start_declaration ready_present active_dispatch_absent coordinator_idle board_closed gate_waiting fingerprint is_board_observation shape_alert shape_reject shape_verdict
  DELIVERY_OK=1
  while IFS=$'\034' read -r record message_id message_type sender task_id dispatch_id summary_b64 upper_report outcome next_action error_code effects_applied is_candidate output_cursor snippet_b64 candidate_ambiguous super_reply target_run_id sender_pane_key start_declaration ready_present active_dispatch_absent coordinator_idle board_closed gate_waiting fingerprint is_board_observation shape_alert shape_reject; do
    if [ "$record" = MALFORMED ]; then
      # MALFORMED 행에는 편지 본체가 없다. 자리 뜻만 다르게 읽는다:
      # 1번칸=이유, 2번칸=type, 3번칸=Delivery 안 위치.
      shape_reason="$message_id"; shape_type="$message_type"; shape_index="$sender"
      # F-B11-2: 상신을 못 하면 이 Delivery 는 ack 하지 않아 다음 배달에서 다시 시도한다.
      # 그래도 큐를 세우지 않는다 — 같은 배달의 정상 형제는 이 주기에 계속 처리한다(break 금지).
      quarantine_shape "$delivery_id" "$shape_index" "$shape_type" "$shape_reason" || DELIVERY_OK=0
      continue
    fi
    [ "$record" = MESSAGE ] || continue
    # B11: 앞단 중복 필터의 단위는 뒤쪽 event_key 와 같아야 한다. messageId 만 보면
    # 같은 ID 를 가진 다른 생명주기 type 편지(question 뒤 escalation)가 여기서 막혀
    # 두 번째 편지가 영영 감독을 못 깨운다. type+messageId 를 한 편지의 신분으로 쓴다.
    seen_key="$message_type:$message_id"
    has_key "$SEEN_IDS" "$seen_key" && continue
    summary=$(decode_b64 "$summary_b64")
    # F-B11-2 소비 끝단: companion 이 올린 모양 결함 알림이 우편함으로 돌아왔다. 여기서
    # 감독을 정확히 1회 깨우고 끝낸다. 이 분기는 어떤 편지도 새로 보내지 않으므로
    # 알림이 알림을 부르는 재귀 고리가 생기지 않는다. 카드 보고가 아니라서
    # taskId/dispatchId 가 없는 것이 정상이므로 아래 식별자 검사에 걸리지 않게 먼저 받는다.
    if [ "$shape_alert" = true ]; then
      event_key="shape_alert:$message_id"
      if ! has_key "$SEEN_EVENT_KEYS" "$event_key"; then
        # F-B11-3 출처 검증. schema 가 통과해도 발신자가 지금 이 판의 project-supervisor
        # 신분이 아니면 인정하지 않는다. 캐시된 옛 handle 이 아니라 이 자리에서 roster 를
        # 다시 조회해(live=true 확인 포함) 현재 handle+pane 한 쌍과 정확히 대조한다.
        shape_verdict="$shape_reject"
        if [ -z "$shape_verdict" ]; then
          if refresh_supervisor_handle; then
            if [ -z "$SUPERVISOR_HANDLE" ] || [ "$sender" != "$SUPERVISOR_HANDLE" ]; then
              shape_verdict=sender_handle_mismatch
            elif [ -z "$SUPERVISOR_PANE" ]; then
              shape_verdict=roster_pane_missing
            elif [ -z "$sender_pane_key" ]; then
              shape_verdict=sender_pane_missing
            elif [ "$sender_pane_key" != "$SUPERVISOR_PANE" ]; then
              shape_verdict=sender_pane_mismatch
            fi
          else
            shape_verdict="roster_$RESOLVE_REASON"
          fi
        fi
        if [ -n "$shape_verdict" ]; then
          # 위조이거나 불명확하다: 깨우지 않는다. 큐는 막지 않게 ack 하되 조용히 버리지도
          # 않는다. 진단에는 고정 어휘의 거부 사유만 남기고 원문·발신자 문자열은 싣지 않는다.
          log_relay_event "forged_or_untrusted_shape_alert board=$BOARD reason=$shape_verdict wake=0 blocked_queue=0"
          SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
          SEEN_IDS="$SEEN_IDS$seen_key|"
          continue
        fi
        emit_signal "SIGNAL message_shape_quarantined sender=$sender message=$message_id summary=$summary" "우편함에서 모양이 깨진 편지 1통이 격리됐습니다. 원문은 싣지 않았습니다. 정상 형제 편지는 이미 처리됐으니, 발신자에게 구조화된 편지를 다시 보내게 하세요." || {
          on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
          DELIVERY_OK=0
          break
        }
        SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
      fi
      SEEN_IDS="$SEEN_IDS$seen_key|"
      continue
    fi
    if [ "$is_candidate" = true ]; then
      snippet=$(decode_b64 "$snippet_b64")
      handle_relay_candidate "$message_id" "$task_id" "$dispatch_id" "$summary" "$output_cursor" "$snippet" "$candidate_ambiguous" || {
        on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
        DELIVERY_OK=0
        break
      }
      SEEN_IDS="$SEEN_IDS$seen_key|"
      continue
    fi

    is_lifecycle=0
    case "$message_type" in worker_done|escalation|decision_gate|question|ask) is_lifecycle=1 ;; esac
    is_structured_upper=0
    [ "$message_type" = status ] && [ "$upper_report" = true ] && is_structured_upper=1
    is_super_reply=0
    [ "$message_type" = status ] && [ "$super_reply" = true ] && [ -n "$target_run_id" ] && is_super_reply=1
    is_lifecycle_error=0
    if [ -n "$error_code" ] || [ "$effects_applied" = false ]; then is_lifecycle_error=1; fi
    if [ "$is_lifecycle" -eq 0 ] && [ "$is_structured_upper" -eq 0 ] && [ "$is_super_reply" -eq 0 ] && [ "$is_lifecycle_error" -eq 0 ]; then
      # 일반 status 분기 우선순위: (1) Track G 판 상태 관찰(NUDGE/MISSING_RELAY),
      # (2) 권위가 검증된 슈퍼 지시, (3) 그 밖은 wake 0 으로 ack.
      if [ "$is_board_observation" = true ]; then
        if [ "$start_declaration" = true ]; then
          handle_start_declaration "$message_id" "$fingerprint" "$board_closed" "$gate_waiting" || {
            on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
            DELIVERY_OK=0
            break
          }
        fi
        if [ "$ready_present" != "" ] || [ "$active_dispatch_absent" != "" ] || [ "$coordinator_idle" != "" ]; then
          handle_nudge_observation "$fingerprint" "$ready_present" "$active_dispatch_absent" "$coordinator_idle" "$board_closed" "$gate_waiting" || {
            on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
            DELIVERY_OK=0
            break
          }
        fi
      fi
      # 진짜 슈퍼감독 지시는 매 조회 시점 run-show 가 돌려준 안정된 창 신분과 정확히
      # 맞을 때만 인정한다. 요청한 --super-run 과 같은 run.id, 비어 있지 않은
      # coordinator_handle 과 coordinator_pane_key, 그리고 메시지의 from_handle 과
      # sender_pane_key 가 각각 그 둘과 정확히 일치해야 한다. pane 없는 메시지나 pane
      # 없는 run-show 응답은 wake 0 이다. 고정 handle·제목·본문·payload 는 인증 근거가
      # 아니다. 같은 판 worker/reviewer/relay 의 ID 포함 status 는 여기서 잡히지 않고
      # wake 0 으로 ack 된다. 실제 권위 super status 는 taskId/dispatchId 가 없어도
      # messageId 단위로 정확히 1회 wake 한다. 인수 전 발신 편지는 소급 인증하지 않는다
      # (coordinator 교대 후 다음 동적 조회부터 새 coordinator 에만 대조).
      if [ -n "$SUPER_COORDINATOR_HANDLE" ] && [ -n "$SUPER_COORDINATOR_PANE" ] && [ "$sender" = "$SUPER_COORDINATOR_HANDLE" ] && [ -n "$sender_pane_key" ] && [ "$sender_pane_key" = "$SUPER_COORDINATOR_PANE" ]; then
        event_key="super_directive:$message_id"
        if ! has_key "$SEEN_EVENT_KEYS" "$event_key"; then
          emit_signal "SIGNAL super_directive sender=$sender message=$message_id summary=$summary" "슈퍼 Run coordinator가 보낸 지시 status입니다. 내용을 확인하세요." || {
            on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
            DELIVERY_OK=0
            break
          }
          SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
        fi
      fi
      SEEN_IDS="$SEEN_IDS$seen_key|"
      continue
    fi

    # Track G: 판 상태 관찰이 실린 status 는 lifecycle 오류가 아닐 때 먼저 관찰로 처리한다.
    # lifecycle 자동 원장(worker_done)과 malformed 격리는 아래 단계에 그대로 남는다.
    if [ "$is_lifecycle_error" -eq 0 ] && [ "$is_board_observation" = true ]; then
      if [ "$start_declaration" = true ]; then
        handle_start_declaration "$message_id" "$fingerprint" "$board_closed" "$gate_waiting" || {
          on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
          DELIVERY_OK=0
          break
        }
      fi
      if [ "$ready_present" != "" ] || [ "$active_dispatch_absent" != "" ] || [ "$coordinator_idle" != "" ]; then
        handle_nudge_observation "$fingerprint" "$ready_present" "$active_dispatch_absent" "$coordinator_idle" "$board_closed" "$gate_waiting" || {
          on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
          DELIVERY_OK=0
          break
        }
      fi
      if [ "$is_structured_upper" -eq 0 ] && [ "$is_super_reply" -eq 0 ]; then
        SEEN_IDS="$SEEN_IDS$seen_key|"
        continue
      fi
      if [ -z "$task_id" ] || [ -z "$dispatch_id" ]; then
        SEEN_IDS="$SEEN_IDS$seen_key|"
        continue
      fi
    fi

    # B6: 슈퍼감독 지시는 카드 생명주기 보고가 아니다. 지시에는 taskId/dispatchId 가
    # 없는 것이 정상이므로, 그 두 값이 없다는 이유로 아래 식별자 검사에서 불량 처리하면
    # 안 된다 — 그것이 2026-08-09 판 11시간 정지의 직접 원인이었다(슈퍼가 보내는
    # type=escalation 지시가 매번 큐 앞을 막았다).
    # 지시로 인정하는 기준은 형식(type)이 아니라 발신자 권위다: 매 주기 run-show 로
    # 동적 조회한 지정 슈퍼 Run 의 현재 coordinator handle 과 pane key 에 발신자의
    # from_handle 과 sender_pane_key 가 각각 정확히 일치할 때만 지시다. handle 만 같고
    # pane 이 다르거나 pane 이 없으면 사칭이므로 인정하지 않고 원래 분류로 떨어진다.
    # 값을 코드에 박지 않으며, coordinator 교대 후 다음 동적 조회부터 새 coordinator 에만
    # 대조한다. 일반 status 는 위 분기에서 이미 처리되므로 여기 오는 것은 lifecycle
    # (escalation/ask/decision_gate/question/worker_done)과 상위보고/오류 형식이다.
    if [ "$is_super_reply" -eq 0 ] \
      && [ -n "$SUPER_COORDINATOR_HANDLE" ] && [ -n "$SUPER_COORDINATOR_PANE" ] \
      && [ "$sender" = "$SUPER_COORDINATOR_HANDLE" ] \
      && [ -n "$sender_pane_key" ] && [ "$sender_pane_key" = "$SUPER_COORDINATOR_PANE" ]; then
      event_key="super_directive:$message_id"
      if ! has_key "$SEEN_EVENT_KEYS" "$event_key"; then
        emit_signal "SIGNAL super_directive sender=$sender message=$message_id summary=$summary" "슈퍼 Run coordinator가 보낸 지시입니다. 카드 보고가 아니므로 taskId/dispatchId가 없는 것이 정상입니다. 내용을 확인하세요." || {
          on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
          DELIVERY_OK=0
          break
        }
        SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
      fi
      SEEN_IDS="$SEEN_IDS$seen_key|"
      continue
    fi

    if [ "$is_super_reply" -eq 0 ] && { [ -z "$task_id" ] || [ -z "$dispatch_id" ] || { [ "$is_structured_upper" -eq 1 ] && { [ -z "$outcome" ] || [ -z "$next_action" ]; }; }; }; then
      malformed_key="malformed:$message_id"
      if ! has_key "$SEEN_MALFORMED" "$malformed_key"; then
        SEEN_MALFORMED="$SEEN_MALFORMED$malformed_key|"
        emit_signal "MALFORMED_LIFECYCLE_REPORT type=$message_type sender=$sender message=$message_id summary=$summary" "식별자가 빠진 보고는 상태에 적용하지 않았습니다. taskId+dispatchId를 갖춘 구조화 보고를 다시 보내세요." || {
          on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { quarantine_message "$message_id" "$message_type" "$sender" malformed_lifecycle_report "$task_id" "$dispatch_id"; SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
          DELIVERY_OK=0
          break
        }
      fi
      # B6: 여기서 큐를 세우지 않는다. 이 편지 한 통만 격리하고 다음 편지로 넘어간다.
      # 격리 사실은 quarantine_message 가 stdout 과 relay 로그에 남기므로 조용한 폐기가
      # 아니다.
      quarantine_message "$message_id" "$message_type" "$sender" malformed_lifecycle_report "$task_id" "$dispatch_id"
      SEEN_IDS="$SEEN_IDS$seen_key|"
      continue
    fi

    if [ "$is_lifecycle_error" -eq 1 ]; then
      event_key="lifecycle_error:$task_id:$dispatch_id"
      if has_key "$SEEN_EVENT_KEYS" "$event_key"; then SEEN_IDS="$SEEN_IDS$seen_key|"; continue; fi
      emit_signal "LIFECYCLE_ERROR type=$message_type sender=$sender task=$task_id dispatch=$dispatch_id code=${error_code:-effectsApplied=false} summary=$summary" "같은 명령을 무작정 재시도하지 말고 pending 보고를 확인하세요." || {
        on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
        DELIVERY_OK=0
        break
      }
      SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
      SEEN_IDS="$SEEN_IDS$seen_key|"
      continue
    fi

    if [ "$is_structured_upper" -eq 1 ]; then
      event_key="status_upper:$task_id:$dispatch_id"
      if has_key "$SEEN_EVENT_KEYS" "$event_key"; then SEEN_IDS="$SEEN_IDS$seen_key|"; continue; fi
      emit_signal "SIGNAL status_upper sender=$sender task=$task_id dispatch=$dispatch_id outcome=$outcome next=$next_action summary=$summary" "상위 보고의 outcome과 nextAction을 확인하세요." || {
        on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
        DELIVERY_OK=0
        break
      }
      SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
      SEEN_IDS="$SEEN_IDS$seen_key|"
      continue
    fi

    if [ "$is_super_reply" -eq 1 ]; then
      event_key="super_reply:$message_id"
      if has_key "$SEEN_EVENT_KEYS" "$event_key"; then SEEN_IDS="$SEEN_IDS$seen_key|"; continue; fi
      emit_signal "SIGNAL super_reply sender=$sender message=$message_id targetRunId=$target_run_id summary=$summary" "슈퍼 Run의 정상 답장을 확인하세요." || {
        on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
        DELIVERY_OK=0
        break
      }
      SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
      SEEN_IDS="$SEEN_IDS$seen_key|"
      continue
    fi

    # B11: task+dispatch는 한 발령 안의 여러 새 편지가 공유하므로 중복 신분이 아니다.
    # 런타임이 부여한 messageId가 같은 편지를 다시 본 경우에만 깨우기를 억제한다.
    # 같은 messageId라도 type이 다르면 서로 다른 편지이므로 각각 1회 깨운다. 그래서
    # 앞단 seen 키(seen_key)와 이 event 키는 반드시 같은 단위(type+messageId)를 쓴다.
    # 같은 발령의 서로 다른 worker_done 보고(worker_done_1/2)도 각각 1회 깨운다(B11).
    # 단, 완료 원장(record_worker_done_ledger)은 task+dispatch 단위로 1줄이다 — 같은
    # 카드의 완료를 두 줄 쓰면 두 번 정산된다. 깨우기(messageId)와 원장(task+dispatch)의
    # 단위가 다르므로 원장 쓰기만 아래에서 task+dispatch 로 한 번 더 중복 제거한다.
    event_key="$seen_key"
    if has_key "$SEEN_EVENT_KEYS" "$event_key"; then SEEN_IDS="$SEEN_IDS$seen_key|"; continue; fi
    if [ "$message_type" = worker_done ]; then
      refresh_relay_handle || true
      relay_now="$RELAY_HANDLE"
      if [ -n "$relay_now" ] && [ "$sender" = "$relay_now" ]; then
        # relay 가 보낸 worker_done 은 실제 작업 완료가 아니다(계약 3): 본 원장 0줄 +
        # 격리 진단으로 끝낸다. relay_card taskId 는 실제 패턴이 아니라 자동 격리된다.
        "$(dirname "$0")/routing-ledger-append.sh" worker_done_auto "$BOARD" "$task_id" \
          "{\"taskId\":\"$task_id\",\"dispatchId\":\"$dispatch_id\",\"sender\":\"$sender\"}" \
          --quarantine-reason "relay_worker_done_not_real_completion" 2>/dev/null || true
       SEEN_IDS="$SEEN_IDS$seen_key|"; continue
     fi
      # 완료 원장은 task+dispatch 당 1줄이다. 같은 완료를 여러 편지가 보고해도
      # (wd_1/wd_1_dup, worker_done_1/2) 원장은 1번만 쓴다 — 깨우기는 messageId 단위로
      # 각각 1회(B11)지만 정산 원장은 완료(task+dispatch) 단위다.
     if ! has_key "$SEEN_WD_LEDGER" "wd:$task_id:$dispatch_id"; then
        SEEN_WD_LEDGER="${SEEN_WD_LEDGER}wd:$task_id:$dispatch_id|"
       record_worker_done_ledger "$task_id" "$dispatch_id" "$sender"
     fi
    fi
    emit_signal "SIGNAL $message_type $sender task=$task_id dispatch=$dispatch_id summary=$summary" || {
      on_wake_failure "$message_id" "$message_type" "$sender" "$task_id" "$dispatch_id" && { SEEN_IDS="$SEEN_IDS$seen_key|"; continue; }
      DELIVERY_OK=0
      break
    }
    SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
    SEEN_IDS="$SEEN_IDS$seen_key|"
  done <<< "$delivery"
}

# A1: supervisor가 소유한 pane에서만 Delivery를 소비한다.
# PPID=1 nohup / launchd 데몬화와 companion 신분 env 규칙 (2026-08-06):
# PPID=1은 표준 nohup 데몬화 경로로 충족한다 — nohup 으로 띄우면 PPID 가 1 이 되고
# ORCA_TERMINAL_HANDLE 등 신분 env 가 그대로 상속된다. launchd 를 쓰는 경우(현재 판
# 실측: ORCA_TERMINAL_HANDLE 을 plist 에 명시해 정상 동작 확인) 명령에 companion 신분
# env 를 반드시 명시해야 한다 — launchd plist 는 부모 셸 env 를 상속하지 않는다.
# PPID=1 만 확인하고 env 를 빠뜨리면 프로세스는 살아 있어도 wake 가 전면 불능이다
# (2026-08-05 env 소실 사고의 규칙 충돌 이유: PPID=1 이지만 신분 env 가 없어 companion
# 이 낡은 handle 로 감시가 정상인 것처럼 보이는 은폐 상태로 살아 있었음). 이 두 상황
# (launchd 명시 env 정상 동작 vs env 소실 사고)을 주석·문서에서 혼동 없이 구분한다.
refresh_supervisor_handle || {
  echo "ROSTER_FAIL_CLOSED role=$SUPERVISOR_ROLE reason=$RESOLVE_REASON" >&2
  exit 4
}
CALLER_TERMINAL_HANDLE="${ORCA_TERMINAL_HANDLE:-}"
if [ -z "$CALLER_TERMINAL_HANDLE" ] || [ "$CALLER_TERMINAL_HANDLE" != "$SUPERVISOR_HANDLE" ]; then
  echo "CHECK_DIAGNOSTIC consumer_owner_mismatch expected=$SUPERVISOR_HANDLE actual=${CALLER_TERMINAL_HANDLE:-missing}"
  exit 4
fi

trap 'exit 0' INT TERM
trap '' HUP
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  NOW=$(date +%s)
  DID_WAIT_THIS_CYCLE=0
  if refresh_supervisor_handle; then
    # roster resolve 가 성공한 주기이므로 반대 종류(roster 실패) 연속 횟수를 끊는다.
    ROSTER_FAIL_STREAK=0
    CALLER_TERMINAL_HANDLE="${ORCA_TERMINAL_HANDLE:-}"
    if [ -z "$CALLER_TERMINAL_HANDLE" ] || [ "$CALLER_TERMINAL_HANDLE" != "$SUPERVISOR_HANDLE" ]; then
      # 루프 중 owner 불일치: 연속 1~2회는 재시도, 3회째에 자기 종료. 실패 주기에는
      # Delivery 를 소비하거나 ack 하지 않는다(fail-closed). 이 분기에서도 roster 실패
      # 연속 횟수는 0 으로 끊는다 — 서로 다른 실패 종류는 절대 합산하지 않는다.
      ROSTER_FAIL_STREAK=0
      OWNER_MISMATCH_STREAK=$((OWNER_MISMATCH_STREAK + 1))
      if [ "$OWNER_MISMATCH_STREAK" -ge 3 ]; then
        echo "SELF_EXIT consumer_owner_mismatch streak=$OWNER_MISMATCH_STREAK expected=$SUPERVISOR_HANDLE actual=${CALLER_TERMINAL_HANDLE:-missing} self_exit=true"
        exit 5
      fi
      echo "CHECK_DIAGNOSTIC consumer_owner_mismatch streak=$OWNER_MISMATCH_STREAK expected=$SUPERVISOR_HANDLE actual=${CALLER_TERMINAL_HANDLE:-missing}"
    else
      OWNER_MISMATCH_STREAK=0
      # 매 주기마다 super Run coordinator 를 동적 조회한다. coordinator 교대 후 다음
      # 조회부터 새 coordinator 에 자동 적응한다.
      resolve_super_coordinator || true
      # F-B11-3: 상신도 비상 깨우기도 실패해 fail-closed 로 남은 상태가 있으면 이 자가점검이
      # 읽고 회수한다. 이것이 그 상태 파일의 단일 소비자다(새 감시 프로세스 없음).
      consume_shape_emergency_state || true
      run_mail_step
      if [ "$CHECK_STATUS" -ne 0 ]; then
        case "$OUT" in
          *consumer_fenced*) diagnose_check_once consumer_fenced ;;
          *terminal_target_not_run_mailbox*) diagnose_check_once terminal_target_not_run_mailbox ;;
          *run_target_mismatch*) diagnose_check_once run_target_mismatch ;;
          *) diagnose_check_once check_failed ;;
        esac
      else
        DELIVERY=$(printf '%s' "$OUT" | parse_delivery)
        DELIVERY_HEADER=$(printf '%s\n' "$DELIVERY" | awk 'NR==1 {print; exit}')
        case "$DELIVERY_HEADER" in
          ERROR\|*) diagnose_check_once "${DELIVERY_HEADER#ERROR|}" ;;
          EMPTY) ;;
          DELIVERY\|*)
            delivery_id=${DELIVERY_HEADER#DELIVERY|}
            process_delivery "$DELIVERY" "$delivery_id"
            if [ "$DELIVERY_OK" -eq 1 ]; then
              # ack 가 실패하면 배달이 우편함에 남아 다음 check --wait 가 같은 배치를
              # 즉시 다시 준다(H2, 2026-08-11 실측: sleep 없는 연속 재생 고리). 이때는
              # wait 가 페이싱을 제공하지 못하므로 이 주기를 "대기하지 않은 주기"로
              # 표시해 아래의 sleep $POLL_INTERVAL 분기가 고리 속도를 잡게 한다.
              "$ORCA_BIN" orchestration check --run "$PROJECT_RUN_ID" --ack "$delivery_id" --json >/dev/null 2>&1 \
                || { diagnose_check_once ack_failed; DID_WAIT_THIS_CYCLE=0; }
            fi
            ;;
         *) diagnose_check_once delivery_shape ;;
       esac
     fi
      # 고아 결정 관문 NUDGE: project Run pending 관문과 슈퍼 Run decision_gate 편지를
      # gateId 로 대조해 빠진 편지가 있으면 현재 project supervisor 를 1회 깨운다.
      # Delivery ack/worker_done 흐름과 독립이며 항상 0 을 돌려 손상하지 않는다.
      handle_gate_nudge_check || true
    fi
  else
    # supervisor roster resolve 실패: owner 불일치와는 별도 연속 횟수로 다룬다.
    # 서로 다른 실패 종류를 무조건 합산하지 않는다. 1~2회는 재시도, 3회 연속이면
    # 자기 종료. 실패 주기에는 consume/ack 하지 않는다(fail-closed).
    # 이 분기에서 owner mismatch 연속 횟수를 0 으로 끊는다 — owner 2회 뒤 roster 1회가
    # 끼면 그 다음 owner 1회는 연속 3회가 아니다(양방향 교차 모두 같은 규칙).
    OWNER_MISMATCH_STREAK=0
    ROSTER_FAIL_STREAK=$((ROSTER_FAIL_STREAK + 1))
    if [ "$ROSTER_FAIL_STREAK" -ge 3 ]; then
      echo "SELF_EXIT supervisor_roster_unresolved streak=$ROSTER_FAIL_STREAK reason=$RESOLVE_REASON self_exit=true"
      exit 6
    fi
    echo "CHECK_DIAGNOSTIC supervisor_roster_unresolved streak=$ROSTER_FAIL_STREAK reason=$RESOLVE_REASON"
  fi

  # 여기서는 relay 주소로 bounded 순찰 알람만 보낸다. 화면 읽기는 relay agent 몫이다.
  if [ "$ENABLE_KICKER" -eq 1 ] && [ "$NOW" -ge "$NEXT_KICKER" ]; then
    if refresh_relay_handle; then
      KICKER_TEXT="[순찰 알람] project=$PROJECT board=$BOARD run=$PROJECT_RUN_ID supervisor=$SUPERVISOR_HANDLE. 자기 판 supervisor output만 bounded 범위로 확인하세요. 각 active worker는 task-list --run $PROJECT_RUN_ID --brief와 dispatch-show로 현재 taskId+dispatchId+pane을 대조한 뒤 scripts/relay-execution-guard.py를 --run $PROJECT_RUN_ID --board $BOARD --terminal <현재handle> --task-id <taskId> --dispatch-id <dispatchId> --relay-log <레포본체 relay log>로 작업당 1회 실행하세요. E1-E8 판정과 재개는 그 도구 결과만 따르고 새 task/dispatch를 만들지 마세요. 도구 실행 줄 또는 Context% 증가를 확인하고 연속 무진행 횟수를 기록하세요. 2회 연속이면 정체로 보고하세요. 스피너만으로 STARTED/정상 진행을 판정하지 마세요. quoted prompt, orchestration render, old scrollback, raw 문자열은 후보 근거에서 제외하세요. 사람에게 답·승인·결정을 요구하거나 waiting_for_kyle인 넓은 후보를 taskId dispatchId outputCursor boundedSnippet을 넣은 relay_candidate 편지로 project Run에 구조화하세요. ID가 없거나 시간·장부가 모호할 때만 boundedSnippet으로 새 relay_candidate를 보내세요. relay는 super upper report나 kyle 질문을 직접 만들지 않고 카드 상태도 바꾸지 않습니다. Context 80% 초과 또는 판 경계에서는 새 relay 세션으로 교대하세요."
      send_text_then_enter "$RELAY_HANDLE" "$KICKER_TEXT" || echo "KICKER_FAIL $RELAY_HANDLE"
    else
      echo "KICKER_FAIL roster_resolve role=$RELAY_ROLE reason=$RESOLVE_REASON"
    fi
    NEXT_KICKER=$(( NOW + KICKER_INTERVAL ))
  fi
  # 대기(wait)가 이번 주기를 이미 잰 경우 sleep 하지 않는다(폴링 제거의 핵심).
  # 진짜 대기하지 않은 주기(폴백 모드, owner 불일치/roster 실패 fail-closed 주기)만
  # sleep 으로 잰다 — 그런 주기에 대기할 수단이 없어 빙글빙글 도는 것을 막는다.
  if [ "$DID_WAIT_THIS_CYCLE" = 1 ]; then
    :
  else
    sleep "$POLL_INTERVAL"
  fi
done
echo "DEADLINE_REACHED"
exit 1
