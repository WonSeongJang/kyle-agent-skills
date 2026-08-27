#!/bin/bash
# B8 감독 주기적 자가 점검 깨우기 시험 — 거부 증거(변이 실측) 포함.
#
# Why: 깨우기는 감독을 주기적으로 깨우는 유일한 장치다. 이 시험이 지키는 것은 네 가지다.
#   1. companion 이 죽어도 깨우기는 계속 돈다 (분리 증명)
#   2. 카드 장부 조회가 실패해도 "0장"으로 읽지 않는다 (fail-closed)
#   3. 내 판 companion 만 죽었을 때, 다른 판 companion 이 살아 있어도 죽음으로 잡는다 (초록불 위장 차단)
#   4. 깨우기가 죽으면 이미 있는 정체 신고기가 그것을 신고한다 (감시 한 겹)
#
# 변이 검증 장치: SUPERVISOR_WAKER_UNDER_TEST / STALL_REPORTER_UNDER_TEST 로 고장 낸 사본을
# 끼우면 이 시험은 **떨어져야** 한다.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
WAKER="${SUPERVISOR_WAKER_UNDER_TEST:-$SKILL_DIR/scripts/supervisor-waker.sh}"
REPORTER="${STALL_REPORTER_UNDER_TEST:-$SKILL_DIR/scripts/stall-reporter.sh}"
PATH_HELPER="$SKILL_DIR/scripts/waker-heartbeat-path.sh"
FIXTURE="$SCRIPT_DIR/fixtures/orca"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS %s\n' "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL %s\n' "$1" >&2; }

# 이 시험이 띄운 프로세스만 여기에 모아 두었다가 끝에서 되돌린다.
# 되돌리는 대상은 전부 이 시험이 만든 /tmp 아래 고유 경로의 프로세스다.
SPAWNED_PIDS=()
cleanup() {
  local p child
  for p in "${SPAWNED_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    # 가짜 daemon(bash)이 띄운 자식(sleep)까지 되돌린다. 부모만 죽이면 자식이
    # 고아로 최대 120초 남아 다음 시험 관측을 오염시킨다.
    for child in $(pgrep -P "$p" 2>/dev/null); do
      kill "$child" 2>/dev/null || true
    done
    kill "$p" 2>/dev/null || true
  done
}
trap cleanup EXIT

new_state() { mktemp -d /tmp/orca-supervisor-waker.XXXXXX; }

# 시험마다 **다른 판 이름**을 쓴다. 이 시험들은 판 이름(`--board`)으로 내 프로세스를 가리므로,
# 모든 시험이 board_test 하나를 쓰면 앞 시험이 남긴 가짜 프로세스가 뒤 시험의 "내 것"으로
# 잡힌다(2026-08-11 실측: 그 때문에 시험 2개가 잘못 떨어졌다). 실제 판 이름은 판마다 다르므로
# 고유 이름을 쓰는 쪽이 현실과도 맞다.
board_of() { printf 'board_%s' "$(basename "$1" | sed 's/[^A-Za-z0-9]/_/g')"; }


# `grep -c` 는 0줄일 때도 "0" 을 찍고 종료 코드 1로 끝난다. 거기에 `|| printf 0` 을 붙이면
# 숫자가 "0\n0" 이 되어 뒤의 `[ ... -eq ... ]` 이 통째로 깨진다(이 시험에서 실제로 겪었다).
count_matches() {
  local pattern="$1" file="$2" n
  [ -f "$file" ] || { printf '0\n'; return 0; }
  n=$(grep -c -- "$pattern" "$file" 2>/dev/null)
  printf '%s\n' "${n:-0}"
}

make_task_list() {
  local dir="$1"; shift
  local tasks="" i=0 status
  for status in "$@"; do
    i=$((i + 1))
    [ -n "$tasks" ] && tasks="$tasks,"
    tasks="$tasks{\"id\":\"task_$i\",\"run_id\":\"run_project\",\"status\":\"$status\"}"
  done
  printf '{"ok":true,"result":{"runId":"run_project","count":%d,"tasks":[%s]}}\n' "$i" "$tasks" > "$dir/task_list.json"
}
make_task_list_raw() { printf '%s\n' "$2" > "$1/task_list.json"; }

