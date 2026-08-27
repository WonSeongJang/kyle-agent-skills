#!/bin/bash
set -euo pipefail
# -E(errtrace): ERR 트랩은 함수 안에서 상속되지 않는다. 켜지 않으면
# 실패한 줄과 명령이 "불명"으로 나와 판정 문구가 반쪽이 된다.
set -E

# companion 지속 신분 불일치 자기 종료 + streak reset + 기동 exit 4 시험.
# owner mismatch 와 roster resolve 실패는 서로 다른 종류별 연속 횟수로 다룬다.
# Track G 551ae18 의 강한 roster 신분 확인과 NUDGE/MISSING_RELAY 상태 계약도 함께 본다.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
COMPANION="$SKILL_DIR/scripts/conductor-companion.sh"
FIXTURE="$SCRIPT_DIR/fixtures/orca"
export COMPANION_POLL_INTERVAL_SEC=0.05
TEST_WAIT_CEILING_SEC="${TEST_WAIT_CEILING_SEC:-60}"
export FAKE_ENTER_MODE=ok
export ORCA_TERMINAL_HANDLE=term_supervisor

# F-B7(2026-08-09): 조용히 죽지 못하게 한다. 사연은 test-conductor-companion.sh 의 같은
# 주석과 같다 — 맨 `[ ... ]` 단언이 `set -e` 로 죽으면 FAIL 한 줄도 안 남는다.
STATE_FAIL_LINE=""
STATE_FAIL_CMD=""
trap 'STATE_FAIL_LINE=$LINENO; STATE_FAIL_CMD=$BASH_COMMAND' ERR

# F-B9-2(2026-08-09): 실행 불가(126/127)를 성적에서 빼고 자기 칸에 넣는다.
# 사연과 관문 처리 근거는 test-conductor-companion.sh 의 같은 주석과 같다.
# 이 파일은 특히 위험했다 — 직전 판에서 126/127 을 만나면 `return 0` 이라
# 아무것도 못 쟀는데 초록불로 넘어갔다(초록불 위장).
TEST_UNAVAILABLE_EXIT=9
unavailable_kind() {
  case "$1" in
    126) printf 'permission_denied(실행 권한 없음)' ;;
    127) printf 'not_found(부를 파일 못 찾음)' ;;
    *) printf 'unknown' ;;
  esac
}
STATE_UNAVAIL_STATUS=""
state_unavailable_stop() {
  local status="$1" expected="$2"
  STATE_UNAVAIL_STATUS="$status"
  printf 'TEST_EXECUTION_UNAVAILABLE status=%s kind=%s expected=%s\n' \
    "$status" "$(unavailable_kind "$status")" "$expected" >&2
  exit "$TEST_UNAVAILABLE_EXIT"
}
# F-B9-2: 배경 실행(`&`) 뒤의 `wait $pid` 는 126/127 을 못 준다 — 실측 결과 1 이 나와서
# 진짜 불합격과 구분되지 않는다(자세한 사연은 test-conductor-companion.sh 의 같은 주석).
# 그래서 판정을 실행 전으로 옮긴다. 여기서 걸리면 성적이 아니라 실행 불가다.
require_runnable() {
  local target="$1" expected="$2"
  [ -e "$target" ] || state_unavailable_stop 127 "$expected (target=$target)"
  [ -x "$target" ] || state_unavailable_stop 126 "$expected (target=$target)"
}
state_suite_verdict() {
  local rc=$?
  if [ "$rc" -eq "$TEST_UNAVAILABLE_EXIT" ]; then
    local s126=0 s127=0
    [ "$STATE_UNAVAIL_STATUS" = 126 ] && s126=1
    [ "$STATE_UNAVAIL_STATUS" = 127 ] && s127=1
    printf 'UNAVAILABLE test-conductor-companion-state.sh exit=%s unavailable=1 status126=%s status127=%s (성적 아님: 합격에도 불합격에도 안 넣음, 관문은 통과 못 함)\n' \
      "$rc" "$s126" "$s127" >&2
    printf 'UNAVAILABLE test-conductor-companion-state.sh exit=%s unavailable=1 status126=%s status127=%s (성적 아님: 합격에도 불합격에도 안 넣음, 관문은 통과 못 함)\n' \
      "$rc" "$s126" "$s127"
    exit "$rc"
  fi
  if [ "$rc" -ne 0 ]; then
    printf 'FAIL test-conductor-companion-state.sh exit=%s line=%s cmd=%s\n' \
      "$rc" "${STATE_FAIL_LINE:-불명}" "${STATE_FAIL_CMD:-불명}" >&2
    printf 'FAIL test-conductor-companion-state.sh exit=%s line=%s cmd=%s\n' \
      "$rc" "${STATE_FAIL_LINE:-불명}" "${STATE_FAIL_CMD:-불명}"
  fi
  exit "$rc"
}
trap state_suite_verdict EXIT

