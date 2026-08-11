#!/bin/bash
set -euo pipefail

# B1 — companion 의 --wait 전환·폴백 로깅·정상 판정을 검증한다(focused).
# 폴링 제거(check --wait 기반)와 "대기 중 vs 죽음" 구분, 그리고 거부 증거(틀린 구현이
# 실제로 시험에 떨어지는지)를 다룬다. 기존 두 companion 시험은 폴백(폴링) 경로를,
# 이 시험은 --wait 주 경로와 정상 판정을 담당한다.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
COMPANION="${B1_COMPANION_UNDER_TEST:-$SKILL_DIR/scripts/conductor-companion.sh}"
FIXTURE="$SCRIPT_DIR/fixtures/orca"
export COMPANION_POLL_INTERVAL_SEC=0.05
export WATCH_DEADLINE_SEC=1
export PROJECT_LEDGER_SCAN_LIMIT=100
export FAKE_ENTER_MODE=ok
export ORCA_TERMINAL_HANDLE=term_supervisor

count() { local pattern="$1" file="$2"; [ -f "$file" ] || { printf '0\n'; return 0; }; rg -c -- "$pattern" "$file" 2>/dev/null || printf '0\n'; }
assert_absent() { local pattern="$1" file="$2"; if [ -f "$file" ] && rg -q -- "$pattern" "$file"; then printf 'ASSERT_ABSENT_FAIL pattern=%s file=%s\n' "$pattern" "$file" >&2; return 1; fi; }
new_state() { mktemp -d /tmp/orca-b1-wait.XXXXXX; }

# companion 을 --wait 지원 fixture(FAKE_WAIT_SUPPORT=1) 또는 폴백(=0)로 돌린다.
# mode 는 기존 시험의 FAKE_RELAY_ALERT_MODE 값(candidate_absent 등).
run_wait_companion() {
  local state_dir="$1" mode="${2:-candidate_absent}" support="${3:-1}"
  export FAKE_ORCA_STATE_DIR="$state_dir"
  export FAKE_RELAY_ALERT_MODE="$mode"
  export FAKE_DELIVERY_MODE=none
  export FAKE_WAIT_SUPPORT="$support"
  export FAKE_WAIT_DELAY=0.05
  export ORCA_BIN="$FIXTURE"
  export RELAY_LOG_FILE="$state_dir/relay.log"
  export ROUTING_LEDGER_FILE="$state_dir/routing-ledger.jsonl"
  set +e
  "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$state_dir/output.log" 2>&1
  local rc=$?
  set -e
  [ "$rc" -eq 1 ]   # DEADLINE_REACHED -> exit 1
}

printf -- '-- B1 --wait happy path --\n'
{
  s=$(new_state)
  happy_state="$s"
  export COMPANION_POLL_INTERVAL_SEC=0.5
  export WATCH_DEADLINE_SEC=4
  run_wait_companion "$s" candidate_absent 1
  # (1) check --wait 명령이 실제로 불렸다.
  rg -q -- '--wait' "$s/calls.log"
  # (2) keepalive 가 COMPANION_ALIVE 마커로 실시간 변환됐다("대기 중" 증거).
  [ "$(count 'COMPANION_ALIVE mode=wait' "$s/output.log")" -ge 1 ]
  # (3) 매 대기 주기마다 COMPANION_WAITED 활동 흔적이 있다.
  [ "$(count 'COMPANION_WAITED' "$s/output.log")" -ge 1 ]
  # (4) --wait 를 지원하므로 폴백 로그가 없어야 한다.
  assert_absent 'COMPANION_WAIT_FALLBACK' "$s/output.log"
  # (5) 배달 처리는 --wait 경로에서도 그대로 된다(misrouted wake 1회).
  [ "$(count 'misrouted_human_decision:task_candidate' "$s/project-sends.log")" -eq 1 ]
  # (6) raw keepalive JSON 이 output 에 새어나가지 않는다(stdout/stderr 분리).
  assert_absent '"_keepalive"' "$s/output.log"
  # (7) 실제 wait 뒤 sleep 이 다시 붙지 않았다. 이 fixture의 전체 판정 비용까지 넣어
  # 정상은 4초 동안 6회 이상, 0.5초 sleep 변형은 그 아래로 갈린다.
  [ "$(count '--wait' "$s/calls.log")" -ge 6 ]
  export COMPANION_POLL_INTERVAL_SEC=0.05
  export WATCH_DEADLINE_SEC=1
  printf 'PASS --wait happy path: keepalive->COMPANION_ALIVE, COMPANION_WAITED, no fallback, delivery processed, stdout clean\n'
}