# 가짜 감시 프로세스를 띄운다. 실제 companion 처럼 **부모가 init(PPID 1)** 이 되도록
# 중간 셸을 즉시 끝내 고아로 만든다. `( cmd & )` 가 그 일을 한다.
# $1 = 판 폴더(런타임 폴더), $2 = 스크립트 이름, $3 = 명령줄에 붙일 인자(선택)
# $3 은 "판 신분이 경로가 아니라 인자에 있는" 실제 배치를 재현할 때 쓴다.
# 결과 PID는 전역 변수 SPAWNED_PID 로 돌려준다. `pid=$(spawn_fake_daemon ...)` 처럼
# 명령 치환으로 받으면 함수가 하위 셸에서 돌아 SPAWNED_PIDS 등록이 부모에게 전달되지
# 않고 cleanup 이 그 PID 를 놓친다(2026-08-11 실측: 시험당 가짜 daemon 5개 잔여).
# 그래서 호출부는 반드시 `spawn_fake_daemon ...; pid=$SPAWNED_PID` 형태로 받는다.
spawn_fake_daemon() {
  local runtime_dir="$1" name="$2" extra="${3:-}" path pid match
  SPAWNED_PID=""
  mkdir -p "$runtime_dir/v3"
  path="$runtime_dir/v3/$name"
  printf '#!/bin/bash\nsleep 120\n' > "$path"
  # 표준입출력을 반드시 끊는다. 고아 프로세스가 부모의 출력 파이프를 물고 있으면
  # 호출부가 **자식이 끝날 때까지 멈춘다.** 실측: 이것 하나로 시험 한 번이
  # 6분 넘게 멈춰 있었다(자식 수명 120초 x 호출 수).
  if [ -n "$extra" ]; then
    # shellcheck disable=SC2086  # 인자를 여러 토막으로 넘기려고 일부러 안 감쌌다.
    ( bash "$path" $extra >/dev/null 2>&1 </dev/null & )
    match="^bash $path $extra$"
  else
    ( bash "$path" >/dev/null 2>&1 </dev/null & )
    match="^bash $path$"
  fi
  # 고아가 되어 PPID 1 로 옮겨질 때까지 기다린다. 고정 시간 대기가 아니라 조건 대기다.
  local waited=0
  while [ "$waited" -lt 100 ]; do
    pid=$(pgrep -f "$match" 2>/dev/null | head -1)
    if [ -n "$pid" ] && [ "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" = "1" ]; then
      SPAWNED_PIDS+=("$pid")
      SPAWNED_PID="$pid"
      return 0
    fi
    sleep 0.05
    waited=$((waited + 1))
  done
  return 1
}

# 판 하나를 차린다. 런타임 폴더 + 중계기 일기 + 정상 카드 장부.
setup_board() {
  local sd="$1"
  mkdir -p "$sd/mine" "$sd/other" "$sd/relay-logs"
  printf '2026-08-10 10:00:00 +0900|patrol_summary active_dispatched=1 no_progress_streak=0\n' > "$sd/relay-logs/relay.log"
  make_task_list "$sd" dispatched
}

heartbeat_path_for() {
  bash "$PATH_HELPER" "$1/relay-logs/relay.log" "$(board_of "$1")"
}

# 깨우기를 한 주기만 돌린다.
run_waker_once() {
  local sd="$1"; shift
  FAKE_ORCA_STATE_DIR="$sd" ORCA_BIN="$FIXTURE" \
    "$WAKER" --board "$(board_of "$sd")" --supervisor term_supervisor --run run_project \
      --relay-log "$sd/relay-logs/relay.log" --runtime-dir "$sd/mine" \
      --once "$@" > "$sd/waker-output.log" 2>&1
  return $?
}

# 인자를 빼고 부른다. 방어가 선택 인자에 매달려 있으면 여기서 통과해 버린다.
run_waker_missing() {
  local sd="$1" omit="$2"
  local args=(--board "$(board_of "$sd")" --supervisor term_supervisor --run run_project
              --relay-log "$sd/relay-logs/relay.log" --runtime-dir "$sd/mine" --once)
  local out=() skip=0 a
  for a in "${args[@]}"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    if [ "$a" = "$omit" ]; then skip=1; continue; fi
    out+=("$a")
  done
  FAKE_ORCA_STATE_DIR="$sd" ORCA_BIN="$FIXTURE" "$WAKER" "${out[@]}" > "$sd/waker-missing.log" 2>&1
  return $?
}

# === 1. 필수 인자가 없으면 거부한다 (방어는 선택 인자가 아니다) ===
test_required_args() {
  local sd bad=0 flag status
  sd=$(new_state); setup_board "$sd"
  for flag in --board --supervisor --run --relay-log --runtime-dir; do
    run_waker_missing "$sd" "$flag"
    status=$?
    [ "$status" -eq 2 ] || { bad=$((bad + 1)); printf '  %s 없이 호출했는데 종료 %s\n' "$flag" "$status" >&2; }
  done
  [ "$bad" -eq 0 ] \
    && pass "required_args: 필수 인자 5종을 하나라도 빼면 거부(종료 2)" \
    || fail "required_args: $bad 개 인자가 없어도 통과함"
}