# 판정 트랩을 건 뒤에 확인해야 UNAVAILABLE 판정 문구가 실제로 찍힌다.
require_runnable "$COMPANION" 'suite subject: conductor-companion.sh'
require_runnable "$FIXTURE" 'suite fixture: fake orca CLI'

new_state() {
  mktemp -d /tmp/orca-companion-state.XXXXXX
}
# F-B7: 파일 부재(-1)와 0줄을 구분해서 센다. 부재를 0건으로 읽으면 "안 생겼다"가
# "생겼는데 비었다"로 둔갑한다.
count_lines() {
  local file="$1"
  [ -f "$file" ] || { printf -- '-1\n'; return 0; }
  wc -l < "$file" | tr -d ' '
}
count_matches() {
  local pattern="$1" file="$2"
  [ -f "$file" ] || { printf '0\n'; return 0; }
  rg -c -- "$pattern" "$file" 2>/dev/null || printf '0\n'
}
assert_absent() {
  local pattern="$1" file="$2"
  if [ -f "$file" ] && rg -q -- "$pattern" "$file"; then
    printf 'ASSERT_ABSENT_FAIL pattern=%s file=%s\n' "$pattern" "$file" >&2
    return 1
  fi
}
state_now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000'; }
wait_state_condition() {
  local pid="$1" state_dir="$2" expected="$3" condition="$4" started status elapsed
  started=$(state_now_ms)
  while kill -0 "$pid" 2>/dev/null; do
    if eval "$condition"; then
      elapsed=$(( $(state_now_ms) - started ))
      kill -TERM "$pid" 2>/dev/null || true
      set +e; wait "$pid"; status=$?; set -e
      run_status="$status"
      if [ "$status" -eq 0 ]; then
        printf 'CONDITION_MET expected=%s elapsed_ms=%s\n' "$expected" "$elapsed" >> "$state_dir/output.log"
      elif [ "$status" -eq 126 ] || [ "$status" -eq 127 ]; then
        state_unavailable_stop "$status" "$expected"
      fi
      return 0
    fi
    elapsed=$(( $(state_now_ms) - started ))
    [ "$elapsed" -lt $((TEST_WAIT_CEILING_SEC * 1000)) ] || break
    sleep 0.05
  done
  set +e; wait "$pid"; status=$?; set -e
  run_status="$status"
  if [ "$status" -eq 126 ] || [ "$status" -eq 127 ]; then
    state_unavailable_stop "$status" "$expected"
  fi
  if [ "$status" -ne 0 ] && [ "$status" -ne 1 ]; then return 0; fi
  printf 'CONDITION_WAIT_STALLED expected=%s\n' "$expected" >&2
  printf 'CONDITION_WAIT_ELAPSED elapsed_ms=%s ceiling_sec=%s\n' "$(( $(state_now_ms) - started ))" "$TEST_WAIT_CEILING_SEC" >&2
  printf 'CONDITION_WAIT_OBSERVED resolves=%s checks=%s output_tail=%s\n' \
    "$(count_matches '^resolve project-supervisor' "$state_dir/roster.log")" \
    "$(count_matches 'orchestration check' "$state_dir/calls.log")" \
    "$(tail -1 "$state_dir/output.log" 2>/dev/null || printf '<없음>')" >&2
  return 1
}
run_state_companion() {
  local state_dir="$1" requested_target="${2:-}"; shift
  export COMPANION_POLL_INTERVAL_SEC=0.05
  export FAKE_ORCA_STATE_DIR="$state_dir"
  export FAKE_RELAY_ALERT_MODE=clean
  export FAKE_DELIVERY_MODE=none
  export ORCA_BIN="$FIXTURE"
  export RELAY_LOG_FILE="$state_dir/relay.log"
  export ROUTING_LEDGER_FILE="$state_dir/routing-ledger.jsonl"
  local target=2
  [ -f "$state_dir/supervisor-handle-seq" ] && target=$(wc -l < "$state_dir/supervisor-handle-seq" | tr -d ' ')
  [ -n "$requested_target" ] && target="$requested_target"
  if [ "$requested_target" = natural ]; then
    set +e
    WATCH_DEADLINE_SEC="$TEST_WAIT_CEILING_SEC" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$state_dir/output.log" 2>&1
    run_status=$?
    set -e
    # 자기 종료 코드(4·5·6)는 성적이지만 126·127 은 companion 을 아예 못 돌렸다는 뜻이다.
    if [ "$run_status" -eq 126 ] || [ "$run_status" -eq 127 ]; then
      state_unavailable_stop "$run_status" 'companion natural self-exit'
    fi
    return 0
  fi
  WATCH_DEADLINE_SEC="$TEST_WAIT_CEILING_SEC" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$state_dir/output.log" 2>&1 &
  local pid=$!
  wait_state_condition "$pid" "$state_dir" "supervisor resolve sequence reached $target with every cycle classified" '[ "$(count_matches "^resolve project-supervisor" "$state_dir/roster.log")" -ge "$target" ] && [ "$(count_matches "^resolve project-supervisor" "$state_dir/roster.log")" -eq $(( $(count_matches "orchestration check --run run_project --json" "$state_dir/calls.log") + $(count_matches "CHECK_DIAGNOSTIC consumer_owner_mismatch streak=" "$state_dir/output.log") + $(count_matches "CHECK_DIAGNOSTIC supervisor_roster_unresolved streak=" "$state_dir/output.log") + 1 )) ]'
}