printf -- '-- B1 fallback path: 조용한 폴백 금지 --\n'
{
  s=$(new_state)
  run_wait_companion "$s" candidate_absent 0
  # (1) 폴백 사실이 정확히 1회 로그에 남는다(조용한 강등 금지).
  [ "$(count 'COMPANION_WAIT_FALLBACK reason=wait_help_absent' "$s/output.log")" -eq 1 ]
  # (2) 폴백이므로 --wait 명령은 불리지 않는다.
  assert_absent -- '--wait' "$s/calls.log"
  # (3) keepalive 마커는 없다(대기하지 않으므로).
  assert_absent 'COMPANION_ALIVE mode=wait' "$s/output.log"
  # (4) 배달 처리는 폴백에서도 된다.
  [ "$(count 'misrouted_human_decision:task_candidate' "$s/project-sends.log")" -eq 1 ]
  printf 'PASS fallback path: COMPANION_WAIT_FALLBACK logged once, no --wait call, delivery processed\n'
}

printf -- '-- B1 정상 판정: ALIVE / UNKNOWN / DEAD --\n'
{
  run_health_battery() {
    local tmp fresh now out rc
    tmp=$(mktemp /tmp/orca-b1-health.XXXXXX)
    fresh=60
    now=$(date +%s)
    # 사례1 대기 중(COMPANION_ALIVE, 12s 전): 정상은 ALIVE.
    printf 'COMPANION_ALIVE mode=wait elapsed_ms=15001 wait_ms=60000\n' > "$tmp"
    out=$("$COMPANION" --health-log "$tmp" --freshness-sec "$fresh" --now-epoch $((now + 12))); rc=$?
    [ "$rc" -eq 0 ] || return 1
    # 사례2 죽은(오래된, 200s): 정상은 DEAD.
    printf 'COMPANION_WAITED wait_ms=60000 check_status=0\n' > "$tmp"
    out=$("$COMPANION" --health-log "$tmp" --freshness-sec "$fresh" --now-epoch $((now + 200))); rc=$?
    [ "$rc" -eq 2 ] || return 1
    # 사례3 SELF_EXIT(치명): 정상은 DEAD.
    printf 'SELF_EXIT consumer_owner_mismatch streak=3 self_exit=true\n' > "$tmp"
    out=$("$COMPANION" --health-log "$tmp" --freshness-sec "$fresh" --now-epoch "$now"); rc=$?
    [ "$rc" -eq 2 ] || return 1
    # 사례4~7: 최근 실패·포화·임의 문자열은 정상도 죽음도 아닌 UNKNOWN(3).
    # 단발 분류를 보는 자리라 --health-classify 를 쓴다(--health-log 는 재측정까지 한다).
    for unhealthy in \
      'CHECK_DIAGNOSTIC check_failed' \
      'WAKE_FAIL term_supervisor' \
      'gate_nudge_suppressed reason=inbox_saturated wake=0' \
      'arbitrary recent text'; do
      printf '%s\n' "$unhealthy" > "$tmp"
      set +e
      out=$("$COMPANION" --health-classify "$tmp" --freshness-sec "$fresh" --now-epoch $((now + 12))); rc=$?
      set -e
      [ "$rc" -eq 3 ] || return 1
      printf '%s' "$out" | rg -q '^UNKNOWN '
    done
    return 0
  }
  run_health_battery || { printf 'FAIL health battery\n' >&2; exit 1; }
  printf 'PASS health: healthy wait->ALIVE, stale/self-exit->DEAD, errors/saturation/unclassified->UNKNOWN\n'
}