# === 2. 판이 정상이어도 무조건 깨운다 ===
test_wakes_unconditionally() {
  local sd n
  sd=$(new_state); setup_board "$sd"
  spawn_fake_daemon "$sd/mine" conductor-companion.sh >/dev/null
  spawn_fake_daemon "$sd/mine" stall-reporter.sh >/dev/null
  run_waker_once "$sd"
  n=$(count_matches '자가점검 깨우기' "$sd/sends.log")
  [ "$n" -ge 1 ] \
    && pass "wakes_unconditionally: 이상이 없어도 감독을 깨운다" \
    || fail "wakes_unconditionally: 정상일 때 깨우지 않음 (n=$n)"
}

# === 3. 카드 장부 조회 실패를 "0장"으로 읽지 않는다 ===
test_query_fail_is_not_zero() {
  local sd unknown zero
  sd=$(new_state); setup_board "$sd"
  make_task_list_raw "$sd" '{"ok":false,"result":{"tasks":[]}}'
  run_waker_once "$sd"
  unknown=$(count_matches '판정불가' "$sd/sends.log")
  zero=$(count_matches '발령 0' "$sd/sends.log")
  { [ "$unknown" -ge 1 ] && [ "$zero" -eq 0 ]; } \
    && pass "query_fail_is_not_zero: 조회 실패를 판정불가로 내보낸다" \
    || fail "query_fail_is_not_zero: 실패를 0장으로 읽음 (판정불가=$unknown 발령0=$zero)"
}

# === 4. 심박을 적는다 (주기 값 포함) ===
test_heartbeat_written() {
  local sd hb alive interval
  sd=$(new_state); setup_board "$sd"
  run_waker_once "$sd" --interval-sec 60
  hb=$(heartbeat_path_for "$sd")
  alive=$(count_matches 'SUPERVISOR_WAKER_ALIVE' "$hb")
  interval=$(count_matches 'interval=60' "$hb")
  { [ "$alive" -ge 2 ] && [ "$interval" -ge 2 ]; } \
    && pass "heartbeat_written: 시작·점검마다 심박과 주기를 적는다" \
    || fail "heartbeat_written: 심박 부족 (alive=$alive interval=$interval)"
}

# === 5. 심박이 중계기 일기를 건드리지 않는다 (초록불 위장 차단) ===
# 중계기 일기에 심박을 적으면 그 파일이 계속 새것이 되어, 중계기가 죽어도 신고기의
# "중계기 순찰이 멈췄다" 판정이 눈이 먼다. 그 위장이 실제로 성립함을 대조로 보인다.
test_heartbeat_does_not_touch_relay_log() {
  local sd before after masked
  sd=$(new_state); setup_board "$sd"
  # 중계기가 죽은 상황: 일기를 과거 시각으로 못 박는다.
  touch -t 202608100000 "$sd/relay-logs/relay.log"
  before=$(stat -f %m "$sd/relay-logs/relay.log")
  run_waker_once "$sd"
  after=$(stat -f %m "$sd/relay-logs/relay.log")
  # 대조: 만약 심박을 중계기 일기에 적었다면 mtime 이 갱신되어 침묵이 가려진다.
  printf 'x\n' >> "$sd/relay-logs/relay.log"
  masked=$(stat -f %m "$sd/relay-logs/relay.log")
  { [ "$before" = "$after" ] && [ "$masked" != "$before" ]; } \
    && pass "heartbeat_does_not_touch_relay_log: 심박이 중계기 침묵 판정을 가리지 않는다" \
    || fail "heartbeat_does_not_touch_relay_log: 일기 mtime 이 흔들림 (before=$before after=$after masked=$masked)"
}

# === 6. 내 판 companion 만 죽으면, 다른 판 것이 살아 있어도 죽음으로 잡는다 ===
test_scoped_companion_death() {
  local sd mine_pid other_pid dead
  sd=$(new_state); setup_board "$sd"
  spawn_fake_daemon "$sd/mine" conductor-companion.sh; mine_pid=$SPAWNED_PID
  spawn_fake_daemon "$sd/other" conductor-companion.sh; other_pid=$SPAWNED_PID
  spawn_fake_daemon "$sd/mine" stall-reporter.sh >/dev/null
  [ -n "$mine_pid" ] && [ -n "$other_pid" ] || { fail "scoped_companion_death: 가짜 감시 프로세스를 못 띄움"; return; }
  # 내 판 것만 되돌린다. 다른 판 것은 그대로 살려 둔다.
  kill "$mine_pid" 2>/dev/null || true
  while kill -0 "$mine_pid" 2>/dev/null; do sleep 0.05; done
  run_waker_once "$sd"
  dead=$(count_matches 'companion 죽음' "$sd/sends.log")
  [ "$dead" -ge 1 ] \
    && pass "scoped_companion_death: 다른 판 companion 이 살아 있어도 내 것의 죽음을 잡는다" \
    || fail "scoped_companion_death: 다른 판 것을 내 생존으로 읽음 (dead=$dead)"
}