run_startup_mismatch_case() {
  local state_dir owner_status
  state_dir=$(new_state)
  export ORCA_TERMINAL_HANDLE=term_other
  set +e
  FAKE_ORCA_STATE_DIR="$state_dir" FAKE_RELAY_ALERT_MODE=clean FAKE_DELIVERY_MODE=none ORCA_BIN="$FIXTURE" RELAY_LOG_FILE="$state_dir/relay.log" ROUTING_LEDGER_FILE="$state_dir/routing-ledger.jsonl" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$state_dir/output.log" 2>&1
  owner_status=$?
  set -e
  # 앞의 실행 전 확인을 통과했더라도, 앞단 실행(foreground)은 126/127 을 정확히 준다.
  if [ "$owner_status" -eq 126 ] || [ "$owner_status" -eq 127 ]; then
    state_unavailable_stop "$owner_status" 'startup owner mismatch -> exit 4'
  fi
  [ "$owner_status" -eq 4 ]
  rg -q 'consumer_owner_mismatch' "$state_dir/output.log"
  assert_absent 'SELF_EXIT' "$state_dir/output.log"
  assert_absent 'orchestration check' "$state_dir/calls.log"
  export ORCA_TERMINAL_HANDLE=term_supervisor
  printf 'PASS startup owner mismatch -> immediate exit 4 (no streak self-exit)\n'
}