printf -- '-- F-B1-2 응답 파일 없음은 DEAD 가 아니라 UNKNOWN --\n'
{
  # 죽음(사실)과 모름(무지)이 같은 값으로 접히면, 모름을 담을 값을 만들어 둔 의미가
  # 없어진다. 없는 파일은 죽음의 증거가 아니다. 대조군으로 "진짜 죽은" 두 상태를 같은
  # 판정기에 넣어 그쪽은 여전히 DEAD 로 갈리는지 함께 센다.
  s=$(new_state)
  now=$(date +%s)
  missing="$s/never-created.log"
  [ ! -e "$missing" ]
  set +e
  out=$("$COMPANION" --health-classify "$missing" --freshness-sec 60 --now-epoch "$now"); rc=$?
  set -e
  [ "$rc" -eq 3 ] || { printf 'FAIL no_log rc=%s (want 3=UNKNOWN)\n' "$rc" >&2; exit 1; }
  printf '%s' "$out" | rg -q '^UNKNOWN reason=no_log'
  # 모름은 행동을 부르지 않는다. (-v 는 줄 단위 반전이라 여러 줄에서 헐거워진다.
  # 부재는 ! + -q 로 확인한다.)
  printf '%s' "$out" | rg -q 'next_action=remeasure'
  ! printf '%s' "$out" | rg -q 'retire'

  # 대조군 1: SELF_EXIT 은 자기가 죽었다고 적은 사실 -> DEAD.
  dead1="$s/self-exit.log"
  printf 'SELF_EXIT consumer_owner_mismatch streak=3 self_exit=true\n' > "$dead1"
  set +e
  out=$("$COMPANION" --health-classify "$dead1" --freshness-sec 60 --now-epoch "$now"); rc=$?
  set -e
  [ "$rc" -eq 2 ] || { printf 'FAIL self_exit rc=%s (want 2=DEAD)\n' "$rc" >&2; exit 1; }
  printf '%s' "$out" | rg -q '^DEAD reason=self_exit'

  # 대조군 2: 신선도 창을 넘긴 로그 -> DEAD(살아 있으면 찍혔어야 할 흔적이 없다).
  dead2="$s/stale.log"
  printf 'COMPANION_WAITED wait_ms=60000 check_status=0\n' > "$dead2"
  set +e
  out=$("$COMPANION" --health-classify "$dead2" --freshness-sec 60 --now-epoch $((now + 200))); rc=$?
  set -e
  [ "$rc" -eq 2 ] || { printf 'FAIL log_stale rc=%s (want 2=DEAD)\n' "$rc" >&2; exit 1; }
  printf '%s' "$out" | rg -q '^DEAD reason=log_stale'
  printf 'PASS no_log->UNKNOWN(remeasure); controls self_exit->DEAD, log_stale->DEAD\n'
}

printf -- '-- F-B1-2 UNKNOWN 은 재측정으로 가고 행동하지 않는다 --\n'
{
  # 모름의 유일한 다음 행동은 다시 재는 것이다. 재측정 없이 행동하면 UNKNOWN 은
  # 이름만 다른 DEAD 가 된다. 기본 입구(--health-log)는 재측정이 켜져 있어야 하고,
  # 재측정을 다 쓰고도 모르면 UNKNOWN 과 **구분되는 이름**으로 닫아야 한다.
  s=$(new_state)
  now=$(date +%s)
  export COMPANION_HEALTH_REMEASURE_GAP_SEC=0
  unknown_log="$s/unknown.log"
  printf 'CHECK_DIAGNOSTIC check_failed\n' > "$unknown_log"
  set +e
  out=$("$COMPANION" --health-log "$unknown_log" --freshness-sec 60 --now-epoch $((now + 12))); rc=$?
  set -e
  # (1) 재측정 판정은 UNKNOWN(3)도 DEAD(2)도 아닌 자기 이름과 자기 코드를 가진다.
  [ "$rc" -eq 4 ] || { printf 'FAIL unknown rc=%s (want 4=UNRESOLVED)\n' "$rc" >&2; exit 1; }
  printf '%s' "$out" | rg -q '^UNRESOLVED reason=unknown_after_remeasure'
  # (2) 실제로 3회 관측했다(최초 1 + 재측정 2). 세어서 확인한다.
  obs=$(printf '%s\n' "$out" | rg -c '^HEALTH_OBSERVATION ' || printf '0\n')
  [ "$obs" -eq 3 ] || { printf 'FAIL observations=%s (want 3)\n' "$obs" >&2; exit 1; }
  printf '%s' "$out" | rg -q 'HEALTH_OBSERVATION attempt=3/3 '
  # (3) 모름 끝에 종료 같은 행동을 지시하지 않는다.
  printf '%s' "$out" | rg -q 'next_action=report_no_retire'
  ! printf '%s' "$out" | rg -q 'next_action=retire_new_companion'

  # (4) 응답 파일 없음도 같은 재측정 경로를 탄다(DEAD 로 접히지 않는다).
  set +e
  out=$("$COMPANION" --health-log "$s/absent.log" --freshness-sec 60 --now-epoch "$now"); rc=$?
  set -e
  [ "$rc" -eq 4 ] || { printf 'FAIL no_log remeasure rc=%s (want 4)\n' "$rc" >&2; exit 1; }
  printf '%s' "$out" | rg -q '^UNRESOLVED '

  # 대조군: 사실이 확인되면 재측정하지 않고 즉시 닫는다. 관측 1회다.
  alive_log="$s/alive.log"
  printf 'COMPANION_ALIVE mode=wait elapsed_ms=15001 wait_ms=60000\n' > "$alive_log"
  set +e
  out=$("$COMPANION" --health-log "$alive_log" --freshness-sec 60 --now-epoch $((now + 12))); rc=$?
  set -e
  [ "$rc" -eq 0 ] || { printf 'FAIL alive rc=%s (want 0)\n' "$rc" >&2; exit 1; }
  [ "$(printf '%s\n' "$out" | rg -c '^HEALTH_OBSERVATION ' || printf '0\n')" -eq 1 ]
  dead_log="$s/dead.log"
  printf 'SELF_EXIT consumer_owner_mismatch streak=3 self_exit=true\n' > "$dead_log"
  set +e
  out=$("$COMPANION" --health-log "$dead_log" --freshness-sec 60 --now-epoch "$now"); rc=$?
  set -e
  [ "$rc" -eq 2 ] || { printf 'FAIL dead rc=%s (want 2)\n' "$rc" >&2; exit 1; }
  # 죽음이 사실로 확인된 경우에만 종료 행동이 붙는다.
  printf '%s' "$out" | rg -q 'next_action=retire_new_companion'
  [ "$(printf '%s\n' "$out" | rg -c '^HEALTH_OBSERVATION ' || printf '0\n')" -eq 1 ]
  unset COMPANION_HEALTH_REMEASURE_GAP_SEC
  printf 'PASS UNKNOWN->3 observations->UNRESOLVED(report_no_retire); controls ALIVE/DEAD close in 1 observation\n'
}