# === 6-1. 앞부분만 겹치는 다른 판 경로를 내 것으로 세지 않는다 ===
# Why (2026-08-11 R-B8 반례): 런타임 경로를 그냥 부분문자열로 맞추면 내 폴더가 `/mine` 일 때
# 다른 판 폴더 `/mine-shadow` 의 companion 하나가 내 companion 으로 세어져
# **내 판 companion 죽음이 조용히 가려진다.** 경로는 글자가 아니라 경계가 있는 경로다.
# 이 시험은 `/other` 처럼 아예 다른 이름이 아니라 **앞부분이 정확히 겹치는** 반례를 쓴다.
test_path_prefix_collision() {
  local sd shadow_pid comp dead
  sd=$(new_state); setup_board "$sd"
  # 내 판에는 companion 을 아예 띄우지 않는다. 신고기만 띄워 신고기 판정과 섞이지 않게 한다.
  spawn_fake_daemon "$sd/mine" stall-reporter.sh >/dev/null
  spawn_fake_daemon "$sd/mine-shadow" conductor-companion.sh; shadow_pid=$SPAWNED_PID
  [ -n "$shadow_pid" ] || { fail "path_prefix_collision: 가짜 감시 프로세스를 못 띄움"; return; }
  run_waker_once "$sd"
  comp=$(count_matches 'companion 0' "$sd/sends.log")
  dead=$(count_matches 'companion 죽음' "$sd/sends.log")
  { [ "$comp" -ge 1 ] && [ "$dead" -ge 1 ]; } \
    && pass "path_prefix_collision: /mine-shadow 를 /mine 으로 세지 않는다" \
    || fail "path_prefix_collision: 앞부분 겹침 경로를 내 생존으로 읽음 (companion0=$comp dead=$dead)"
}

# === 6-2. 내 런타임 폴더 아래 실제 경로는 그대로 내 것으로 센다 (대조군) ===
# 위 시험이 "경계를 너무 좁혀 아무것도 안 세는" 방식으로도 통과하지 않도록 짝으로 둔다.
test_path_boundary_control() {
  local sd comp dead
  sd=$(new_state); setup_board "$sd"
  spawn_fake_daemon "$sd/mine" conductor-companion.sh >/dev/null
  spawn_fake_daemon "$sd/mine" stall-reporter.sh >/dev/null
  # 앞부분 겹침 프로세스가 같이 살아 있어도 내 숫자는 1 이어야 한다(둘로 세지도 않는다).
  spawn_fake_daemon "$sd/mine-shadow" conductor-companion.sh >/dev/null
  run_waker_once "$sd"
  comp=$(count_matches 'companion 1' "$sd/sends.log")
  dead=$(count_matches 'companion 죽음' "$sd/sends.log")
  { [ "$comp" -ge 1 ] && [ "$dead" -eq 0 ]; } \
    && pass "path_boundary_control: 내 폴더 아래 실제 경로는 그대로 내 것으로 센다" \
    || fail "path_boundary_control: 내 것을 못 셈 (companion1=$comp dead=$dead)"
}

# === 6-3. 내 경로가 남의 경로 **꼬리**로 들어 있어도 내 것으로 세지 않는다 ===
# Why: 경계를 뒤쪽만 보면 `/a/b/mine` 이 `/deep/a/b/mine` 안에 통째로 들어 있으므로
# 다시 남의 프로세스를 내 것으로 센다. 앞 경계(줄 시작·공백)를 같이 봐야 막힌다.
# 실측(2026-08-11): 앞 경계만 빼도 6-1/6-2 는 둘 다 통과했다 — 그 변형을 잡는 자리다.
test_path_suffix_collision() {
  local sd nested nested_pid comp dead
  sd=$(new_state); setup_board "$sd"
  nested="$sd/deep$sd/mine"
  spawn_fake_daemon "$sd/mine" stall-reporter.sh >/dev/null
  spawn_fake_daemon "$nested" conductor-companion.sh; nested_pid=$SPAWNED_PID
  [ -n "$nested_pid" ] || { fail "path_suffix_collision: 가짜 감시 프로세스를 못 띄움"; return; }
  run_waker_once "$sd"
  comp=$(count_matches 'companion 0' "$sd/sends.log")
  dead=$(count_matches 'companion 죽음' "$sd/sends.log")
  { [ "$comp" -ge 1 ] && [ "$dead" -ge 1 ]; } \
    && pass "path_suffix_collision: 남의 경로 꼬리에 든 내 경로를 내 것으로 세지 않는다" \
    || fail "path_suffix_collision: 꼬리 겹침 경로를 내 생존으로 읽음 (companion0=$comp dead=$dead)"
}