run_owner_mismatch_streak_case() {
  local state_dir
  state_dir=$(new_state)
  printf 'term_supervisor\nterm_drifted\nterm_drifted\nterm_drifted\n' > "$state_dir/supervisor-handle-seq"
  run_state_companion "$state_dir" natural
  [ "$run_status" -eq 5 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC consumer_owner_mismatch streak=' "$state_dir/output.log")" -eq 2 ]
  [ "$(count_matches 'SELF_EXIT consumer_owner_mismatch streak=3' "$state_dir/output.log")" -eq 1 ]
  [ ! -f "$state_dir/acks.log" ]
  printf 'PASS owner mismatch streak: 1-2 survive + no-ack, 3rd self-exit code 5\n'
}

run_owner_mismatch_reset_case() {
  local state_dir
  state_dir=$(new_state)
  printf 'term_supervisor\nterm_drifted\nterm_drifted\nterm_supervisor\nterm_drifted\nterm_drifted\nterm_supervisor\n' > "$state_dir/supervisor-handle-seq"
  run_state_companion "$state_dir"
  [ "$run_status" -eq 0 ]
  assert_absent 'SELF_EXIT' "$state_dir/output.log"
  printf 'PASS owner mismatch reset: 2 mismatch + 1 success resets, subsequent 1-2 fail no exit\n'
}

run_roster_fail_streak_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_SUPERVISOR_RESOLVE_FAIL_AFTER=1
  run_state_companion "$state_dir" natural
  [ "$run_status" -eq 6 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC supervisor_roster_unresolved streak=' "$state_dir/output.log")" -eq 2 ]
  [ "$(count_matches 'SELF_EXIT supervisor_roster_unresolved streak=3' "$state_dir/output.log")" -eq 1 ]
  [ ! -f "$state_dir/acks.log" ]
  unset FAKE_SUPERVISOR_RESOLVE_FAIL_AFTER
  printf 'PASS roster resolve streak: 1-2 survive + no-ack, 3rd self-exit code 6 (separate counter)\n'
}

# 실패 주기에는 Delivery 를 소비하지 않는다는 것을 직접 센다.
# 루프 1회 = supervisor resolve 1회이고, identity 가 좋은 주기에만 check 1회를 부른다.
# 따라서 check 횟수 == (supervisor resolve 총 횟수 - 기동 1회 - 진단 줄 수) 여야 한다.
assert_no_consume_on_failure_cycles() {
  local state_dir="$1" resolves checks diagnostics
  resolves=$(count_matches '^resolve project-supervisor' "$state_dir/roster.log")
  checks=$(count_matches 'orchestration check --run run_project --json' "$state_dir/calls.log")
  diagnostics=$(( $(count_matches 'CHECK_DIAGNOSTIC consumer_owner_mismatch streak=' "$state_dir/output.log") + $(count_matches 'CHECK_DIAGNOSTIC supervisor_roster_unresolved streak=' "$state_dir/output.log") ))
  [ "$checks" -eq $(( resolves - 1 - diagnostics )) ]
  [ ! -f "$state_dir/acks.log" ]
}

# owner mismatch 2회 -> roster 실패 1회 -> owner mismatch 2회.
# 서로 다른 실패 종류가 섞였으므로 owner 연속 3회가 아니다. 자기 종료가 없어야 한다.
run_cross_owner_roster_owner_case() {
  local state_dir
  state_dir=$(new_state)
  printf 'term_supervisor\nterm_drifted\nterm_drifted\nterm_ignored\nterm_drifted\nterm_drifted\nterm_supervisor\n' > "$state_dir/supervisor-handle-seq"
  printf '4\n' > "$state_dir/supervisor-resolve-fail-seq"
  run_state_companion "$state_dir"
  [ "$run_status" -eq 0 ]
  assert_absent 'SELF_EXIT' "$state_dir/output.log"
  [ "$(count_matches 'CHECK_DIAGNOSTIC consumer_owner_mismatch streak=1' "$state_dir/output.log")" -eq 2 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC consumer_owner_mismatch streak=2' "$state_dir/output.log")" -eq 2 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC consumer_owner_mismatch streak=3' "$state_dir/output.log")" -eq 0 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC supervisor_roster_unresolved streak=1' "$state_dir/output.log")" -eq 1 ]
  assert_no_consume_on_failure_cycles "$state_dir"
  printf 'PASS cross streak owner2 -> roster1 -> owner2: no false exit 5, no consume/ack on failures\n'
}