printf -- '-- F-B1-3 UNRESOLVED 를 실제로 소비하는 운영 경로 --\n'
{
  # 값을 만드는 것 / 밖으로 내는 것 / 소비자가 쓰는 것은 각각 다른 일이다. 앞 라운드는
  # UNRESOLVED(exit 4)와 행동표까지 만들어 놓고 그 값을 받는 운영 코드가 0개였다.
  # 여기서는 소비자가 실제로 exit 4 를 받아 (1) 행동을 report_no_retire 로 고르고
  # (2) 감독에게 보고를 보내고 (3) 아무것도 내리지 않는지를 본다.
  s=$(new_state)
  now=$(date +%s)
  export COMPANION_HEALTH_REMEASURE_GAP_SEC=0
  export FAKE_ORCA_STATE_DIR="$s"
  export ORCA_BIN="$FIXTURE"
  sends="$s/project-sends.log"
  # 연속 횟수 상태 파일의 기본 유도 경로(로그 경로 -> TMPDIR)를 그대로 시험한다.
  # TMPDIR 을 이 판 상태 폴더로 돌려 매 실행이 깨끗한 0에서 시작하게 한다.
  saved_tmpdir="${TMPDIR:-}"
  export TMPDIR="$s"

  unresolved_log="$s/decide-unknown.log"
  printf 'CHECK_DIAGNOSTIC check_failed\n' > "$unresolved_log"
  set +e
  out=$("$COMPANION" --health-decide "$unresolved_log" --run run_project \
        --freshness-sec 60 --now-epoch $((now + 12))); rc=$?
  set -e
  [ "$rc" -eq 4 ] || { printf 'FAIL decide unresolved rc=%s (want 4)\n' "$rc" >&2; exit 1; }
  printf '%s\n' "$out" | rg -q '^HEALTH_DECISION action=report_no_retire rc=4 verdict=UNRESOLVED unresolved_streak=1$'
  # 보고가 실제로 나갔다. 편지 장부에 정확히 1통, escalation 으로.
  printf '%s\n' "$out" | rg -q '^HEALTH_REPORT_SENT run=run_project verdict=UNRESOLVED unresolved_streak=1$'
  [ "$(count '--type escalation' "$sends")" -eq 1 ] \
    || { printf 'FAIL report letters=%s (want 1)\n' "$(count '--type escalation' "$sends")" >&2; exit 1; }
  # 모름은 내리지 않는다: 소비자가 고른 행동에 종료가 섞이지 않는다.
  ! printf '%s\n' "$out" | rg -q 'HEALTH_DECISION action=retire_new_companion'

  # 대조군 1 — ALIVE 는 진행이고 보고를 만들지 않는다(장부는 1통 그대로).
  alive_log="$s/decide-alive.log"
  printf 'COMPANION_ALIVE mode=wait elapsed_ms=15001 wait_ms=60000\n' > "$alive_log"
  set +e
  out=$("$COMPANION" --health-decide "$alive_log" --run run_project \
        --freshness-sec 60 --now-epoch $((now + 12))); rc=$?
  set -e
  [ "$rc" -eq 0 ] || { printf 'FAIL decide alive rc=%s (want 0)\n' "$rc" >&2; exit 1; }
  printf '%s\n' "$out" | rg -q '^HEALTH_DECISION action=proceed rc=0 verdict=ALIVE unresolved_streak=0$'
  [ "$(count '--type escalation' "$sends")" -eq 1 ]

  # 대조군 2 — DEAD 만 종료 행동을 낸다. 이 자리가 비면 시험 자체가 고장난 것이다.
  dead_log="$s/decide-dead.log"
  printf 'SELF_EXIT consumer_owner_mismatch streak=3 self_exit=true\n' > "$dead_log"
  set +e
  out=$("$COMPANION" --health-decide "$dead_log" --run run_project \
        --freshness-sec 60 --now-epoch "$now"); rc=$?
  set -e
  [ "$rc" -eq 2 ] || { printf 'FAIL decide dead rc=%s (want 2)\n' "$rc" >&2; exit 1; }
  printf '%s\n' "$out" | rg -q '^HEALTH_DECISION action=retire_new_companion rc=2 verdict=DEAD unresolved_streak=0$'
  [ "$(count '--type escalation' "$sends")" -eq 1 ]

  # 보고를 못 보내는 경우에도 조용히 넘어가지 않고, 그래도 내리지 않는다.
  set +e
  out=$("$COMPANION" --health-decide "$unresolved_log" \
        --freshness-sec 60 --now-epoch $((now + 12))); rc=$?
  set -e
  [ "$rc" -eq 4 ] || { printf 'FAIL decide unresolved(no run) rc=%s (want 4)\n' "$rc" >&2; exit 1; }
  # 같은 로그의 두 번째 모름이므로 연속 2회다. 다른 로그의 ALIVE/DEAD 는 이 연속을 끊지
  # 않는다 — 연속은 그 companion 하나에 대한 이야기다.
  printf '%s\n' "$out" | rg -q '^HEALTH_REPORT_UNDELIVERED reason=no_run verdict=UNRESOLVED unresolved_streak=2$'
  printf '%s\n' "$out" | rg -q '^HEALTH_DECISION action=report_no_retire rc=4 verdict=UNRESOLVED unresolved_streak=2$'
  [ "$(count '--type escalation' "$sends")" -eq 1 ]

  # 연속은 사실이 확인되면 끊긴다. 같은 로그가 ALIVE 로 바뀌면 0으로 돌아가고,
  # 그 뒤 다시 모르면 3이 아니라 1에서 다시 센다. 임계값은 코드에 없고 숫자만 나간다.
  printf 'COMPANION_ALIVE mode=wait elapsed_ms=15001 wait_ms=60000\n' > "$unresolved_log"
  set +e
  out=$("$COMPANION" --health-decide "$unresolved_log" --run run_project \
        --freshness-sec 60 --now-epoch $((now + 12))); rc=$?
  set -e
  [ "$rc" -eq 0 ] || { printf 'FAIL streak reset rc=%s (want 0)\n' "$rc" >&2; exit 1; }
  printf '%s\n' "$out" | rg -q '^HEALTH_DECISION action=proceed rc=0 verdict=ALIVE unresolved_streak=0$'
  printf 'CHECK_DIAGNOSTIC check_failed\n' > "$unresolved_log"
  set +e
  out=$("$COMPANION" --health-decide "$unresolved_log" --run run_project \
        --freshness-sec 60 --now-epoch $((now + 12))); rc=$?
  set -e
  [ "$rc" -eq 4 ] || { printf 'FAIL streak restart rc=%s (want 4)\n' "$rc" >&2; exit 1; }
  printf '%s\n' "$out" | rg -q '^HEALTH_DECISION action=report_no_retire rc=4 verdict=UNRESOLVED unresolved_streak=1$'
  # 편지에도 연속 횟수가 들어간다(코드는 세기만 하고 판단은 사람이 한다).
  [ "$(count 'unresolved_streak=1' "$sends")" -ge 1 ]

  if [ -n "$saved_tmpdir" ]; then export TMPDIR="$saved_tmpdir"; else unset TMPDIR; fi
  unset COMPANION_HEALTH_REMEASURE_GAP_SEC
  printf 'PASS UNRESOLVED(exit 4) 소비자: action=report_no_retire + 보고 1통(연속 횟수 포함), 연속 1->2 누적 후 사실 확인으로 0, ALIVE=proceed/DEAD=retire 대조군\n'
}