# === 7. 내 판 companion 이 살아 있으면 죽음으로 읽지 않는다 (대조군) ===
test_alive_companion_not_reported_dead() {
  local sd dead count
  sd=$(new_state); setup_board "$sd"
  spawn_fake_daemon "$sd/mine" conductor-companion.sh >/dev/null
  spawn_fake_daemon "$sd/mine" stall-reporter.sh >/dev/null
  run_waker_once "$sd"
  dead=$(count_matches 'companion 죽음' "$sd/sends.log")
  count=$(count_matches 'companion 1' "$sd/sends.log")
  { [ "$dead" -eq 0 ] && [ "$count" -ge 1 ]; } \
    && pass "alive_companion_not_reported_dead: 살아 있으면 1개로 세고 죽음이라 하지 않는다" \
    || fail "alive_companion_not_reported_dead: 오보 (죽음=$dead companion1=$count)"
}

# === 8. companion 이 죽어도 깨우기는 계속 돈다 (분리 증명) ===
test_survives_companion_death() {
  local sd pid comp_pid before after waited
  sd=$(new_state); setup_board "$sd"
  spawn_fake_daemon "$sd/mine" conductor-companion.sh; comp_pid=$SPAWNED_PID
  [ -n "$comp_pid" ] || { fail "survives_companion_death: 가짜 companion 을 못 띄움"; return; }
  FAKE_ORCA_STATE_DIR="$sd" ORCA_BIN="$FIXTURE" \
    "$WAKER" --board "$(board_of "$sd")" --supervisor term_supervisor --run run_project \
      --relay-log "$sd/relay-logs/relay.log" --runtime-dir "$sd/mine" \
      --interval-sec 1 > "$sd/waker-loop.log" 2>&1 &
  pid=$!
  SPAWNED_PIDS+=("$pid")
  # 셸이 이 작업을 거둘 때 찍는 "Terminated" 잡음을 끈다. 관문 화면에서 진짜 실패로 보인다.
  disown "$pid" 2>/dev/null || true
  # 첫 깨우기가 나올 때까지 기다린다.
  waited=0
  while [ "$(count_matches '자가점검 깨우기' "$sd/sends.log")" -lt 1 ] && [ "$waited" -lt 200 ]; do
    sleep 0.1; waited=$((waited + 1))
  done
  before=$(count_matches '자가점검 깨우기' "$sd/sends.log")
  # companion 을 죽인다. 배달이 죽어도 깨우기는 살아야 한다.
  kill "$comp_pid" 2>/dev/null || true
  waited=0
  while [ "$(count_matches '자가점검 깨우기' "$sd/sends.log")" -le "$before" ] && [ "$waited" -lt 200 ]; do
    sleep 0.1; waited=$((waited + 1))
  done
  after=$(count_matches '자가점검 깨우기' "$sd/sends.log")
  local still_alive=0
  kill -0 "$pid" 2>/dev/null && still_alive=1
  kill "$pid" 2>/dev/null || true
  { [ "$before" -ge 1 ] && [ "$after" -gt "$before" ] && [ "$still_alive" -eq 1 ]; } \
    && pass "survives_companion_death: companion 이 죽어도 깨우기는 계속 돈다" \
    || fail "survives_companion_death: 배달이 죽자 깨우기도 멈춤 (before=$before after=$after alive=$still_alive)"
}

# === 9. 낡은 코드로 도는 상주 프로세스를 잡는다 ===
test_stale_code_detected() {
  local sd pid stale
  sd=$(new_state); setup_board "$sd"
  spawn_fake_daemon "$sd/mine" conductor-companion.sh; pid=$SPAWNED_PID
  spawn_fake_daemon "$sd/mine" stall-reporter.sh >/dev/null
  [ -n "$pid" ] || { fail "stale_code_detected: 가짜 companion 을 못 띄움"; return; }
  # 도는 프로세스보다 파일이 더 새것이 되게 만든다 = 낡은 코드로 돌고 있다.
  touch "$sd/mine/v3/conductor-companion.sh"
  sleep 1
  touch "$sd/mine/v3/conductor-companion.sh"
  run_waker_once "$sd"
  stale=$(count_matches '낡은코드:conductor-companion.sh' "$sd/sends.log")
  [ "$stale" -ge 1 ] \
    && pass "stale_code_detected: 파일만 고치고 옛 코드로 도는 프로세스를 잡는다" \
    || fail "stale_code_detected: 낡은 코드를 못 잡음 (stale=$stale)"
}