# roster 실패 2회 -> owner mismatch 1회 -> roster 실패 2회.
# 반대 방향 교차도 합산하지 않는다. exit 6 이 나오면 안 된다.
run_cross_roster_owner_roster_case() {
  local state_dir
  state_dir=$(new_state)
  printf 'term_supervisor\nterm_ignored\nterm_ignored\nterm_drifted\nterm_ignored\nterm_ignored\nterm_supervisor\n' > "$state_dir/supervisor-handle-seq"
  printf '2\n3\n5\n6\n' > "$state_dir/supervisor-resolve-fail-seq"
  run_state_companion "$state_dir"
  [ "$run_status" -eq 0 ]
  assert_absent 'SELF_EXIT' "$state_dir/output.log"
  [ "$(count_matches 'CHECK_DIAGNOSTIC supervisor_roster_unresolved streak=1' "$state_dir/output.log")" -eq 2 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC supervisor_roster_unresolved streak=2' "$state_dir/output.log")" -eq 2 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC supervisor_roster_unresolved streak=3' "$state_dir/output.log")" -eq 0 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC consumer_owner_mismatch streak=1' "$state_dir/output.log")" -eq 1 ]
  assert_no_consume_on_failure_cycles "$state_dir"
  printf 'PASS cross streak roster2 -> owner1 -> roster2: no false exit 6, no consume/ack on failures\n'
}

# 정상 identity 1회가 끼면 두 연속 횟수가 모두 0으로 돌아간다.
run_cross_normal_reset_case() {
  local state_dir
  state_dir=$(new_state)
  printf 'term_supervisor\nterm_drifted\nterm_ignored\nterm_supervisor\nterm_drifted\nterm_ignored\nterm_supervisor\nterm_supervisor\n' > "$state_dir/supervisor-handle-seq"
  printf '3\n6\n' > "$state_dir/supervisor-resolve-fail-seq"
  run_state_companion "$state_dir"
  [ "$run_status" -eq 0 ]
  assert_absent 'SELF_EXIT' "$state_dir/output.log"
  [ "$(count_matches 'streak=2' "$state_dir/output.log")" -eq 0 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC consumer_owner_mismatch streak=1' "$state_dir/output.log")" -eq 2 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC supervisor_roster_unresolved streak=1' "$state_dir/output.log")" -eq 2 ]
  printf 'PASS interleaved owner/roster failures with normal cycles -> both streaks reset to 0\n'
}

# Track G 551ae18: roster resolve 응답의 각 신분 필드 반례. currentHandle 만 맞아도
# 기동 시 fail-closed exit 4 이고 mailbox 소비가 0회여야 한다.
run_roster_identity_field_case() {
  local field="$1" state_dir status
  state_dir=$(new_state)
  set +e
  FAKE_ORCA_STATE_DIR="$state_dir" FAKE_RELAY_ALERT_MODE=clean FAKE_DELIVERY_MODE=none FAKE_ROSTER_BAD_FIELD="$field" ORCA_BIN="$FIXTURE" RELAY_LOG_FILE="$state_dir/relay.log" ROUTING_LEDGER_FILE="$state_dir/routing-ledger.jsonl" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$state_dir/output.log" 2>&1
  status=$?
  set -e
  [ "$status" -eq 4 ]
  rg -q -- 'ROSTER_FAIL_CLOSED role=project-supervisor reason=identity_mismatch' "$state_dir/output.log"
  assert_absent 'orchestration check' "$state_dir/calls.log"
  [ ! -f "$state_dir/acks.log" ]
  printf 'PASS wrong roster identity field=%s -> exit 4 fail-closed, zero mailbox consume\n' "$field"
}