printf -- '-- B1 즉시 오류는 wait 성공이 아니며 빠르게 재호출하지 않는다 --\n'
{
  s=$(new_state)
  export COMPANION_POLL_INTERVAL_SEC=0.2
  export FAKE_CHECK_FAILURE=consumer_fenced
  run_wait_companion "$s" candidate_absent 1
  unset FAKE_CHECK_FAILURE
  calls=$(count '--wait' "$s/calls.log")
  [ "$calls" -le 6 ]
  [ "$(count 'COMPANION_WAIT_FAILED' "$s/output.log")" -ge 1 ]
  assert_absent 'COMPANION_WAITED' "$s/output.log"
  printf 'PASS immediate error pacing: wait_calls=%s (1s, max=6), failed marker present, success marker absent\n' "$calls"
  export COMPANION_POLL_INTERVAL_SEC=0.05
}

# 실제 소스 복사본 10개를 바꾸고, 바뀐 문자열을 다시 확인한 뒤 이 focused 시험이
# 모두 거부하는지 센다. 적용 실패는 rejected 에 넣지 않고 unmeasured 로 센다.
if [ "${B1_SKIP_MUTATIONS:-0}" != 1 ]; then
  printf -- '-- B1 실제 소스 변형 16개 --\n'
  mutation_root=$(mktemp -d /tmp/orca-b1-mutants.XXXXXX)
  tried=0; applied=0; rejected=0; unmeasured=0
  for mutant in dead_as_alive silent_fallback remove_wait remove_keepalive sleep_after_wait \
                no_log_as_dead unknown_retires no_remeasure unresolved_named_unknown remeasure_count_zero \
                decide_unresolved_retires decide_report_dropped decide_report_silent_failure \
                decide_dead_never_retires decide_streak_not_counted decide_streak_never_resets; do
    tried=$((tried + 1))
    mutant_script="$mutation_root/$mutant.sh"
    cp "$SKILL_DIR/scripts/conductor-companion.sh" "$mutant_script"
    before=$(shasum -a 256 "$mutant_script" | awk '{print $1}')
    case "$mutant" in
      dead_as_alive) perl -0pi -e 's/if grep -q '\''\^SELF_EXIT '\''/if false \&\& grep -q '\''^SELF_EXIT '\''/' "$mutant_script" ;;
      silent_fallback) perl -0pi -e 's/echo "COMPANION_WAIT_FALLBACK reason=wait_help_absent poll_interval=\$POLL_INTERVAL"/: # mutant silent fallback/' "$mutant_script" ;;
      remove_wait) perl -0pi -e 's/\*"--wait"\*\) WAIT_CAPABLE=1/\*"--wait"\*\) WAIT_CAPABLE=0/' "$mutant_script" ;;
      remove_keepalive) perl -0pi -e 's/echo "COMPANION_ALIVE mode=wait/echo "COMPANION_MARKER_REMOVED mode=wait/' "$mutant_script" ;;
      sleep_after_wait) perl -0pi -e 's/if \[ "\$DID_WAIT_THIS_CYCLE" = 1 \]; then/if [ "$DID_WAIT_THIS_CYCLE" = 2 ]; then/' "$mutant_script" ;;
      # F-B1-2: 모름이 다시 아는 값으로 붕괴하는 4가지 방식 + 재측정을 껍데기로 만드는 1가지.
      # (1) 응답 파일 없음을 죽음이라고 우기기.
      no_log_as_dead) perl -0pi -e 's/UNKNOWN reason=no_log next_action=remeasure"; return 3/DEAD reason=no_log"; return 2/' "$mutant_script" ;;
      # (2) 모름을 근거로 종료를 지시하기.
      unknown_retires) perl -0pi -e 's/next_action=remeasure/next_action=retire_new_companion/g' "$mutant_script" ;;
      # (3) 재측정을 건너뛰고 맨 UNKNOWN 을 호출자에게 넘기기(모든 입구에서).
      no_remeasure) perl -0pi -e 's/judge_companion_health_with_remeasure "/judge_companion_health "/g' "$mutant_script" ;;
      # (4) 재측정 끝 판정을 UNKNOWN 과 같은 이름으로 부르기.
      unresolved_named_unknown) perl -0pi -e 's/echo "UNRESOLVED reason=/echo "UNKNOWN reason=/' "$mutant_script" ;;
      # (5) 재측정 횟수를 0으로 만들어 계약을 껍데기만 남기기.
      remeasure_count_zero) perl -0pi -e 's/HEALTH_REMEASURE_COUNT=2/HEALTH_REMEASURE_COUNT=0/' "$mutant_script" ;;
      # F-B1-3: 소비자가 UNRESOLVED 를 받고도 값을 안 쓰는 4가지 방식.
      # (6) 모름을 근거로 내려버리기 — 소비자 자리에서 다시 모름=죽음으로 접는다.
      decide_unresolved_retires) perl -0pi -e 's/    4\) action=report_no_retire ;;/    4) action=retire_new_companion ;;/' "$mutant_script" ;;
      # (7) 행동만 고르고 보고로는 안 잇기 — 값이 밖으로 안 나간다.
      decide_report_dropped) perl -0pi -e 's/    report_health_unresolved "\$verdict" "\$streak" \|\| true/    : # mutant: no report/' "$mutant_script" ;;
      # (8) 보고 실패를 조용히 삼키기.
      decide_report_silent_failure) perl -0pi -e 's/HEALTH_REPORT_UNDELIVERED reason=no_run/HEALTH_REPORT_QUIET reason=no_run/' "$mutant_script" ;;
      # (9) 반대 방향: 죽음이 확인돼도 아무 행동을 안 고르면 표 자체가 껍데기다.
      decide_dead_never_retires) perl -0pi -e 's/    2\) action=retire_new_companion ;;/    2) action=report_no_retire ;;/' "$mutant_script" ;;
      # (10) 연속 횟수를 안 세고 늘 1이라고 우기기 — 한 번과 여러 번을 구분 못 하게 된다.
      decide_streak_not_counted) perl -0pi -e 's/    streak=\$\(\( \$\(read_health_streak "\$streak_file"\) \+ 1 \)\)/    streak=1/' "$mutant_script" ;;
      # (11) 사실이 확인돼도 연속을 안 끊기 — 끊기지 않는 연속 횟수는 근거가 아니다.
      decide_streak_never_resets) perl -0pi -e 's/if \[ -f "\$streak_file" \]; then : > "\$streak_file" 2>\/dev\/null \|\| true; fi/: # mutant: no reset/' "$mutant_script" ;;
    esac
    after=$(shasum -a 256 "$mutant_script" | awk '{print $1}')
    if [ "$before" = "$after" ]; then
      unmeasured=$((unmeasured + 1))
      printf 'MUTATION_UNMEASURED name=%s reason=not_applied\n' "$mutant"
      continue
    fi
    applied=$((applied + 1))
    chmod +x "$mutant_script"
    set +e
    B1_COMPANION_UNDER_TEST="$mutant_script" B1_SKIP_MUTATIONS=1 bash "$0" > "$mutation_root/$mutant.log" 2>&1
    mutant_rc=$?
    set -e
    if [ "$mutant_rc" -ne 0 ] && [ "$mutant_rc" -ne 126 ] && [ "$mutant_rc" -ne 127 ]; then
      rejected=$((rejected + 1))
      printf 'MUTATION_REJECTED name=%s rc=%s\n' "$mutant" "$mutant_rc"
    elif [ "$mutant_rc" -eq 126 ] || [ "$mutant_rc" -eq 127 ]; then
      unmeasured=$((unmeasured + 1))
      printf 'MUTATION_UNMEASURED name=%s rc=%s\n' "$mutant" "$mutant_rc"
    else
      printf 'MUTATION_SURVIVED name=%s rc=0\n' "$mutant"
    fi
  done
  printf 'mutation evidence: tried=%s applied=%s rejected=%s unmeasured=%s\n' "$tried" "$applied" "$rejected" "$unmeasured"
  # `A && B && C` 는 set -e 로 안 멈춘다(중간 항목은 errexit 면제, 실측 확인).
  # 그래서 수가 틀렸는데도 초록불이 나오던 자리다. 명시적으로 떨어뜨린다.
  if [ "$tried" -ne 16 ] || [ "$applied" -ne "$tried" ] \
     || [ "$rejected" -ne "$applied" ] || [ "$unmeasured" -ne 0 ]; then
    printf 'FAIL mutation evidence: tried=%s applied=%s rejected=%s unmeasured=%s (want 16/16/16/0)\n' \
      "$tried" "$applied" "$rejected" "$unmeasured" >&2
    exit 1
  fi

  printf -- '-- B1 0건 검색 대조군 --\n'
  control_file=$(mktemp /tmp/orca-b1-search-control.XXXXXX)
  printf '%s\n' \
    'COMPANION_HEALTH_JUDGE_MODE=always_alive' \
    'COMPANION_TEST_SUPPRESS_FALLBACK=1' \
    'rm -f "$stdout_file"' > "$control_file"
  controls=0
  for pattern in COMPANION_HEALTH_JUDGE_MODE COMPANION_TEST_SUPPRESS_FALLBACK 'rm -f'; do
    # 운영 소스에서는 0건이어야 하고, 같은 검색기로 심은 대조군은 1건이어야 한다.
    if ! rg -q -- "$pattern" "$SKILL_DIR/scripts/conductor-companion.sh" \
      && [ "$(count "$pattern" "$control_file")" -eq 1 ]; then
      controls=$((controls + 1))
    fi
  done
  # 성공 wait 표식 검색기는 정상 경로에서 1건 이상을 실제로 잡아야 한다.
  if [ "$(count 'COMPANION_WAITED' "$happy_state/output.log")" -ge 1 ]; then
    controls=$((controls + 1))
  fi
  printf 'control evidence: passed=%s total=4\n' "$controls"
  if [ "$controls" -ne 4 ]; then
    printf 'FAIL control evidence: passed=%s (want 4)\n' "$controls" >&2
    exit 1
  fi
  printf 'B1_SCORE baseline=8/8 mutations=%s/%s controls=%s/4\n' "$rejected" "$applied" "$controls"