# === 10. 심박 경로를 양쪽이 같은 자리에서 계산한다 ===
test_heartbeat_path_single_source() {
  local sd from_helper in_waker in_reporter
  sd=$(new_state); setup_board "$sd"
  from_helper=$(heartbeat_path_for "$sd")
  run_waker_once "$sd"
  in_waker=$(grep -o 'heartbeat=[^ ]*' "$sd/waker-output.log" | head -1 | sed 's/^heartbeat=//')
  in_reporter=$(grep -c "waker_heartbeat_path" "$REPORTER" 2>/dev/null || printf '0')
  { [ "$from_helper" = "$in_waker" ] && [ -f "$from_helper" ] && [ "$in_reporter" -ge 1 ]; } \
    && pass "heartbeat_path_single_source: 깨우기와 신고기가 같은 계산기를 쓴다" \
    || fail "heartbeat_path_single_source: 경로 계산이 갈림 (helper=$from_helper waker=$in_waker reporter_uses=$in_reporter)"
}

# === 신고기 쪽: 깨우기 죽음을 실제로 신고하는가 ===
run_reporter_once() {
  local sd="$1"
  FAKE_ORCA_STATE_DIR="$sd" ORCA_BIN="$FIXTURE" \
    STALL_REPORTER_STATE_DIR="$sd/reporter-state" FAKE_RELAY_HANDLE=term_relay \
    STALL_REPORTER_STARTUP_CYCLES=0 \
    STALL_REPORTER_WAKER_SILENCE_SEC="${2:-1}" \
    "$REPORTER" --project project_test --board "$(board_of "$sd")" \
      --relay-log "$sd/relay-logs/relay.log" \
      --super-run run_super --project-run run_project --relay-role relay \
      --relay-silence-sec 999999 --board-idle-sec 999999 --poll-sec 1 --once \
      > "$sd/reporter-output.log" 2>&1
}

# === 11. 심박이 끊기면 신고기가 신고한다 ===
test_reporter_reports_waker_death() {
  local sd hb n stopped
  sd=$(new_state); setup_board "$sd"
  run_waker_once "$sd"
  hb=$(heartbeat_path_for "$sd")
  # 심박을 과거로 못 박는다 = 깨우기가 죽은 뒤 시간이 흘렀다.
  touch -t 202608100000 "$hb"
  mkdir -p "$sd/reporter-state"
  run_reporter_once "$sd" 60
  n=$(count_matches '감독 깨우기가 멈췄다' "$sd/project-sends.log")
  stopped=$(count_matches '"wakerState":"stopped"' "$sd/project-sends.log")
  { [ "$n" -ge 1 ] && [ "$stopped" -ge 1 ]; } \
    && pass "reporter_reports_waker_death: 심박이 끊기면 신고기가 신고한다" \
    || fail "reporter_reports_waker_death: 깨우기 죽음을 신고 안 함 (n=$n stopped=$stopped)"
}

# === 12. 심박이 살아 있으면 오보하지 않는다 (대조군) ===
test_reporter_quiet_when_waker_alive() {
  local sd n
  sd=$(new_state); setup_board "$sd"
  run_waker_once "$sd"
  mkdir -p "$sd/reporter-state"
  run_reporter_once "$sd" 3600
  n=$(count_matches '감독 깨우기가' "$sd/project-sends.log")
  [ "$n" -eq 0 ] \
    && pass "reporter_quiet_when_waker_alive: 심박이 살아 있으면 조용하다" \
    || fail "reporter_quiet_when_waker_alive: 살아 있는데 오보 (n=$n)"
}