# Track G 551ae18 상태 계약: NUDGE / MISSING_RELAY.
run_track_g_state_case() {
  local mode="$1" expected_wake="$2" pattern="${3:-}" state_dir status
  state_dir=$(new_state)
  FAKE_ORCA_STATE_DIR="$state_dir" FAKE_RELAY_ALERT_MODE="$mode" FAKE_DELIVERY_MODE=none FAKE_ROSTER_MULTIPLE_ROLE="${TRACK_G_MULTIPLE_ROLE:-}" ORCA_BIN="$FIXTURE" RELAY_LOG_FILE="$state_dir/relay.log" ROUTING_LEDGER_FILE="$state_dir/routing-ledger.jsonl" WATCH_DEADLINE_SEC="$TEST_WAIT_CEILING_SEC" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$state_dir/output.log" 2>&1 &
  local pid=$!
  wait_state_condition "$pid" "$state_dir" 'Track G state completed one patrol' '[ "$(count_matches "orchestration check --run run_project --json" "$state_dir/calls.log")" -ge 2 ]'
  [ "$run_status" -eq 0 ]
  [ "$(count_matches '--terminal term_supervisor --text' "$state_dir/sends.log")" -eq "$expected_wake" ]
  [ "$(count_matches '--terminal term_supervisor --enter' "$state_dir/sends.log")" -eq "$expected_wake" ]
  if [ -n "$pattern" ]; then
    rg -q -- "$pattern" "$state_dir/sends.log" 2>/dev/null || rg -q -- "$pattern" "$state_dir/output.log"
  fi
  printf 'PASS Track G state %s -> %s wake\n' "$mode" "$expected_wake"
}

# stateFingerprint 가 빠진 편지를 주는 wrapper fixture. 기존 fixture(orca)를 감싸서
# orchestration check 만 fingerprint 누락 편지로 덮어쓰고 나머지(roster/send/ack/run-show)는
# 기존 fixture에 위임한다. ack 줄 수로 여러 편지를 순서대로 준다.
make_missing_fp_fixture() {
  local state_dir="$1" script="$state_dir/missing-fp-fixture.sh"
  printf '#!/bin/bash\nset -u\n' > "$script"
  printf 'REAL_FIXTURE="%s"\n' "$FIXTURE" >> "$script"
  cat >> "$script" <<'WRAPPER_BODY'
STATE_DIR="${FAKE_ORCA_STATE_DIR:?}"
if [ "${1:-}" = "orchestration" ] && [ "${2:-}" = "check" ]; then
  previous=""
  ack_arg=""
  for argument in "$@"; do
    [ "$previous" = --ack ] && ack_arg="$argument"
    previous="$argument"
  done
  if [ -n "$ack_arg" ]; then
    printf '%s\n' "$ack_arg" >> "$STATE_DIR/acks.log"
    printf '%s\n' '{"result":{"acknowledged":true}}'
    exit 0
  fi
  ack_count=0
  [ -f "$STATE_DIR/acks.log" ] && ack_count=$(wc -l < "$STATE_DIR/acks.log" | tr -d ' ')
  kind="${MISSING_FP_KIND:-nudge}"
  case "${MISSING_FP_SEQUENCE:-single}:$ack_count" in
    single:0)
      if [ "$kind" = start ]; then
        printf '%s\n' '{"result":{"deliveryId":"delivery_missing_fp","messages":[{"message_id":"missing_fp_start","type":"status","sender_handle":"term_supervisor","subject":"missing fp start","payload":{"startDeclaration":true}}]}}'
      else
        printf '%s\n' '{"result":{"deliveryId":"delivery_missing_fp","messages":[{"message_id":"missing_fp_nudge","type":"status","sender_handle":"term_supervisor","subject":"missing fp nudge","payload":{"readyCardPresent":true,"activeDispatchAbsent":true,"coordinatorIdle":true}}]}}'
      fi
      ;;
    single:*)
      printf '%s\n' '{"result":{"deliveryId":null,"messages":[],"count":0}}'
      ;;
    alternate:0)
      printf '%s\n' '{"result":{"deliveryId":"delivery_alt","messages":[{"message_id":"alt_missing_0","type":"status","sender_handle":"term_supervisor","subject":"missing fp","payload":{"readyCardPresent":true,"activeDispatchAbsent":true,"coordinatorIdle":true}}]}}'
      ;;
    alternate:1)
      printf '%s\n' '{"result":{"deliveryId":"delivery_alt","messages":[{"message_id":"alt_valid_a","type":"status","sender_handle":"term_supervisor","subject":"valid a","payload":{"readyCardPresent":true,"activeDispatchAbsent":true,"coordinatorIdle":true,"stateFingerprint":"valid_a"}}]}}'
      ;;
    alternate:2)
      printf '%s\n' '{"result":{"deliveryId":"delivery_alt","messages":[{"message_id":"alt_missing_1","type":"status","sender_handle":"term_supervisor","subject":"missing fp again","payload":{"readyCardPresent":true,"activeDispatchAbsent":true,"coordinatorIdle":true}}]}}'
      ;;
    alternate:3)
      printf '%s\n' '{"result":{"deliveryId":"delivery_alt","messages":[{"message_id":"alt_valid_b","type":"status","sender_handle":"term_supervisor","subject":"valid b","payload":{"readyCardPresent":true,"activeDispatchAbsent":true,"coordinatorIdle":true,"stateFingerprint":"valid_b"}}]}}'
      ;;
    alternate:*)
      printf '%s\n' '{"result":{"deliveryId":null,"messages":[],"count":0}}'
      ;;
  esac
  exit 0