fi

printf -- '-- H2 ack 실패 시 미확인 배치 재생 고리 페이싱 --\n'
{
  # ack 가 계속 실패하면 배달이 우편함에 남아 check --wait 가 같은 배치를 즉시
  # 다시 준다. wait 성공 주기에는 sleep 이 없으므로, ack 실패를 페이싱 신호로
  # 바꾸지 않은 변형은 이 시험 조건에서 초과 호출로 드러난다
  # (2026-08-11 실측: 수정본 3~5회 / 페이싱 없는 변형 7~12회, 4초 기준).
  s=$(new_state)
  export FAKE_ORCA_STATE_DIR="$s"
  export FAKE_RELAY_ALERT_MODE=candidate_absent
  export FAKE_DELIVERY_MODE=worker_done
  export FAKE_WAIT_SUPPORT=1
  export FAKE_WAIT_DELAY=0
  export FAKE_ACK_FAIL=1
  export ORCA_BIN="$FIXTURE"
  export RELAY_LOG_FILE="$s/relay.log"
  export ROUTING_LEDGER_FILE="$s/routing-ledger.jsonl"
  export COMPANION_POLL_INTERVAL_SEC=0.5
  export WATCH_DEADLINE_SEC=4
  set +e
  "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$s/output.log" 2>&1
  rc=$?
  set -e
  [ "$rc" -eq 1 ]   # DEADLINE_REACHED -> exit 1
  # (1) 재생이 실제로 일어났다(배달이 남아 wait 가 반복 호출됐다).
  [ "$(count '--wait' "$s/calls.log")" -ge 2 ]
  # (2) 그래도 호출 간격은 POLL_INTERVAL(0.5s)로 잡힌다 — 4초에 6회 이하여야 한다.
  [ "$(count '--wait' "$s/calls.log")" -le 6 ]
  # (3) ack 시도도 같은 상한 안에 있다.
  [ "$(wc -l < "$s/acks.log" | tr -d ' ')" -le 6 ]
  # (4) ack 실패 진단이 로그에 남는다.
  [ "$(count 'CHECK_DIAGNOSTIC ack_failed' "$s/output.log")" -ge 1 ]
  # (5) 같은 배달이 재생돼도 부작용(SIGNAL)은 중복되지 않는다.
  [ "$(count '^SIGNAL worker_done' "$s/output.log")" -eq 1 ]
  unset FAKE_ACK_FAIL
  export COMPANION_POLL_INTERVAL_SEC=0.05
  export WATCH_DEADLINE_SEC=1
  printf 'PASS H2: ack failure replays unacked batch but loop paced by POLL_INTERVAL, side effects deduped\n'
}

printf 'PASS B1 wait/fallback/health focused suite\n'