# === 13. "한 번도 없음"과 "있다가 끊김"을 다른 말로 신고한다 ===
test_reporter_absent_vs_stopped() {
  local sd_absent sd_stopped absent stopped absent_wrong
  sd_absent=$(new_state); setup_board "$sd_absent"; mkdir -p "$sd_absent/reporter-state"
  run_reporter_once "$sd_absent" 0
  absent=$(count_matches '아예 없다' "$sd_absent/project-sends.log")
  absent_wrong=$(count_matches '멈췄다' "$sd_absent/project-sends.log")

  sd_stopped=$(new_state); setup_board "$sd_stopped"
  run_waker_once "$sd_stopped"
  touch -t 202608100000 "$(heartbeat_path_for "$sd_stopped")"
  mkdir -p "$sd_stopped/reporter-state"
  run_reporter_once "$sd_stopped" 60
  stopped=$(count_matches '멈췄다' "$sd_stopped/project-sends.log")
  { [ "$absent" -ge 1 ] && [ "$absent_wrong" -eq 0 ] && [ "$stopped" -ge 1 ]; } \
    && pass "reporter_absent_vs_stopped: 없음과 끊김을 다른 말로 신고한다" \
    || fail "reporter_absent_vs_stopped: 두 경우가 접힘 (absent=$absent absent_wrong=$absent_wrong stopped=$stopped)"
}

# === 14. 심박이 다시 찍히면 재장전된다 ===
test_reporter_rearms() {
  local sd alerted
  sd=$(new_state); setup_board "$sd"; mkdir -p "$sd/reporter-state"
  run_reporter_once "$sd" 0
  run_waker_once "$sd"
  run_reporter_once "$sd" 3600
  alerted=$(grep -c 'rearm supervisor_waker_recovered' "$sd/reporter-output.log" 2>/dev/null || printf '0')
  [ "$alerted" -ge 1 ] \
    && pass "reporter_rearms: 깨우기가 돌아오면 재장전된다" \
    || fail "reporter_rearms: 재장전 안 됨 (rearm=$alerted)"
}

# === 15. 여러 판이 스크립트 하나를 같이 쓰는 배치에서도 내 것을 찾는다 ===
# Why (2026-08-11 실측): 이 판의 companion 은 판별 사본이 아니라 공유 경로
# `~/.claude/skills/.../conductor-companion.sh --project ... --board mailbox-relay-1` 로 돌고 있었다.
# **판 신분이 경로가 아니라 인자에 있다.** 경로로만 좁히면 살아 있는 companion 을 0개로 세어
# "죽음"을 계속 외친다(빨간불 위장). 그래서 `--board <내 판>` 도 내 것으로 인정한다.
test_shared_script_layout() {
  local sd dead comp
  sd=$(new_state); setup_board "$sd"
  # 경로는 내 판 런타임 폴더 밖이고, 신분은 --board 인자에만 있다.
  spawn_fake_daemon "$sd/shared" conductor-companion.sh "--project project_test --board $(board_of "$sd")" >/dev/null
  spawn_fake_daemon "$sd/shared" stall-reporter.sh "--project project_test --board $(board_of "$sd")" >/dev/null
  run_waker_once "$sd"
  dead=$(count_matches '죽음' "$sd/sends.log")
  comp=$(count_matches 'companion 1' "$sd/sends.log")
  { [ "$dead" -eq 0 ] && [ "$comp" -ge 1 ]; } \
    && pass "shared_script_layout: 공유 스크립트 배치에서도 내 판 것을 살아있음으로 센다" \
    || fail "shared_script_layout: 살아 있는데 죽음으로 읽음 (죽음=$dead companion1=$comp)"
}

# === 16. 공유 배치에서 다른 판 것은 내 것으로 세지 않는다 (대조) ===
test_shared_script_other_board_not_mine() {
  local sd dead
  sd=$(new_state); setup_board "$sd"
  # 같은 공유 경로에 **다른 판** 것만 살아 있다. 내 것은 없다.
  spawn_fake_daemon "$sd/shared" conductor-companion.sh "--project project_test --board other_board" >/dev/null
  run_waker_once "$sd"
  dead=$(count_matches 'companion 죽음' "$sd/sends.log")
  [ "$dead" -ge 1 ] \
    && pass "shared_script_other_board_not_mine: 다른 판 것을 내 생존으로 읽지 않는다" \
    || fail "shared_script_other_board_not_mine: 다른 판 것을 내 것으로 셈 (죽음=$dead)"
}