fi
exec "$REAL_FIXTURE" "$@"
WRAPPER_BODY
  chmod +x "$script"
  printf '%s\n' "$script"
}

# stateFingerprint 누락 시 wake 0 (text 0, enter 0, signal 0) + ordinary ack 1.
run_missing_fingerprint_case() {
  local kind="$1" relay_mode="$2" state_dir wrapper status signal_tag
  state_dir=$(new_state)
  wrapper=$(make_missing_fp_fixture "$state_dir")
  if [ "$kind" = start ]; then signal_tag='MISSING_RELAY fingerprint='; else signal_tag='NUDGE fingerprint='; fi
  FAKE_ORCA_STATE_DIR="$state_dir" FAKE_RELAY_ALERT_MODE="$relay_mode" FAKE_DELIVERY_MODE=none MISSING_FP_SEQUENCE=single MISSING_FP_KIND="$kind" ORCA_BIN="$wrapper" RELAY_LOG_FILE="$state_dir/relay.log" ROUTING_LEDGER_FILE="$state_dir/routing-ledger.jsonl" WATCH_DEADLINE_SEC="$TEST_WAIT_CEILING_SEC" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$state_dir/output.log" 2>&1 &
  local pid=$!
  wait_state_condition "$pid" "$state_dir" 'missing fingerprint delivery acknowledged' '[ "$(count_lines "$state_dir/acks.log")" -ge 1 ]'
  [ "$run_status" -eq 0 ]
  [ "$(count_matches '--terminal term_supervisor --text' "$state_dir/sends.log")" -eq 0 ]
  [ "$(count_matches '--terminal term_supervisor --enter' "$state_dir/sends.log")" -eq 0 ]
  assert_absent "$signal_tag" "$state_dir/sends.log"
  assert_absent "$signal_tag" "$state_dir/output.log"
  rg -q -- 'reason=state_fingerprint_required wake=0' "$state_dir/output.log"
  [ -f "$state_dir/acks.log" ]
  [ "$(count_lines "$state_dir/acks.log")" -eq 1 ]
  printf 'PASS missing fingerprint %s -> wake 0 (text/enter/signal 0), ack 1\n' "$kind"
}