# === 17. 판 이름의 정규식 특수문자가 다른 판을 내 것으로 만들지 않는다 ===
# Why: 판 이름을 정규식에 그대로 넣으면 `.` 이 아무 글자나 맞는다. 그러면 판 `b.test` 가
# 판 `bXtest` 의 프로세스를 자기 것으로 읽어, **내 것이 죽어도 살아 있음**으로 보고한다.
# 이 판이 하루 종일 잡은 부류 그대로다 — 숫자는 초록인데 그 숫자가 내 것을 안 가리킨다.
test_regex_metachar_board_isolation() {
  local sd dead
  sd=$(new_state); setup_board "$sd"
  # 다른 판 이름은 내 이름과 **한 글자만** 다르다. 그 자리가 내 이름에서는 `.` 이다.
  # 두 가지 함정을 한 번에 본다.
  #   bXtest      - 정규식이었다면 `.` 이 X 를 맞춘다
  #   b.test_more - 앞부분이 내 이름과 똑같다(경계를 안 보면 내 것으로 읽힌다)
  spawn_fake_daemon "$sd/shared" conductor-companion.sh "--project project_test --board bXtest" >/dev/null
  spawn_fake_daemon "$sd/shared2" conductor-companion.sh "--project project_test --board b.test_more" >/dev/null
  FAKE_ORCA_STATE_DIR="$sd" ORCA_BIN="$FIXTURE" \
    "$WAKER" --board 'b.test' --supervisor term_supervisor --run run_project \
      --relay-log "$sd/relay-logs/relay.log" --runtime-dir "$sd/mine" --once \
      > "$sd/waker-regex.log" 2>&1
  dead=$(count_matches 'companion 죽음' "$sd/sends.log")
  [ "$dead" -ge 1 ] \
    && pass "regex_metachar_board_isolation: 판 이름의 특수문자가 다른 판을 내 것으로 만들지 않는다" \
    || fail "regex_metachar_board_isolation: b.test 가 bXtest 를 자기 것으로 읽음 (죽음=$dead)"
}

# === 18. 로케일이 달라도 세기와 낡은코드 검사가 같이 산다 ===
# Why: `ps -o lstart` 은 한국어 로케일에서 토막 수가 다른 모양으로 찍힌다. 그때 기동 시각
# 파싱이 조용히 죽어 낡은코드 검사만 사라졌다(2026-08-10 실측). 세기는 우연히 맞아서
# 화면상 이상이 없었다 — 로케일에 매달린 침묵이다. 그래서 로케일을 바꿔 놓고 같은 것을 본다.
test_locale_independent() {
  local sd pid stale comp
  sd=$(new_state); setup_board "$sd"
  spawn_fake_daemon "$sd/mine" conductor-companion.sh; pid=$SPAWNED_PID
  spawn_fake_daemon "$sd/mine" stall-reporter.sh >/dev/null
  [ -n "$pid" ] || { fail "locale_independent: 가짜 companion 을 못 띄움"; return; }
  touch "$sd/mine/v3/conductor-companion.sh"; sleep 1; touch "$sd/mine/v3/conductor-companion.sh"
  LC_ALL=ko_KR.UTF-8 LANG=ko_KR.UTF-8 FAKE_ORCA_STATE_DIR="$sd" ORCA_BIN="$FIXTURE" \
    "$WAKER" --board "$(board_of "$sd")" --supervisor term_supervisor --run run_project \
      --relay-log "$sd/relay-logs/relay.log" --runtime-dir "$sd/mine" --once \
      > "$sd/waker-locale.log" 2>&1
  stale=$(count_matches '낡은코드:conductor-companion.sh' "$sd/sends.log")
  comp=$(count_matches 'companion 1' "$sd/sends.log")
  { [ "$stale" -ge 1 ] && [ "$comp" -ge 1 ]; } \
    && pass "locale_independent: 한국어 로케일에서도 세기와 낡은코드 검사가 산다" \
    || fail "locale_independent: 로케일에 따라 검사가 죽음 (stale=$stale companion1=$comp)"
}

# === 실행 ===
echo "=== supervisor-waker B8 시험 (깨우기: $WAKER / 신고기: $REPORTER) ==="
bash -n "$WAKER" || { echo "SYNTAX_FAIL $WAKER"; exit 1; }
bash -n "$REPORTER" || { echo "SYNTAX_FAIL $REPORTER"; exit 1; }
bash -n "$PATH_HELPER" || { echo "SYNTAX_FAIL $PATH_HELPER"; exit 1; }

test_required_args
test_wakes_unconditionally
test_query_fail_is_not_zero
test_heartbeat_written
test_heartbeat_does_not_touch_relay_log
test_scoped_companion_death
test_path_prefix_collision
test_path_boundary_control
test_path_suffix_collision
test_alive_companion_not_reported_dead
test_survives_companion_death
test_stale_code_detected
test_shared_script_layout
test_shared_script_other_board_not_mine
test_regex_metachar_board_isolation
test_locale_independent
test_heartbeat_path_single_source
test_reporter_reports_waker_death
test_reporter_quiet_when_waker_alive
test_reporter_absent_vs_stopped
test_reporter_rearms

echo ""
echo "결과: PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