# 서로 다른 누락 지문 뒤 유효한 서로 다른 stateFingerprint 가 오면 각각 wake 1.
# 가짜 합성 지문이 없어야 누락 지문이 SEEN 을 오염시키지 않는다.
run_missing_then_valid_case() {
  local state_dir wrapper status
  state_dir=$(new_state)
  wrapper=$(make_missing_fp_fixture "$state_dir")
  FAKE_ORCA_STATE_DIR="$state_dir" FAKE_RELAY_ALERT_MODE=clean FAKE_DELIVERY_MODE=none MISSING_FP_SEQUENCE=alternate MISSING_FP_KIND=nudge ORCA_BIN="$wrapper" RELAY_LOG_FILE="$state_dir/relay.log" ROUTING_LEDGER_FILE="$state_dir/routing-ledger.jsonl" WATCH_DEADLINE_SEC="$TEST_WAIT_CEILING_SEC" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$state_dir/output.log" 2>&1 &
  local pid=$!
  wait_state_condition "$pid" "$state_dir" 'four alternating fingerprint deliveries acknowledged' '[ "$(count_lines "$state_dir/acks.log")" -ge 4 ]'
  [ "$run_status" -eq 0 ]
  [ "$(count_matches '--terminal term_supervisor --text' "$state_dir/sends.log")" -eq 2 ]
  [ "$(count_matches '--terminal term_supervisor --enter' "$state_dir/sends.log")" -eq 2 ]
  rg -q -- 'NUDGE fingerprint=valid_a' "$state_dir/sends.log" 2>/dev/null || rg -q -- 'NUDGE fingerprint=valid_a' "$state_dir/output.log"
  rg -q -- 'NUDGE fingerprint=valid_b' "$state_dir/sends.log" 2>/dev/null || rg -q -- 'NUDGE fingerprint=valid_b' "$state_dir/output.log"
  assert_absent 'NUDGE fingerprint=ready:present' "$state_dir/sends.log"
  assert_absent 'NUDGE fingerprint=ready:present' "$state_dir/output.log"
  assert_absent 'NUDGE fingerprint=start:' "$state_dir/sends.log"
  assert_absent 'NUDGE fingerprint=start:' "$state_dir/output.log"
  [ "$(count_lines "$state_dir/acks.log")" -eq 4 ]
  printf 'PASS missing-then-valid: 2 missing fp wake 0 + 2 distinct valid fp wake 1, no synthetic fingerprint pollution\n'
}

run_startup_mismatch_case
run_owner_mismatch_streak_case
run_owner_mismatch_reset_case
run_roster_fail_streak_case
run_cross_owner_roster_owner_case
run_cross_roster_owner_roster_case
run_cross_normal_reset_case
for identity_field in project board role run status lifecycle live result_live pane handle; do
  run_roster_identity_field_case "$identity_field"
done
run_track_g_state_case state_nudge 1 'NUDGE fingerprint=nudge_fp'
run_track_g_state_case state_nudge_duplicate 1 'NUDGE_DUPLICATE fingerprint=nudge_fp wake=0'
run_track_g_state_case state_nudge_fingerprint_change 2 'NUDGE fingerprint=nudge_b'
run_track_g_state_case state_nudge_false 0 'NUDGE_SUPPRESSED fingerprint=nudge_false'
run_track_g_state_case state_nudge_closed 0 'NUDGE_SUPPRESSED fingerprint=nudge_closed'
run_track_g_state_case state_gate_waiting 0 'NUDGE_SUPPRESSED fingerprint=nudge_gate'
run_track_g_state_case start_missing_relay 1 'MISSING_RELAY fingerprint=start_fp'
run_track_g_state_case start_duplicate_missing_relay 1 'MISSING_RELAY_DUPLICATE fingerprint=start_fp wake=0'
run_track_g_state_case start_relay_present 0 'MISSING_RELAY_SUPPRESSED fingerprint=start_fp relay=present wake=0'
run_track_g_state_case start_duplicate_present 0 'MISSING_RELAY_SUPPRESSED fingerprint=start_fp relay=present wake=0'
run_track_g_state_case start_wrong_relay 0 'MISSING_RELAY_CHECK_UNKNOWN fingerprint=start_fp roster=unknown wake=0'
TRACK_G_MULTIPLE_ROLE=relay run_track_g_state_case start_relay_present 0 'MISSING_RELAY_CHECK_UNKNOWN fingerprint=start_fp roster=ambiguous wake=0'
run_missing_fingerprint_case nudge clean
run_missing_fingerprint_case start start_missing_relay
run_missing_then_valid_case
printf 'PASS companion state lifecycle focused suite; streak self-exit + cross reset + startup gate + Track G roster identity and NUDGE/MISSING_RELAY\n'
