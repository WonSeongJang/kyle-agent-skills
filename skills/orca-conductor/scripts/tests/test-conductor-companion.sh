#!/bin/bash
set -euo pipefail
# -E(errtrace): ERR 트랩은 함수 안에서 상속되지 않는다. 켜지 않으면
# 실패한 줄과 명령이 "불명"으로 나와 판정 문구가 반쪽이 된다.
set -E

# F-B7(2026-08-09): 이 시험이 조용히 죽지 못하게 만든다.
#
# Why: 이 파일의 단언은 전부 맨 `[ ... ]` 라서, 하나가 틀리면 `set -e` 가 스크립트를
# 그 자리에서 죽인다 — FAIL 한 줄도 없이. 그러면 화면에 남는 마지막 줄은 직전 시험이
# 찍은 초록 문구이고, 진짜 신호(종료 코드 1)는 아무도 못 본다. 2026-08-09에 실제로
# 그렇게 됐다. 이제 죽을 때 어느 줄에서 어떤 명령이 틀렸는지 반드시 찍는다.
COMPANION_FAIL_LINE=""
COMPANION_FAIL_CMD=""
trap 'COMPANION_FAIL_LINE=$LINENO; COMPANION_FAIL_CMD=$BASH_COMMAND' ERR

# F-B9-2(2026-08-09): "시험이 틀렸다"와 "시험을 돌리지 못했다"를 성적에서 분리한다.
#
# Why: 종료 126(실행 권한 없음)·127(부를 파일 못 찾음)은 대상 구현이 틀렸다는 뜻이
# 아니다. 아무것도 측정하지 못했다는 뜻이다. 그런데 직전 판에서는 그 값을 만들어
# 찍기만 하고 성적을 매기는 쪽(EXIT 판정 트랩)이 그 값을 안 썼다 — 화면에는
# TEST_EXECUTION_UNAVAILABLE 이 뜨는데 판정은 그대로 FAIL 이었다. 값을 만드는 것과
# 그 값이 실제로 쓰이는 것은 다르다.
#
# 그래서 실행 불가는 종료 코드 9 라는 자기 칸을 갖는다. 합격(0)에도 불합격(1)에도
# 넣지 않고 판정 문구도 UNAVAILABLE 로 따로 찍는다.
#
# 관문은 통과시키지 않는다(exit 9 는 0 이 아니다). 근거: 성적(몇 개 통과)과 관문
# 통과 여부는 다른 값이다. 실행 불가는 "합격도 불합격도 모른다"는 상태이고, 모르는
# 상태로 관문을 열면 초록불 위장이 된다. 재실행 요구는 관문을 연 뒤 사람이 기억해야
# 하는 규율이라 놓치면 그대로 새어 나간다. 그래서 그 자체로 관문 실패로 둔다.
TEST_UNAVAILABLE_EXIT=9
# 126 과 127 은 처방이 다르다(권한 주기 / 파일 놓기). 그래서 구분해 남긴다.
unavailable_kind() {
  case "$1" in
    126) printf 'permission_denied(실행 권한 없음)' ;;
    127) printf 'not_found(부를 파일 못 찾음)' ;;
    *) printf 'unknown' ;;
  esac
}
COMPANION_UNAVAIL_STATUS=""
companion_unavailable_stop() {
  local status="$1" expected="$2"
  COMPANION_UNAVAIL_STATUS="$status"
  printf 'TEST_EXECUTION_UNAVAILABLE status=%s kind=%s expected=%s\n' \
    "$status" "$(unavailable_kind "$status")" "$expected" >&2
  exit "$TEST_UNAVAILABLE_EXIT"
}
# F-B9-2: 배경 실행(`&`) 뒤의 `wait $pid` 로는 126/127 을 못 잡는다 — 실측했다.
#
#   foreground  없는 파일 -> 127,  실행권한 없음 -> 126   (맞게 나온다)
#   background  없는 파일 ->   1,  실행권한 없음 ->   1   (진짜 불합격과 구분 불가)
#
# 자식이 루프보다 먼저 죽으면 bash 가 그 상태를 이미 거두어서 `wait` 이 1 을 준다.
# 그래서 `wait` 결과만 보는 분류는 이 파일들에서 한 번도 켜지지 않는 죽은 코드였다.
# 판정을 실행 전으로 옮긴다: 부를 파일이 있는지·실행 권한이 있는지 먼저 본다.
# 이건 사후 추측이 아니라 확정이고, 126 과 127 의 처방(권한 주기 / 파일 놓기)도 그대로 나온다.
require_runnable() {
  local target="$1" expected="$2"
  [ -e "$target" ] || companion_unavailable_stop 127 "$expected (target=$target)"
  [ -x "$target" ] || companion_unavailable_stop 126 "$expected (target=$target)"
}
companion_suite_verdict() {
  local rc=$?
  if [ "$rc" -eq "$TEST_UNAVAILABLE_EXIT" ]; then
    local s126=0 s127=0
    [ "$COMPANION_UNAVAIL_STATUS" = 126 ] && s126=1
    [ "$COMPANION_UNAVAIL_STATUS" = 127 ] && s127=1
    printf 'UNAVAILABLE test-conductor-companion.sh exit=%s unavailable=1 status126=%s status127=%s (성적 아님: 합격에도 불합격에도 안 넣음, 관문은 통과 못 함)\n' \
      "$rc" "$s126" "$s127" >&2
    printf 'UNAVAILABLE test-conductor-companion.sh exit=%s unavailable=1 status126=%s status127=%s (성적 아님: 합격에도 불합격에도 안 넣음, 관문은 통과 못 함)\n' \
      "$rc" "$s126" "$s127"
  elif [ "$rc" -ne 0 ]; then
    printf 'FAIL test-conductor-companion.sh exit=%s line=%s cmd=%s\n' \
      "$rc" "${COMPANION_FAIL_LINE:-불명}" "${COMPANION_FAIL_CMD:-불명}" >&2
    printf 'FAIL test-conductor-companion.sh exit=%s line=%s cmd=%s\n' \
      "$rc" "${COMPANION_FAIL_LINE:-불명}" "${COMPANION_FAIL_CMD:-불명}"
  fi
  exit "$rc"
}
trap companion_suite_verdict EXIT

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
# 시험 대상 구현을 밖에서 갈아끼울 수 있게 둔다. 이것이 "틀린 구현을 실제로 넣고 돌려서
# 빨간불이 켜지는지 본다"를 한 줄로 만드는 장치다:
#   COMPANION_UNDER_TEST=<B6 이전 원본> bash test-conductor-companion.sh   -> 반드시 실패
COMPANION="${COMPANION_UNDER_TEST:-$SKILL_DIR/scripts/conductor-companion.sh}"
# F-B9-2: 시험 대상과 모의 orca 를 돌리기 전에 먼저 확인한다. 여기서 걸리면 성적이
# 아니라 "시험 실행 불가"이고, 종료 9 로 끝난다.
require_runnable "$COMPANION" 'suite subject: conductor-companion.sh'
FIXTURE="$SCRIPT_DIR/fixtures/orca"
require_runnable "$FIXTURE" 'suite fixture: fake orca CLI'
export COMPANION_POLL_INTERVAL_SEC=0.05
TEST_WAIT_CEILING_SEC="${TEST_WAIT_CEILING_SEC:-60}"
export PROJECT_LEDGER_SCAN_LIMIT=100
export FAKE_CHECK_FAILURE=""
export FAKE_ENTER_MODE=ok
export ORCA_TERMINAL_HANDLE=term_supervisor
# 깨우기 실패 재시도 한도를 기본적으로 크게 고정한다. 이 한도는 B6 이 새로 도입한
# 것이라, 고정하지 않으면 "깨우기 실패 -> Delivery 재시도" 계열 시험의 결과가 1초 창에
# 루프가 몇 번 도는지(=머신 부하)에 따라 흔들린다. 한도 자체의 계약은
# run_wake_failure_bounded_case 한 곳에서만 낮춰서 검사한다.
export COMPANION_MAX_WAKE_ATTEMPTS=999

count_matches() {
  local pattern="$1" file="$2"
  [ -f "$file" ] || { printf '0\n'; return 0; }
  rg -c -- "$pattern" "$file" 2>/dev/null || printf '0\n'
}
# F-B7(2026-08-09): 파일 "부재"와 "있고 비어 있음"을 구분해서 읽는다.
#
# Why: 예전에는 `$(read_log "$state_dir/acks.log")` 처럼 조건 없이 읽었다. 파일이 없으면
# `cat` 이 stderr 에 "No such file or directory" 를 뱉고 값은 빈 문자열이 되는데,
# 빈 문자열은 "ack 0건"과 생김새가 같다. 그래서 화면에는 원인을 알 수 없는 cat 오류만
# 남고, 무엇이 왜 틀렸는지는 사라졌다. 이제 부재는 <파일없음> 이라는 눈에 보이는 값으로
# 나오므로, 단언이 틀릴 때 "0건이라 틀렸다"와 "아예 안 생겨서 틀렸다"가 구분된다.
read_log() {
  local file="$1"
  if [ ! -f "$file" ]; then printf '<파일없음:%s>' "$file"; return 0; fi
  cat "$file"
}
# 줄바꿈을 공백으로 바꿔 한 줄로 읽는다(여러 ack 을 순서까지 비교하는 자리용).
read_log_flat() {
  local file="$1"
  if [ ! -f "$file" ]; then printf '<파일없음:%s>' "$file"; return 0; fi
  tr '\n' ' ' < "$file"
}
assert_absent() {
  local pattern="$1" file="$2"
  if [ -f "$file" ] && rg -q -- "$pattern" "$file"; then
    printf 'ASSERT_ABSENT_FAIL pattern=%s file=%s\n' "$pattern" "$file" >&2
    return 1
  fi
}
assert_no_screen_reads() {
  local state_dir="$1"
  assert_absent 'terminal read' "$state_dir/calls.log"
  assert_absent 'terminal read' "$COMPANION"
}
# F-B7(2026-08-09): "관측이 없었다"와 "관측했는데 틀렸다"를 구분한다.
#
# 실측한 사고: `WATCH_DEADLINE_SEC=1` 인 창 안에서 companion 이 기동(roster 조회 등)만
# 하다가 창이 끝나는 일이 있다. 그러면 우편함 조회를 한 번도 못 하고, ack 도 못 하고,
# `acks.log` 가 아예 안 생긴다. 예전 단언은 그 파일을 조건 없이 읽어서 `cat: ... No such
# file or directory` 만 남기고 죽었다 — 무엇이 왜 틀렸는지는 사라진 채로.
# 부하 11 인 맥에서 같은 케이스를 20회 돌려 1회 재현했다(5%). 판 전체는 케이스가 ~140개라
# 사실상 매번 어딘가에서 터진다.
#
# 이것은 companion 의 결함이 아니라 시험 창이 짧아서 생긴 "잰 적이 없음"이다. 그래서
# 실패로 세지 않고 다시 잰다. 다만 조용히 넘어가지 않는다 — 다시 잴 때마다 화면에 남긴다.
#
# 다시 재도 되는 근거: 우편함 조회를 한 번도 안 했다면 fixture 의 `log_call` 이 한 번도
# 안 돌았다는 뜻이고(= `calls.log` 가 비었거나 없다), `sends.log`·`project-sends.log`·
# `acks.log`·`phase` 는 전부 그 뒤에서만 쓰이므로 남은 기록이 없다. 즉 같은 판에서 다시
# 재도 앞 시도의 흔적이 숫자를 오염시키지 않는다. 반대로 조회가 한 번이라도 돌았는데
# 결과가 틀렸다면 그것은 진짜 실패이므로 절대 다시 재지 않는다.
now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000'; }
observed_state() {
  local state_dir="$1"
  printf 'calls=%s acks=%s sends=%s roster=%s output_tail=%s' \
    "$(count_matches '.' "$state_dir/calls.log")" \
    "$(count_matches '.' "$state_dir/acks.log")" \
    "$(count_matches '.' "$state_dir/sends.log")" \
    "$(count_matches '.' "$state_dir/roster.log")" \
    "$(tail -1 "$state_dir/output.log" 2>/dev/null || printf '<없음>')"
}
wait_for_test_condition() {
  local pid="$1" state_dir="$2" expected="$3" condition="$4"
  local started now elapsed status
  started=$(now_ms)
  while kill -0 "$pid" 2>/dev/null; do
    if eval "$condition"; then
      elapsed=$(( $(now_ms) - started ))
      kill -TERM "$pid" 2>/dev/null || true
      set +e; wait "$pid"; status=$?; set -e
      [ "$status" -eq 0 ] || { printf 'CONDITION_STOP_FAILED status=%s pid=%s\n' "$status" "$pid" >&2; return 1; }
      printf 'CONDITION_MET expected=%s elapsed_ms=%s\n' "$expected" "$elapsed" >> "$state_dir/output.log"
      return 0
    fi
    now=$(now_ms); elapsed=$((now - started))
    [ "$elapsed" -lt $((TEST_WAIT_CEILING_SEC * 1000)) ] || break
    sleep 0.05
  done
  set +e; wait "$pid"; status=$?; set -e
  if [ "$status" -eq 126 ] || [ "$status" -eq 127 ]; then
    companion_unavailable_stop "$status" "$expected"
  fi
  printf 'CONDITION_WAIT_STALLED expected=%s\n' "$expected" >&2
  printf 'CONDITION_WAIT_ELAPSED elapsed_ms=%s ceiling_sec=%s\n' "$(( $(now_ms) - started ))" "$TEST_WAIT_CEILING_SEC" >&2
  printf 'CONDITION_WAIT_OBSERVED %s\n' "$(observed_state "$state_dir")" >&2
  return 1
}
run_companion() {
  local mode="$1" state_dir="$2" delivery_mode="${3:-none}" script="${4:-$COMPANION}" ledger="${5:-$state_dir/routing-ledger.jsonl}" expected="${6:-one complete patrol}" condition="${7:-[ \"\$(count_matches 'orchestration check --run run_project --json' \"$state_dir/calls.log\")\" -ge 2 ]}"
  export FAKE_ORCA_STATE_DIR="$state_dir"
  export FAKE_RELAY_ALERT_MODE="$mode"
  export FAKE_DELIVERY_MODE="$delivery_mode"
  export ORCA_BIN="$FIXTURE"
  export RELAY_LOG_FILE="$state_dir/relay.log"
  export ROUTING_LEDGER_FILE="$ledger"
  require_runnable "$script" "$expected"
  WATCH_DEADLINE_SEC="$TEST_WAIT_CEILING_SEC" "$script" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$state_dir/output.log" 2>&1 &
  local pid=$!
  wait_for_test_condition "$pid" "$state_dir" "$expected" "$condition"
}
new_state() {
  mktemp -d /tmp/orca-relay-focused.XXXXXX
}
assert_single_wake() {
  local state_dir="$1"
  [ "$(count_matches '--terminal term_supervisor --text' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches '--terminal term_supervisor --enter' "$state_dir/sends.log")" -eq 1 ]
}
run_candidate_absent_case() {
  local mode="${1:-candidate_absent}" state_dir
  state_dir=$(new_state)
  run_companion "$mode" "$state_dir"
  [ "$(count_matches 'misrouted_human_decision:task_candidate' "$state_dir/project-sends.log")" -eq 1 ]
  assert_single_wake "$state_dir"
  [ "$(count_matches 'wake=1' "$state_dir/relay.log")" -eq 1 ]
  [ "$(read_log "$state_dir/acks.log")" = delivery_candidate ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS %s missing official project letter -> one escalation + one supervisor wake\n' "$mode"
}
run_candidate_present_case() {
  local mode="$1" state_dir
  state_dir=$(new_state)
  run_companion "$mode" "$state_dir"
  [ "$(count_matches 'misrouted_human_decision:' "$state_dir/project-sends.log")" -eq 0 ]
  [ "$(count_matches '--terminal term_supervisor' "$state_dir/sends.log")" -eq 0 ]
  [ "$(count_matches 'late_recovered task=task_candidate dispatch=ctx_candidate cursor=77 wake=0' "$state_dir/relay.log")" -eq 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS official %s letter -> late_recovered + zero wake\n' "$mode"
}
run_candidate_context_case() {
  local mode="$1" state_dir
  state_dir=$(new_state)
  run_companion "$mode" "$state_dir"
  [ "$(count_matches 'misrouted_human_decision:' "$state_dir/project-sends.log")" -eq 0 ]
  [ "$(count_matches '--terminal term_supervisor' "$state_dir/sends.log")" -eq 0 ]
  [ "$(count_matches 'RELAY_CONTEXT_REQUIRED' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches '--terminal term_relay --enter' "$state_dir/sends.log")" -eq 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS %s -> bounded relay context request only\n' "$mode"
}
run_duplicate_cursor_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion candidate_duplicate "$state_dir" none "$COMPANION" "$state_dir/routing-ledger.jsonl" 'duplicate candidate suppressed' '[ "$(count_matches "RELAY_CANDIDATE_DUPLICATE" "$state_dir/output.log")" -ge 1 ]'
  [ "$(count_matches 'misrouted_human_decision:' "$state_dir/project-sends.log")" -eq 1 ]
  [ "$(count_matches '--terminal term_supervisor --text' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'RELAY_CANDIDATE_DUPLICATE task=task_candidate dispatch=ctx_candidate cursor=77 wake=0' "$state_dir/output.log")" -eq 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS duplicate task+dispatch+cursor -> zero duplicate wake\n'
}
# Delivery 2개를 순서대로 소비하려면 루프가 최소 2주기 돌아야 한다. 1초 창에서는 머신
# 부하에 따라 1주기만 도는 경우가 있어 결과가 흔들렸다(B6 이전에도 동일하게 흔들렸음을
# 교대 실행 15쌍으로 실측: 현재 13/15, 이전 13/15). 주기 수에 의존하는 시험만 창을 넓혀
# 증거가 부하에 흔들리지 않게 한다.
run_fifo_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" fifo "$COMPANION" "$state_dir/routing-ledger.jsonl" 'two FIFO deliveries acknowledged' '[ "$(count_matches . "$state_dir/acks.log")" -ge 2 ]'
  [ "$(read_log_flat "$state_dir/acks.log")" = 'delivery_1 delivery_2 ' ]
  [ "$(count_matches '--run run_project --ack delivery_1' "$state_dir/calls.log")" -eq 1 ]
  [ "$(count_matches '--run run_project --ack delivery_2' "$state_dir/calls.log")" -eq 1 ]
  [ "$(count_matches --enter "$state_dir/sends.log")" -eq 2 ]
  [ "$(count_matches 'SIGNAL escalation term_worker task=task_1 dispatch=ctx_1' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'SIGNAL decision_gate term_worker task=task_2 dispatch=ctx_2' "$state_dir/sends.log")" -eq 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS FIFO lifecycle delivery and exact text+Enter ack path\n'
}

# B11: 중복 억제 단위는 task+dispatch가 아니라 편지 ID다. 같은 발령의 서로 다른 새
# 질문은 내용도 다르게 두어 각각 깨우고, 같은 편지 ID 재처리만 한 번으로 억제한다.
run_lifecycle_message_identity_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" lifecycle_question_two
  [ "$(count_matches 'SIGNAL question term_worker task=task_same dispatch=ctx_same' "$state_dir/sends.log")" -eq 2 ]
  [ "$(count_matches '--terminal term_supervisor --enter' "$state_dir/sends.log")" -eq 2 ]
  printf 'PASS B11 same dispatch, two different questions -> two wakes\n'

  state_dir=$(new_state)
  run_companion clean "$state_dir" lifecycle_question_replay
  [ "$(count_matches 'SIGNAL question term_worker task=task_same dispatch=ctx_same' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches '--terminal term_supervisor --enter' "$state_dir/sends.log")" -eq 1 ]
  printf 'PASS B11 same message replay -> one wake\n'

  state_dir=$(new_state)
  run_companion clean "$state_dir" lifecycle_escalation_two
  [ "$(count_matches 'SIGNAL escalation term_worker task=task_same dispatch=ctx_same' "$state_dir/sends.log")" -eq 2 ]
  printf 'PASS B11 same dispatch, two escalations -> two wakes\n'

  state_dir=$(new_state)
  export FAKE_WORKER_ROLE=developer FAKE_WORKER_HANDLE=term_worker
  run_companion clean "$state_dir" lifecycle_worker_done_two
  unset FAKE_WORKER_ROLE FAKE_WORKER_HANDLE
  [ "$(count_matches 'SIGNAL worker_done term_worker task=task_bf886c87af30 dispatch=ctx_de177164da67' "$state_dir/sends.log")" -eq 2 ]
  printf 'PASS B11 same dispatch, two worker_done reports -> two wakes\n'

  state_dir=$(new_state)
  run_companion clean "$state_dir" lifecycle_ask_two
  [ "$(count_matches 'SIGNAL ask term_worker task=task_same dispatch=ctx_same' "$state_dir/sends.log")" -eq 2 ]
  printf 'PASS B11 same dispatch, two ask letters -> two wakes\n'

  state_dir=$(new_state)
  run_companion clean "$state_dir" lifecycle_decision_gate_two
  [ "$(count_matches 'SIGNAL decision_gate term_worker task=task_same dispatch=ctx_same' "$state_dir/sends.log")" -eq 2 ]
  printf 'PASS B11 same dispatch, two decision_gate letters -> two wakes\n'
}
# F-B11 중요1: 같은 messageId 라도 생명주기 type 이 다르면 서로 다른 편지다.
# 앞단 중복 필터가 messageId 만 보면 두 번째 편지(escalation)가 여기서 막혀 감독이
# 영영 못 깨어난다. 앞단 seen 키와 event 키가 같은 단위(type+messageId)를 써야 한다.
assert_cross_type_contract() {
  local state_dir="$1"
  [ "$(count_matches 'SIGNAL question term_worker task=task_same dispatch=ctx_same' "$state_dir/sends.log")" -eq 1 ] || return 1
  [ "$(count_matches 'SIGNAL escalation term_worker task=task_same dispatch=ctx_same' "$state_dir/sends.log")" -eq 1 ] || return 1
  [ "$(count_matches '--terminal term_supervisor --enter' "$state_dir/sends.log")" -eq 2 ] || return 1
  [ "$(read_log "$state_dir/acks.log")" = delivery_cross_type ] || return 1
}
run_lifecycle_cross_type_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" lifecycle_cross_type
  assert_cross_type_contract "$state_dir"
  assert_no_screen_reads "$state_dir"
  printf 'PASS F-B11 same messageId with different type -> two wakes (question 1 + escalation 1)\n'
}
# F-B11 중요2: 불량 messageId 한 통이 Delivery 전체를 막으면 안 된다. 불량 편지는
# 깨우지 않고(wake 0) 보이게 격리하며, 같은 Delivery 의 뒤 정상 편지는 계속 깨우고
# Delivery ack 도 성립해야 한다.
assert_malformed_id_contract() {
  local state_dir="$1" reason="$2"
  # 불량 편지로 감독을 깨우지 않는다.
  [ "$(count_matches 'task=task_bad dispatch=ctx_bad' "$state_dir/sends.log")" -eq 0 ] || return 1
  # 조용한 폐기가 아니다: relay 로그와 companion 출력 둘 다에 이유·위치·type 이 남는다.
  [ "$(count_matches "message_shape_quarantined delivery=delivery_bad_id index=0 type=escalation reason=$reason wake=0 blocked_queue=0" "$state_dir/relay.log")" -eq 1 ] || return 1
  [ "$(count_matches "message_shape_quarantined delivery=delivery_bad_id index=0 type=escalation reason=$reason" "$state_dir/output.log")" -ge 1 ] || return 1
  # 뒤의 정상 편지는 그대로 깨운다.
  [ "$(count_matches 'SIGNAL question term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ] || return 1
  # Delivery ack 이 성립한다(큐가 멈추지 않는다).
  [ "$(count_matches '--run run_project --ack delivery_bad_id' "$state_dir/calls.log")" -ge 1 ] || return 1
  # 원문 비밀을 진단에 싣지 않는다: 격리 줄은 type·위치·이유만 남기고 불량 편지의
  # payload 식별자나 제목은 어디에도 새지 않는다.
  [ "$(count_matches 'task_bad' "$state_dir/relay.log")" -eq 0 ] || return 1
  [ "$(count_matches 'task_bad' "$state_dir/output.log")" -eq 0 ] || return 1
  # F-B11-2: 진단이 파일에만 남고 끝나지 않는다. 같은 처리 경로가 project Run 으로
  # 구조화 편지를 정확히 1통 올린다(상신 주체는 companion 한 곳뿐이다).
  [ "$(count_matches 'orchestration send --run run_project --subject message_shape_quarantined:board_test' "$state_dir/project-sends.log")" -eq 1 ] || return 1
  [ "$(count_matches 'MESSAGE_SHAPE_REPORT_SENT board=board_test' "$state_dir/output.log")" -eq 1 ] || return 1
  [ "$(count_matches 'reason='"$reason" "$state_dir/project-sends.log")" -eq 1 ] || return 1
  # 상신에도 원문은 없다. deliveryId 원문조차 싣지 않고 해시(deliveryRef)만 싣는다.
  [ "$(count_matches 'task_bad' "$state_dir/project-sends.log")" -eq 0 ] || return 1
  [ "$(count_matches 'delivery_bad_id' "$state_dir/project-sends.log")" -eq 0 ] || return 1
  [ "$(count_matches 'deliveryRef' "$state_dir/project-sends.log")" -eq 1 ] || return 1
}
# F-B11-2: 불량 1통 뒤 서로 다른 정상 lifecycle 4종이 각각 깨어나는지 본다.
run_malformed_id_four_good_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" malformed_id_four_good
  [ "$(count_matches 'SIGNAL question term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'SIGNAL ask term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'SIGNAL escalation term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'SIGNAL decision_gate term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'task=task_bad dispatch=ctx_bad' "$state_dir/sends.log")" -eq 0 ]
  [ "$(count_matches 'message_shape_quarantined delivery=delivery_bad_id_four_good index=0' "$state_dir/relay.log")" -eq 1 ]
  [ "$(count_matches 'message_shape_quarantined:board_test' "$state_dir/project-sends.log")" -eq 1 ]
  [ "$(count_matches '--run run_project --ack delivery_bad_id_four_good' "$state_dir/calls.log")" -ge 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS F-B11-2 malformed head + 4 lifecycle types -> 4 wakes, 1 structured report\n'
}
# F-B11-2: 원문 누출 0건을 4개 출력 경로에서 한꺼번에 본다.
# (companion stdout · relay 로그 · 감독 terminal send · project Run 상신)
run_malformed_id_secret_case() {
  local state_dir marker
  state_dir=$(new_state)
  run_companion clean "$state_dir" malformed_id_secret
  [ "$(count_matches 'SIGNAL question term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'message_shape_quarantined:board_test' "$state_dir/project-sends.log")" -eq 1 ]
  for marker in SECRET_SUBJECT_ZYX SECRET_BODY_ZYX SECRET_PAYLOAD_ZYX SECRET_TASK_ZYX SECRET_DISPATCH_ZYX; do
    [ "$(count_matches "$marker" "$state_dir/output.log")" -eq 0 ]
    [ "$(count_matches "$marker" "$state_dir/relay.log")" -eq 0 ]
    [ "$(count_matches "$marker" "$state_dir/sends.log")" -eq 0 ]
    [ "$(count_matches "$marker" "$state_dir/project-sends.log")" -eq 0 ]
    [ "$(count_matches "$marker" "$state_dir/calls.log")" -eq 0 ]
  done
  assert_no_screen_reads "$state_dir"
  printf 'PASS F-B11-2 malformed 원문 표식 5종 x 출력 경로 5곳 누출 0건\n'
}
# F-B11-2 소비 끝단: 올린 알림이 우편함으로 돌아오면 감독을 정확히 1회 깨우고 끝난다.
# 알림이 또 다른 알림을 만들면(재귀) project 상신이 늘어나므로 그 자리에서 잡힌다.
run_shape_report_echo_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" shape_report_echo
  [ "$(count_matches 'SIGNAL message_shape_quarantined sender=term_supervisor message=shape_alert_1' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches '--terminal term_supervisor --enter' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'MALFORMED_LIFECYCLE_REPORT' "$state_dir/sends.log")" -eq 0 ]
  [ "$(count_matches 'orchestration send' "$state_dir/calls.log")" -eq 0 ]
  [ "$(count_matches '--run run_project --ack delivery_shape_echo' "$state_dir/calls.log")" -ge 1 ]
  # F-B11-3: 진짜 알림은 출처 검증을 통과하므로 거부 진단이 한 줄도 없어야 한다.
  [ "$(count_matches 'forged_or_untrusted_shape_alert' "$state_dir/relay.log")" -eq 0 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS F-B11-2 shape alert echo -> supervisor wake 1, no recursive report\n'
}
run_shape_report_echo_replay_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" shape_report_echo_replay
  [ "$(count_matches 'SIGNAL message_shape_quarantined sender=term_supervisor message=shape_alert_same' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'orchestration send' "$state_dir/calls.log")" -eq 0 ]
  [ "$(count_matches '--run run_project --ack delivery_shape_echo_replay' "$state_dir/calls.log")" -ge 1 ]
  [ "$(count_matches 'forged_or_untrusted_shape_alert' "$state_dir/relay.log")" -eq 0 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS F-B11-2 same shape alert replayed -> still one wake\n'
}
# F-B11-3 중요1: payload 표식만 흉내 낸 편지는 구조 알림으로 인정하지 않는다.
#
# Why: 표식 하나만 보고 인정하면 판 밖 발신자가 감독을 마음대로 깨울 수 있다(R-F-B11-2
# 중요1, 위조 focused 148/148 통과). 그래서 (1) 지금 이 순간의 project-supervisor 를 roster
# 로 다시 조회해 handle+pane 한 쌍과 정확히 대조하고, (2) type·subject·board·deliveryRef·
# index·messageType·reason·payload 키 집합·본문 결속까지 전부 맞을 때만 인정한다.
#
# 거부는 조용한 폐기가 아니다: 고정 어휘 거부 사유를 남기고, 큐를 막지 않도록 ack 하며,
# 같은 Delivery 의 정상 형제는 그대로 깨운다. 거부한 편지가 아래 lifecycle 분기로 새어
# 나가 escalation 으로 깨우지도 않는다(그것이 위조의 진짜 이득이므로 여기서 함께 막는다).
run_shape_alert_forged_case() {
  local label="$1" delivery_mode="$2" expect_reason="$3" state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" "$delivery_mode" "$COMPANION" "$state_dir/routing-ledger.jsonl" \
    "forged shape alert rejected: $label" \
    '[ "$(count_matches . "$state_dir/acks.log")" -ge 1 ]'
  # 위조 알림으로는 감독을 깨우지 않는다(구조 알림 경로로도, lifecycle 경로로도).
  [ "$(count_matches 'SIGNAL message_shape_quarantined' "$state_dir/sends.log")" -eq 0 ] || return 1
  [ "$(count_matches 'shape_alert_forged' "$state_dir/sends.log")" -eq 0 ] || return 1
  # 조용히 버리지 않는다: 고정 어휘 거부 사유만 남는다.
  [ "$(count_matches "forged_or_untrusted_shape_alert board=board_test reason=$expect_reason wake=0 blocked_queue=0" "$state_dir/relay.log")" -eq 1 ] || return 1
  # 거부가 새 편지를 만들지 않는다(재귀 금지).
  [ "$(count_matches 'orchestration send' "$state_dir/calls.log")" -eq 0 ] || return 1
  # 큐는 막지 않는다: 같은 Delivery 의 정상 형제는 깨어나고 ack 도 성립한다.
  [ "$(count_matches 'SIGNAL question term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ] || return 1
  [ "$(count_matches '--run run_project --ack delivery_shape_forged' "$state_dir/calls.log")" -ge 1 ] || return 1
  # 위조가 심은 원문은 어느 출력 경로에도 새지 않는다.
  [ "$(count_matches 'task_smuggled' "$state_dir/relay.log")" -eq 0 ] || return 1
  [ "$(count_matches 'task_smuggled' "$state_dir/sends.log")" -eq 0 ] || return 1
  assert_no_screen_reads "$state_dir"
  printf '  REJECTED forged=%s reason=%s (깨우기 0 · 고정 어휘 진단 1 · 정상 형제 1 · ack 성립)\n' "$label" "$expect_reason"
}
run_shape_alert_provenance_suite() {
  local rows row label mode reason attempted=0 rejected=0
  rows='outsider:shape_alert_outsider:sender_handle_mismatch
same_handle_other_pane:shape_alert_same_handle_other_pane:sender_pane_mismatch
no_pane:shape_alert_no_pane:sender_pane_missing
old_supervisor_handle:shape_alert_old_handle:sender_handle_mismatch
roster_unknown:shape_alert_roster_unknown:roster_not_found
subject:shape_alert_bad_subject:subject_mismatch
board:shape_alert_bad_board:board_mismatch
reason:shape_alert_bad_reason:reason_not_allowed
deliveryRef:shape_alert_bad_ref:ref_format
index:shape_alert_bad_index:index_format
messageType:shape_alert_bad_type:message_type_not_allowed
not_escalation:shape_alert_not_escalation:not_escalation
extra_payload_key:shape_alert_extra_key:payload_keys
body_raw_field:shape_alert_body_raw:body_raw_field'
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    label="${row%%:*}"; row="${row#*:}"
    mode="${row%%:*}"; reason="${row#*:}"
    attempted=$((attempted + 1))
    run_shape_alert_forged_case "$label" "$mode" "$reason"
    rejected=$((rejected + 1))
  done <<< "$rows"
  [ "$attempted" -eq 14 ]
  [ "$rejected" -eq "$attempted" ]
  printf 'PASS F-B11-3 forged shape alert %s/%s 거부 (출처 4종 + schema 10종, 각 wake 0 · ack 1 · 정상 형제 1)\n' "$rejected" "$attempted"
}
# F-B11-2: 상신 첫 시도가 실패해도 조용히 넘기지 않는다. 진단을 드러내고 다음 배달에서
# 다시 시도해 성공하며, 그 사이 정상 형제는 한 번만 깨우고 중복 상신도 없다.
run_shape_report_send_retry_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_PROJECT_SEND_FAIL=once
  run_companion clean "$state_dir" malformed_id_object "$COMPANION" "$state_dir/routing-ledger.jsonl" \
    'shape report retried after first failure' \
    '[ "$(count_matches . "$state_dir/acks.log")" -ge 1 ]'
  unset FAKE_PROJECT_SEND_FAIL
  [ "$(count_matches 'CHECK_DIAGNOSTIC shape_report_send_failed' "$state_dir/output.log")" -ge 1 ]
  [ "$(count_matches 'message_shape_report_failed delivery=delivery_bad_id index=0' "$state_dir/relay.log")" -ge 1 ]
  [ "$(count_matches 'orchestration send --run run_project --subject message_shape_quarantined:board_test' "$state_dir/calls.log")" -eq 2 ]
  [ "$(count_matches 'message_shape_quarantined:board_test' "$state_dir/project-sends.log")" -eq 1 ]
  [ "$(count_matches 'SIGNAL question term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'message_shape_quarantined delivery=delivery_bad_id index=0' "$state_dir/relay.log")" -eq 1 ]
  [ "$(count_matches '--run run_project --ack delivery_bad_id' "$state_dir/calls.log")" -ge 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS F-B11-2 report send fails once -> retried, one report, one good wake\n'
}
# F-B11-2: 계속 실패해도 무한 재시도로 큐를 잡아두지 않는다. 한도에서 포기하되 포기 사실을
# 남기고 Delivery 를 ack 해 정상 형제와 다음 편지가 계속 흐르게 한다.
run_shape_report_send_exhausted_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_PROJECT_SEND_FAIL=always
  export COMPANION_MAX_WAKE_ATTEMPTS=2
  run_companion clean "$state_dir" malformed_id_object "$COMPANION" "$state_dir/routing-ledger.jsonl" \
    'shape report gives up after the retry budget' \
    '[ "$(count_matches . "$state_dir/acks.log")" -ge 1 ]'
  unset FAKE_PROJECT_SEND_FAIL
  export COMPANION_MAX_WAKE_ATTEMPTS=999
  [ "$(count_matches 'orchestration send --run run_project --subject message_shape_quarantined:board_test' "$state_dir/calls.log")" -eq 2 ]
  [ "$(count_matches 'message_shape_quarantined:board_test' "$state_dir/project-sends.log")" -eq 0 ]
  [ "$(count_matches 'message_shape_report_exhausted delivery=delivery_bad_id index=0 reason=message_id_type attempts=2' "$state_dir/relay.log")" -eq 1 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC shape_report_send_failed' "$state_dir/output.log")" -ge 1 ]
  [ "$(count_matches 'SIGNAL question term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches '--run run_project --ack delivery_bad_id' "$state_dir/calls.log")" -ge 1 ]
  # F-B11-3 중요2: 포기 사실이 파일에만 남고 소비자 0 이면 선행 실패와 같은 방식으로 다시
  # 묻힌다. 상신 채널이 완전히 막혔으므로 편지가 아닌 독립 경로(감독 terminal)로 정확히
  # 1회 알린다. 싣는 값은 board·허용 목록 안의 reason·deliveryRef 뿐이다.
  [ "$(count_matches 'SIGNAL message_shape_report_exhausted board=board_test deliveryRef=[0-9a-f]{12} reason=message_id_type' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'shape_report_exhausted_wake board=board_test deliveryRef=[0-9a-f]{12} reason=message_id_type wake=1' "$state_dir/relay.log")" -eq 1 ]
  # 비상 알림에도 원 malformed 원문·카드 식별자·deliveryId 원문은 없다.
  [ "$(count_matches 'task_bad' "$state_dir/sends.log")" -eq 0 ]
  [ "$(count_matches 'ctx_bad' "$state_dir/sends.log")" -eq 0 ]
  [ "$(count_matches 'delivery_bad_id' "$state_dir/sends.log")" -eq 0 ]
  # 비상 경로는 편지를 새로 만들지 않는다: 상신 시도는 한도 2회 그대로다(재귀 0).
  [ "$(count_matches 'orchestration send' "$state_dir/calls.log")" -eq 2 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS F-B11-2 report send keeps failing -> bounded retries, visible give-up, queue keeps flowing\n'
  printf 'PASS F-B11-3 상신 한도 소진 -> 비상 직접 wake 1 (원문 0 · 추가 편지 0 · ack 성립)\n'
}
# F-B11-3: 상신이 정상 성공한 판에서는 비상 wake 가 0 이어야 한다(과잉 깨우기 금지).
run_shape_report_no_emergency_when_ok_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" malformed_id_object
  [ "$(count_matches 'message_shape_quarantined:board_test' "$state_dir/project-sends.log")" -eq 1 ]
  [ "$(count_matches 'SIGNAL message_shape_report_exhausted' "$state_dir/sends.log")" -eq 0 ]
  [ "$(count_matches 'shape_report_exhausted_wake' "$state_dir/relay.log")" -eq 0 ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC shape_emergency' "$state_dir/output.log")" -eq 0 ]
  [ ! -f "$state_dir/shape-emergency.board_test.state" ]
  printf 'PASS F-B11-3 상신 정상 성공 -> 비상 wake 0, 비상 상태 파일 0\n'
}
# F-B11-3: 같은 프로세스에서 같은 Delivery 가 재생돼도 비상 wake 는 1회로 유지된다.
run_shape_report_emergency_replay_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_PROJECT_SEND_FAIL=always
  export FAKE_ACK_FAIL_ONCE=1
  export COMPANION_MAX_WAKE_ATTEMPTS=2
  run_companion clean "$state_dir" malformed_id_object "$COMPANION" "$state_dir/routing-ledger.jsonl" \
    'same delivery replayed after ack failure' \
    '[ "$(count_matches . "$state_dir/acks.log")" -ge 2 ]'
  unset FAKE_PROJECT_SEND_FAIL FAKE_ACK_FAIL_ONCE
  export COMPANION_MAX_WAKE_ATTEMPTS=999
  [ "$(count_matches 'SIGNAL message_shape_report_exhausted board=board_test' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'shape_report_exhausted_wake board=board_test' "$state_dir/relay.log")" -eq 1 ]
  [ "$(count_matches 'SIGNAL question term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ]
  printf 'PASS F-B11-3 같은 Delivery 재생 -> 비상 wake 여전히 1\n'
}
# F-B11-3: 직접 깨우기까지 실패해도 조용히 숨기지 않는다. 다음 자가점검이 읽는 고정 상태
# 파일에 fail-closed 로 남고, 그 파일을 실제로 읽는 소비자가 있다는 것까지 증명한다.
# (새 감시 프로세스는 만들지 않는다 — 소비자는 이 companion 루프의 자가점검 한 곳이다.)
run_shape_emergency_wake_failure_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_PROJECT_SEND_FAIL=always
  export FAKE_SEND_FAIL_TEXT_MATCH=message_shape_report_exhausted
  export COMPANION_MAX_WAKE_ATTEMPTS=2
  run_companion clean "$state_dir" malformed_id_object "$COMPANION" "$state_dir/routing-ledger.jsonl" \
    'emergency wake failure consumed by the next self-check' \
    '[ "$(count_matches "CHECK_DIAGNOSTIC shape_emergency_wake_pending" "$state_dir/output.log")" -ge 1 ]'
  unset FAKE_PROJECT_SEND_FAIL FAKE_SEND_FAIL_TEXT_MATCH
  export COMPANION_MAX_WAKE_ATTEMPTS=999
  # 실패를 드러낸다.
  [ "$(count_matches 'CHECK_DIAGNOSTIC shape_emergency_wake_failed ref=[0-9a-f]{12} reason=message_id_type' "$state_dir/output.log")" -ge 1 ]
  [ "$(count_matches 'shape_report_exhausted_wake_failed board=board_test deliveryRef=[0-9a-f]{12} reason=message_id_type wake=0 fail_closed=1' "$state_dir/relay.log")" -ge 1 ]
  # 고정 상태 파일에 fail-closed 로 남는다.
  [ -f "$state_dir/shape-emergency.board_test.state" ]
  [ "$(count_matches '^pending\|[0-9a-f]{12}\|message_id_type$' "$state_dir/shape-emergency.board_test.state")" -ge 1 ]
  [ "$(count_matches 'delivery_bad_id' "$state_dir/shape-emergency.board_test.state")" -eq 0 ]
  [ "$(count_matches 'task_bad' "$state_dir/shape-emergency.board_test.state")" -eq 0 ]
  # 소비자가 실제로 그 파일을 읽는다(읽었다는 증거가 자가점검 진단으로 나온다).
  [ "$(count_matches 'CHECK_DIAGNOSTIC shape_emergency_wake_pending ref=[0-9a-f]{12} reason=message_id_type' "$state_dir/output.log")" -ge 1 ]
  # 실패해도 정상 형제와 큐는 계속 흐른다.
  [ "$(count_matches 'SIGNAL question term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches '--run run_project --ack delivery_bad_id' "$state_dir/calls.log")" -ge 1 ]
  printf 'PASS F-B11-3 비상 직접 wake 실패 -> fail-closed 상태 파일 + 다음 자가점검이 읽음\n'
}
# F-B11-3: 첫 비상 깨우기만 실패하면 다음 자가점검이 회수해 같은 파일을 recovered 로 닫는다.
run_shape_emergency_recovery_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_PROJECT_SEND_FAIL=always
  export FAKE_SEND_FAIL_TEXT_MATCH=message_shape_report_exhausted
  export FAKE_SEND_FAIL_TEXT_ONCE=1
  export COMPANION_MAX_WAKE_ATTEMPTS=2
  run_companion clean "$state_dir" malformed_id_object "$COMPANION" "$state_dir/routing-ledger.jsonl" \
    'emergency wake recovered by the next self-check' \
    '[ "$(count_matches "^recovered" "$state_dir/shape-emergency.board_test.state")" -ge 1 ]'
  unset FAKE_PROJECT_SEND_FAIL FAKE_SEND_FAIL_TEXT_MATCH FAKE_SEND_FAIL_TEXT_ONCE
  export COMPANION_MAX_WAKE_ATTEMPTS=999
  [ "$(count_matches '^pending\|[0-9a-f]{12}\|message_id_type$' "$state_dir/shape-emergency.board_test.state")" -eq 1 ]
  [ "$(count_matches '^recovered\|[0-9a-f]{12}\|message_id_type$' "$state_dir/shape-emergency.board_test.state")" -eq 1 ]
  [ "$(count_matches 'shape_report_exhausted_wake board=board_test deliveryRef=[0-9a-f]{12} reason=message_id_type wake=1 recovered=1' "$state_dir/relay.log")" -eq 1 ]
  # 회수 뒤에는 같은 항목으로 다시 깨우지 않는다.
  [ "$(count_matches 'shape_report_exhausted_wake board=board_test' "$state_dir/relay.log")" -eq 1 ]
  printf 'PASS F-B11-3 비상 wake 첫 실패 -> 다음 자가점검이 회수하고 상태 파일을 닫음\n'
}
run_malformed_id_case() {
  local label="$1" delivery_mode="$2" reason="$3" state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" "$delivery_mode"
  assert_malformed_id_contract "$state_dir" "$reason"
  assert_no_screen_reads "$state_dir"
  printf '  QUARANTINED bad_id=%s reason=%s (불량 깨우기 0 · 가시 진단 1 · 정상 깨우기 1 · ack 성립)\n' "$label" "$reason"
}
run_malformed_id_suite() {
  local attempted=0 isolated=0 variants label mode reason
  variants='empty:malformed_id_empty:message_id_empty
missing:malformed_id_missing:message_id_missing
null:malformed_id_null:message_id_null
object:malformed_id_object:message_id_type
array:malformed_id_array:message_id_type
number:malformed_id_number:message_id_type
boolean:malformed_id_bool:message_id_type'
  while IFS=: read -r label mode reason; do
    [ -n "$label" ] || continue
    attempted=$((attempted + 1))
    run_malformed_id_case "$label" "$mode" "$reason"
    isolated=$((isolated + 1))
  done <<< "$variants"
  [ "$attempted" -eq 7 ]
  [ "$isolated" -eq "$attempted" ]
  printf 'PASS F-B11 malformed messageId %s종 격리: 정상 형제 편지 %s/%s 보존, Delivery 전체 중단 0건\n' \
    "$attempted" "$isolated" "$attempted"
}
# 불량 1통 뒤 정상 2통: 형제 편지가 한 통만 살아남는 부분 통과를 막는다.
run_malformed_id_two_good_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" malformed_id_two_good
  [ "$(count_matches 'SIGNAL question term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 2 ]
  [ "$(count_matches 'task=task_bad dispatch=ctx_bad' "$state_dir/sends.log")" -eq 0 ]
  [ "$(count_matches 'message_shape_quarantined delivery=delivery_bad_id_two_good index=0' "$state_dir/relay.log")" -eq 1 ]
  [ "$(count_matches '--run run_project --ack delivery_bad_id_two_good' "$state_dir/calls.log")" -ge 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS F-B11 malformed head + two good questions -> both good letters wake\n'
}
# 실제 중복 경계: ack 첫 시도가 실패해 같은 Delivery 가 그대로 다시 배달돼도 정상 편지는
# 다시 깨우지 않고, malformed 진단도 다시 남기지 않는다(무한 반복 금지).
run_ack_retry_dedup_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_ACK_FAIL_ONCE=1
  run_companion clean "$state_dir" malformed_id_object "$COMPANION" "$state_dir/routing-ledger.jsonl" \
    'ack retried after first failure' '[ "$(count_matches . "$state_dir/acks.log")" -ge 2 ]'
  unset FAKE_ACK_FAIL_ONCE
  [ "$(count_matches 'CHECK_DIAGNOSTIC ack_failed' "$state_dir/output.log")" -ge 1 ]
  [ "$(count_matches '--run run_project --ack delivery_bad_id' "$state_dir/calls.log")" -ge 2 ]
  [ "$(count_matches 'SIGNAL question term_worker task=task_good dispatch=ctx_good' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'message_shape_quarantined delivery=delivery_bad_id index=0' "$state_dir/relay.log")" -eq 1 ]
  # F-B11-2: 같은 Delivery 가 재생돼도 구조화 상신은 정확히 1회다(중복 상신 금지).
  [ "$(count_matches 'message_shape_quarantined:board_test' "$state_dir/project-sends.log")" -eq 1 ]
  [ "$(count_matches 'orchestration send --run run_project --subject message_shape_quarantined:board_test' "$state_dir/calls.log")" -eq 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS F-B11 ack first failure then retry -> one good wake, one malformed diagnostic\n'
}
# B6: 식별자 없는 보고는 그 편지 한 통만 격리하고 큐는 계속 흐른다. 예전처럼 Delivery
# 전체를 붙잡아 두지 않는다(선두 차단 제거). 격리는 조용한 폐기가 아니라 로그에 남는다.
run_malformed_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" malformed_mix
  [ "$(count_matches 'MALFORMED_LIFECYCLE_REPORT type=escalation' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'message_quarantined message=bad_1 type=escalation sender=term_worker reason=malformed_lifecycle_report' "$state_dir/relay.log")" -eq 1 ]
  [ "$(count_matches '--run run_project --ack delivery_1' "$state_dir/calls.log")" -ge 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS malformed report -> quarantined with a visible log line, queue keeps flowing\n'
}
# ---------------- 거부 증거 (rejection evidence) ----------------
# 요구되는 모양은 "결함이 있으면 이 시험이 떨어진다"이지 "결함이 있음을 확인했다"가 아니다.
# 그래서 결함을 흉내 내는 스위치를 production 코드에 넣지 않는다. 대신 B6 이전의 실제
# 구현 원본을 고정 커밋에서 그대로 꺼내 같은 계약 검사식을 걸고, 실제로 떨어지는 것을 본다.
# 아래 assert_*_contract 들이 진짜 증거다: 구현을 되돌리면 그 검사가 그대로 빨간불이 된다.
# 전체 확인은 한 줄로 재현된다 (반드시 비정상 종료해야 한다):
#   COMPANION_UNDER_TEST="$(가져온 B6 이전 원본)" bash test-conductor-companion.sh
PREFIX_COMMIT=3ffc0bd
PREFIX_COMPANION=""
setup_prefix_companion() {
  local repo_root prefix_dir
  repo_root=$(cd "$SKILL_DIR/../.." && pwd)
  # 원본이 형제 스크립트(routing-ledger-append.sh)를 자기 위치 기준으로 찾으므로 같이
  # 놓아 준다. 그래야 "파일이 없어서" 떨어지는 가짜 빨간불이 아니라 B6 동작 차이로만
  # 떨어진다.
  prefix_dir=$(mktemp -d /tmp/orca-b6-prefix.XXXXXX)
  ln -sf "$SKILL_DIR/scripts/routing-ledger-append.sh" "$prefix_dir/routing-ledger-append.sh"
  PREFIX_COMPANION="$prefix_dir/conductor-companion.sh"
  # 원본을 못 꺼내면 조용히 건너뛰지 않는다. 증거 없는 통과가 이 카드에서 가장 나쁜 결과다.
  if ! git -C "$repo_root" show "$PREFIX_COMMIT:skills/orca-conductor/scripts/conductor-companion.sh" > "$PREFIX_COMPANION" 2>/dev/null; then
    printf 'REJECTION_EVIDENCE_UNAVAILABLE commit=%s (B6 이전 원본을 꺼내지 못했다)\n' "$PREFIX_COMMIT" >&2
    return 1
  fi
  [ -s "$PREFIX_COMPANION" ]
  chmod +x "$PREFIX_COMPANION"
  # 꺼낸 것이 정말 B6 이전인지 확인한다. B6 표식이 들어 있으면 그것은 증거가 아니다.
  if rg -q 'quarantine_message' "$PREFIX_COMPANION"; then
    printf 'REJECTION_EVIDENCE_INVALID commit=%s already contains the B6 fix\n' "$PREFIX_COMMIT" >&2
    return 1
  fi
  printf '  prefix implementation extracted: commit=%s lines=%s\n' "$PREFIX_COMMIT" "$(wc -l < "$PREFIX_COMPANION" | tr -d ' ')"
}
# B6 이전 실제 구현에 같은 계약 검사를 걸어 떨어지는 것을 본다. 통과해 버리면 그 계약
# 검사는 결함을 구분하지 못하는 것이므로(=증거가 아니므로) 여기서 즉시 실패시킨다.
assert_prefix_fails_contract() {
  local label="$1" delivery_mode="$2" contract_fn="$3" state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" "$delivery_mode" "$PREFIX_COMPANION"
  if "$contract_fn" "$state_dir" >/dev/null 2>&1; then
    printf 'REJECTION_EVIDENCE_MISSING contract=%s (B6 이전 구현이 이 검사를 통과했다)\n' "$contract_fn" >&2
    return 1
  fi
  printf '  RED prefix=%s contract=%s (틀린 구현에서 실제로 떨어짐)\n' "$label" "$contract_fn"
}
# 큐 맨 앞의 식별자 없는 편지 뒤에 있는 편지 2통이 모두 배달되고 Delivery 가 ack 된다.
assert_head_of_line_contract() {
  local state_dir="$1"
  [ "$(count_matches 'SIGNAL escalation term_worker task=task_hol_1 dispatch=ctx_hol_1' "$state_dir/sends.log")" -eq 1 ] || return 1
  [ "$(count_matches 'SIGNAL decision_gate term_worker task=task_hol_2 dispatch=ctx_hol_2' "$state_dir/sends.log")" -eq 1 ] || return 1
  [ "$(count_matches '--run run_project --ack delivery_hol' "$state_dir/calls.log")" -ge 1 ] || return 1
}
# 격리 사실은 relay 로그와 companion 출력 둘 다에 남아야 한다(조용한 폐기 금지).
assert_quarantine_visible() {
  local state_dir="$1"
  [ "$(count_matches 'message_quarantined message=hol_bad type=escalation sender=term_worker reason=malformed_lifecycle_report' "$state_dir/relay.log")" -eq 1 ] || return 1
  [ "$(count_matches 'message_quarantined message=hol_bad' "$state_dir/output.log")" -ge 1 ] || return 1
}
run_head_of_line_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" head_of_line
  assert_head_of_line_contract "$state_dir"
  assert_quarantine_visible "$state_dir"
  [ "$(count_matches 'MALFORMED_LIFECYCLE_REPORT type=escalation sender=term_worker message=hol_bad' "$state_dir/sends.log")" -eq 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS head-of-line: 식별자 없는 선두 편지 격리 + 뒤 2통 정상 배달 + Delivery ack\n'
}
# 슈퍼 지시(type=escalation, 카드 식별자 없음)는 카드 보고로 오분류되지 않는다.
assert_super_directive_accepted() {
  local state_dir="$1"
  [ "$(count_matches 'SIGNAL super_directive sender=term_super_coord message=super_esc_1' "$state_dir/sends.log")" -eq 1 ] || return 1
  [ "$(count_matches MALFORMED_LIFECYCLE_REPORT "$state_dir/sends.log")" -eq 0 ] || return 1
  [ "$(count_matches 'message_quarantined message=super_esc_1' "$state_dir/relay.log")" -eq 0 ] || return 1
  [ "$(count_matches 'SIGNAL escalation term_worker task=task_esc_behind dispatch=ctx_esc_behind' "$state_dir/sends.log")" -eq 1 ] || return 1
  [ "$(count_matches '--run run_project --ack delivery_super_esc' "$state_dir/calls.log")" -ge 1 ] || return 1
}
run_super_escalation_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" super_escalation
  assert_super_directive_accepted "$state_dir"
  assert_no_screen_reads "$state_dir"
  printf 'PASS super directive as escalation without taskId/dispatchId -> directive, not malformed\n'
}
run_super_escalation_ask_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" super_escalation_ask
  [ "$(count_matches 'SIGNAL super_directive sender=term_super_coord message=super_esc_1' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches MALFORMED_LIFECYCLE_REPORT "$state_dir/sends.log")" -eq 0 ]
  printf 'PASS super directive as ask without identifiers -> directive, not malformed\n'
}
run_super_escalation_duplicate_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" super_escalation_duplicate
  [ "$(count_matches 'super_directive sender=term_super_coord message=super_esc_same' "$state_dir/sends.log")" -eq 1 ]
  printf 'PASS same super directive replayed -> exactly one wake\n'
}
# 거부 증거 본체: B6 이전 실제 구현을 넣고 계약 검사 3종을 그대로 돌려 빨간불을 본다.
# B6: 후보 대조용 우편함 조회도 자기 project Run 으로 좁혀야 한다. 여기는 포화 판정이
# 아예 없어서, 전역 창이 다른 판 편지로 차면 실제로 있는 공식 편지를 "없음"으로 보고
# 감독을 오경보로 깨운다. 기본 경로에 범위가 붙는지 직접 확인한다.
assert_candidate_scan_scoped() {
  local state_dir="$1"
  [ "$(count_matches 'inbox --full --terminal run:run_project' "$state_dir/calls.log")" -ge 1 ] || return 1
  # 범위를 안 좁힌 전역 조회가 한 번이라도 남아 있으면 안 된다.
  [ "$(count_matches 'inbox --full --limit' "$state_dir/calls.log")" -eq 0 ] || return 1
}
run_candidate_scan_scoped_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion candidate_present "$state_dir"
  assert_candidate_scan_scoped "$state_dir"
  printf 'PASS candidate ledger scan: 기본 경로에서 자기 project Run 으로 좁혀 조회한다\n'
}
run_prefix_rejection_suite() {
  local attempted=0 red=0
  setup_prefix_companion
  attempted=$((attempted + 1)); assert_prefix_fails_contract head_of_line head_of_line assert_head_of_line_contract; red=$((red + 1))
  attempted=$((attempted + 1)); assert_prefix_fails_contract quarantine_visible head_of_line assert_quarantine_visible; red=$((red + 1))
  attempted=$((attempted + 1)); assert_prefix_fails_contract super_directive super_escalation assert_super_directive_accepted; red=$((red + 1))
  attempted=$((attempted + 1)); assert_prefix_fails_contract candidate_scan candidate_present assert_candidate_scan_scoped; red=$((red + 1))
  [ "$attempted" -eq 4 ]
  [ "$red" -eq "$attempted" ]
  printf 'PASS rejection evidence: B6 이전 실제 구현(%s)에 계약 검사 %s개를 걸어 %s개가 실제로 떨어졌다\n' "$PREFIX_COMMIT" "$attempted" "$red"
}
# 슈퍼 사칭 거부. 발신 handle+pane 이 그 순간 run-show 가 돌려준 권위 쌍과 정확히 맞을
# 때만 지시다. 아래 변형은 하나도 지시로 인정되면 안 된다(super_directive wake 0).
run_super_impostor_case() {
  local label="$1" delivery_mode="$2" state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" "$delivery_mode"
  if [ "$(count_matches 'SIGNAL super_directive' "$state_dir/sends.log")" -ne 0 ]; then
    printf 'IMPOSTOR_ACCEPTED variant=%s\n' "$label" >&2
    return 1
  fi
  printf '  REJECTED impostor=%s\n' "$label"
}
run_super_impostor_suite() {
  local attempted=0 rejected=0
  local variants='wrong_sender_handle:super_escalation_wrong_handle
wrong_sender_pane:super_escalation_wrong_pane
missing_sender_pane:super_escalation_no_pane
self_declared_payload:super_escalation_forged_payload'
  while IFS=: read -r label mode; do
    [ -n "$label" ] || continue
    attempted=$((attempted + 1))
    run_super_impostor_case "$label" "$mode"
    rejected=$((rejected + 1))
  done <<< "$variants"
  # run-show 권위 자체가 어긋나는 변형: 같은 정상 편지를 쓰되 권위 조회 결과만 바꾼다.
  export FAKE_SUPER_RUN_SHOW_ID=run_other
  attempted=$((attempted + 1)); run_super_impostor_case runshow_other_run super_escalation; rejected=$((rejected + 1))
  unset FAKE_SUPER_RUN_SHOW_ID
  export FAKE_SUPER_COORDINATOR_PANE=
  attempted=$((attempted + 1)); run_super_impostor_case runshow_missing_pane super_escalation; rejected=$((rejected + 1))
  unset FAKE_SUPER_COORDINATOR_PANE
  export FAKE_SUPER_COORDINATOR_HANDLE=term_other_coord
  attempted=$((attempted + 1)); run_super_impostor_case runshow_other_coordinator super_escalation; rejected=$((rejected + 1))
  unset FAKE_SUPER_COORDINATOR_HANDLE
  export FAKE_RUN_SHOW_FAIL=1
  attempted=$((attempted + 1)); run_super_impostor_case runshow_unreachable super_escalation; rejected=$((rejected + 1))
  unset FAKE_RUN_SHOW_FAIL
  [ "$attempted" -eq 8 ]
  [ "$rejected" -eq "$attempted" ]
  printf 'PASS super impostor: attempted=%s rejected=%s (거부되지 않은 변형 0개)\n' "$attempted" "$rejected"
}
# 일시적 깨우기 실패는 여전히 Delivery 재시도로 다룬다. 재시도 한도를 시험에서 크게
# 고정해 루프 횟수(타이밍)에 결과가 흔들리지 않게 한다.
run_enter_failure_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_ENTER_MODE=fail
  run_companion clean "$state_dir" fifo
  [ ! -f "$state_dir/acks.log" ]
  [ "$(count_matches 'WAKE_FAIL term_supervisor' "$state_dir/output.log")" -gt 0 ]
  export FAKE_ENTER_MODE=ok
  printf 'PASS Enter failure leaves Delivery unacked for replay (재시도 여력이 남은 동안)\n'
}
# B6: 깨우기가 계속 실패해도 그 한 통이 큐를 영구히 막지 못한다. 한도(기본 3회)를 넘기면
# 그 편지만 격리하고 다음으로 넘어간다 — 재시도 무한 반복도 선두 차단이기 때문이다.
run_wake_failure_bounded_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_ENTER_MODE=fail
  export COMPANION_MAX_WAKE_ATTEMPTS=2
  run_companion clean "$state_dir" fifo "$COMPANION" "$state_dir/routing-ledger.jsonl" 'wake failure quarantined and first delivery acknowledged' '[ "$(count_matches "wake_failed_exhausted" "$state_dir/relay.log")" -ge 1 ] && [ "$(count_matches "delivery_1" "$state_dir/acks.log")" -ge 1 ]'
  export COMPANION_MAX_WAKE_ATTEMPTS=999
  export FAKE_ENTER_MODE=ok
  [ "$(count_matches 'message_quarantined message=msg_1 type=escalation sender=term_worker reason=wake_failed_exhausted' "$state_dir/relay.log")" -ge 1 ]
  [ "$(count_matches '--run run_project --ack delivery_1' "$state_dir/calls.log")" -ge 1 ]
  printf 'PASS persistent wake failure -> bounded retry then quarantine, queue not blocked forever\n'
}
run_super_reply_once_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" super_reply
  [ "$(read_log "$state_dir/acks.log")" = delivery_super_reply ]
  assert_single_wake "$state_dir"
  [ "$(count_matches 'SIGNAL super_reply sender=term_super message=super_reply_1 targetRunId=run_super' "$state_dir/sends.log")" -eq 1 ]
  printf 'PASS superReply status -> one supervisor text+Enter then one ack\n'
}
run_super_reply_duplicate_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" super_reply_duplicate
  [ "$(read_log "$state_dir/acks.log")" = delivery_super_reply ]
  assert_single_wake "$state_dir"
  [ "$(count_matches 'message=super_reply_same' "$state_dir/sends.log")" -eq 1 ]
  printf 'PASS repeated superReply messageId -> zero additional wake\n'
}
run_super_reply_enter_failure_case() {
  local state_dir replay_json
  state_dir=$(new_state)
  export FAKE_ENTER_MODE=fail
  run_companion clean "$state_dir" super_reply
  [ ! -f "$state_dir/acks.log" ]
  [ "$(count_matches 'WAKE_FAIL term_supervisor' "$state_dir/output.log")" -gt 0 ]
  replay_json=$(FAKE_ORCA_STATE_DIR="$state_dir" FAKE_DELIVERY_MODE=super_reply "$FIXTURE" orchestration check --run run_project --json)
  python3 -c 'import json,sys; assert json.load(sys.stdin)["result"]["deliveryId"] == "delivery_super_reply"' <<< "$replay_json"
  export FAKE_ENTER_MODE=ok
  printf 'PASS superReply Enter failure -> no ack and same Delivery replays\n'
}
run_ordinary_status_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" ordinary_status
  [ "$(read_log "$state_dir/acks.log")" = delivery_ordinary_status ]
  [ "$(count_matches '--terminal term_supervisor' "$state_dir/sends.log")" -eq 0 ]
  printf 'PASS ordinary status -> zero wake and normal ack\n'
}
run_consumer_fenced_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_CHECK_FAILURE=consumer_fenced
  run_companion clean "$state_dir"
  [ ! -f "$state_dir/acks.log" ]
  [ "$(count_matches 'CHECK_DIAGNOSTIC consumer_fenced' "$state_dir/output.log")" -eq 1 ]
  export FAKE_CHECK_FAILURE=""
  printf 'PASS consumer_fenced is fail-closed without ack\n'
}
run_owner_mismatch_case() {
  local state_dir owner_status
  state_dir=$(new_state)
  export ORCA_TERMINAL_HANDLE=term_other
  set +e
  FAKE_ORCA_STATE_DIR="$state_dir" FAKE_RELAY_ALERT_MODE=clean FAKE_DELIVERY_MODE=fifo ORCA_BIN="$FIXTURE" RELAY_LOG_FILE="$state_dir/relay.log" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project 999 > "$state_dir/output.log" 2>&1
  owner_status=$?
  set -e
  [ "$owner_status" -eq 4 ]
  rg -q 'consumer_owner_mismatch expected=term_supervisor actual=term_other' "$state_dir/output.log"
  assert_absent 'orchestration check' "$state_dir/calls.log"
  export ORCA_TERMINAL_HANDLE=term_supervisor
  printf 'PASS A1 supervisor-owned pane guard exits 4 before mailbox check\n'
}
# P3B R4 worker_done_auto 시험 헬퍼(중요1/2 + 인접).
# $1=task_list JSON. $2=expect_recorded(1=기록, 0=격리). $3=expect_roundId.
# $4=worker_role(기본 developer). $5=worker_handle(기본 term_worker). $6=dispatch_status(기본 completed).
# $7=roster_all_members override 파일(옵션).
# $8=dispatch_show override JSON(옵션: camelCase/status 반례용).
RUN_ID_TEST="run_2a88f926a4e0"
TID_TEST="task_bf886c87af30"
DID_TEST="ctx_de177164da67"
run_wd_scenario() {
  local tl_content="$1" expect_recorded="$2" expect_round="${3:-}"
  local wd_role="${4:-developer}" wd_handle="${5:-term_worker}" wd_status="${6:-completed}"
  local roster_override="${7:-}" ds_override="${8:-}"
  local state_dir
  state_dir=$(new_state)
  printf '%s\n' "$tl_content" > "$state_dir/task_list.json"
  if [ -n "$ds_override" ]; then
    printf '%s\n' "$ds_override" > "$state_dir/dispatch_show.json"
  else
    cat > "$state_dir/dispatch_show.json" <<JSON
{"result":{"dispatch":{"id":"$DID_TEST","run_id":"$RUN_ID_TEST","task_id":"$TID_TEST","assignee_handle":"$wd_handle","assignee_pane_key":"pane_worker","status":"$wd_status"}}}
JSON
  fi
  export FAKE_RUN_ID="$RUN_ID_TEST" FAKE_ORCA_STATE_DIR="$state_dir" FAKE_RELAY_ALERT_MODE=clean FAKE_DELIVERY_MODE=worker_done
  export FAKE_WORKER_ROLE="$wd_role" FAKE_WORKER_HANDLE="$wd_handle" FAKE_WORKER_PANE="pane_worker"
  [ -n "$roster_override" ] && cp "$roster_override" "$state_dir/roster_all_members.json"
  export ORCA_BIN="$FIXTURE" RELAY_LOG_FILE="$state_dir/relay.log" ROUTING_LEDGER_FILE="$state_dir/routing-ledger.jsonl"
  WATCH_DEADLINE_SEC="$TEST_WAIT_CEILING_SEC" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run "$RUN_ID_TEST" --super-run run_super 999 > "$state_dir/output.log" 2>&1 &
  local pid=$!
  wait_for_test_condition "$pid" "$state_dir" 'worker_done delivery fully processed' '[ "$(count_matches "orchestration check --run $RUN_ID_TEST --json" "$state_dir/calls.log")" -ge 2 ]'
  local ledger="$state_dir/routing-ledger.jsonl"
  if [[ "$expect_recorded" == "1" ]]; then
    python3 - "$ledger" "$expect_round" <<'PY'
import json, os, sys
# F-B7: 부재(파일 자체가 없음)와 0건(있고 비어 있음)을 구분해서 말한다. 예전에는 부재가
# FileNotFoundError 역추적으로만 드러나서 "무엇이 왜 틀렸는지"가 사라졌다.
path = sys.argv[1]
assert os.path.exists(path), f"원장 파일이 아예 없다(부재): {path}"
lines = [l for l in open(path) if l.strip()]
assert len(lines) == 1, f"expected 1 ledger line, got {len(lines)} (파일은 있음: {path})"
e = json.loads(lines[0])
assert e["eventType"] == "worker_done_auto"
assert e["runId"] == "run_2a88f926a4e0" and e["roundId"] == sys.argv[2]
assert e["taskId"] == "task_bf886c87af30" and e["dispatchId"] == "ctx_de177164da67"
assert e["payload"]["taskId"] == "task_bf886c87af30" and e["payload"]["dispatchId"] == "ctx_de177164da67"
PY
  else
    [ "$(count_matches 'worker_done_auto' "$ledger")" -eq 0 ] || { echo "FAIL: expected 0 ledger lines, got $(count_matches 'worker_done_auto' "$ledger")" >&2; exit 1; }
  fi
  unset FAKE_RUN_ID FAKE_WORKER_ROLE FAKE_WORKER_HANDLE FAKE_WORKER_PANE
}
# 정상 task-list 템플릿(공식 필드: result.runId, 행 run_id, deps JSON 문자열)
TL_IMPL='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":1,"tasks":[{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":"[]","status":"completed"}]}}'
TL_REV='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":2,"tasks":[{"id":"task_111111110000","run_id":"run_2a88f926a4e0","deps":"[]","status":"completed"},{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":"[\"task_111111110000\"]","status":"completed"}]}}'
run_worker_done_ledger_case() {
  run_wd_scenario "$TL_IMPL" 1 "$TID_TEST"
  printf 'PASS A2 worker_done implementer -> roundId=self\n'
}
run_worker_done_reviewer_case() {
  run_wd_scenario "$TL_REV" 1 "task_111111110000" reviewer
  printf 'PASS A2b worker_done reviewer -> roundId=deps[0]\n'
}
run_worker_done_reviewer_variant_case() {
  run_wd_scenario "$TL_REV" 1 "task_111111110000" "reviewer-r2"
  printf 'PASS A2b2 worker_done reviewer-r2 -> roundId=deps[0]\n'
}
run_worker_done_ambiguous_case() {
  local tl='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":1,"tasks":[{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":"[\"task_aaaaaaaaaaaa\",\"task_bbbbbbbbbbbb\"]","status":"completed"}]}}'
  run_wd_scenario "$tl" 0 ""
  printf 'PASS A2c worker_done reviewer multi-deps -> quarantined\n'
}
run_worker_done_assignee_mismatch_case() {
  run_wd_scenario "$TL_IMPL" 0 "" developer "term_someone_else" completed
  printf 'PASS A2d worker_done assignee mismatch -> quarantined\n'
}
run_worker_done_dispatch_failed_case() {
  run_wd_scenario "$TL_IMPL" 0 "" developer term_worker failed
  printf 'PASS A2e worker_done dispatch failed -> quarantined\n'
}
run_worker_done_role_unknown_case() {
  run_wd_scenario "$TL_IMPL" 0 "" "supervisor-worker"
  printf 'PASS A2f worker_done unrecognized role -> quarantined\n'
}
run_worker_done_bad_row_case() {
  local tl='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":2,"tasks":[{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":"[]","status":"completed"},{"id":"task_222222220000","run_id":"run_other","deps":"[]","status":"ready"}]}}'
  run_wd_scenario "$tl" 0 ""
  printf 'PASS A2g worker_done task-list row wrong run -> quarantined\n'
}
run_worker_done_missing_envelope_case() {
  local tl='{"result":{"tasks":[{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":"[]","status":"completed"}]}}'
  run_wd_scenario "$tl" 0 ""
  printf 'PASS A2h worker_done missing envelope (ok/runId/count) -> quarantined\n'
}
run_worker_done_row_missing_run_case() {
  local tl='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":1,"tasks":[{"id":"task_bf886c87af30","deps":"[]","status":"completed"}]}}'
  run_wd_scenario "$tl" 0 ""
  printf 'PASS A2i worker_done row missing run -> quarantined\n'
}
run_worker_done_wrong_board_case() {
  local ro; ro=$(mktemp)
  printf '%s\n' '{"ok":true,"result":{"members":[{"id":"r1","project":"project_test","board":"WRONG_BOARD","role":"developer","runId":"run_2a88f926a4e0","pane":"pane_worker","status":"active","lifecycle":"active","live":true,"currentHandle":"term_worker"}]}}' > "$ro"
  run_wd_scenario "$TL_IMPL" 0 "" developer term_worker completed "$ro"
  printf 'PASS A2j worker_done wrong-board roster -> quarantined\n'
}
run_worker_done_deps_array_object_case() {
  local tl='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":1,"tasks":[{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":[],"status":"completed"}]}}'
  run_wd_scenario "$tl" 0 ""
  printf 'PASS A2k worker_done deps array object (not JSON string) -> quarantined\n'
}
run_worker_done_deps_bad_json_case() {
  local tl='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":1,"tasks":[{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":"not-json","status":"completed"}]}}'
  run_wd_scenario "$tl" 0 ""
  printf 'PASS A2l worker_done deps bad JSON string -> quarantined\n'
}
run_worker_done_count_mismatch_case() {
  local tl='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":2,"tasks":[{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":"[]","status":"completed"}]}}'
  run_wd_scenario "$tl" 0 ""
  printf 'PASS A2m worker_done count mismatch -> quarantined\n'
}
# ---- R4 중요1: roster 후보 유일 선택 + 공식 필드 ----
# twin: 정상 board 행 + wrong board 행이 같은 handle+pane 을 가지면 복수 후보로 격리
run_worker_done_twin_candidates_case() {
  local ro; ro=$(mktemp)
  printf '%s\n' '{"ok":true,"result":{"members":[
    {"id":"r1","project":"project_test","board":"board_test","role":"developer","runId":"run_2a88f926a4e0","pane":"pane_worker","status":"active","lifecycle":"active","live":true,"currentHandle":"term_worker"},
    {"id":"r2","project":"project_test","board":"WRONG_BOARD","role":"developer","runId":"run_2a88f926a4e0","pane":"pane_worker","status":"active","lifecycle":"active","live":true,"currentHandle":"term_worker"}
  ]}}' > "$ro"
  run_wd_scenario "$TL_IMPL" 0 "" developer term_worker completed "$ro"
  printf 'PASS A2n worker_done twin candidates same handle+pane -> quarantined (multiple)\n'
}
# run_id 별칭(runId 없음) → 격리
run_worker_done_roster_runid_alias_case() {
  local ro; ro=$(mktemp)
  printf '%s\n' '{"ok":true,"result":{"members":[{"id":"r1","project":"project_test","board":"board_test","role":"developer","run_id":"run_2a88f926a4e0","pane":"pane_worker","status":"active","lifecycle":"active","live":true,"currentHandle":"term_worker"}]}}' > "$ro"
  run_wd_scenario "$TL_IMPL" 0 "" developer term_worker completed "$ro"
  printf 'PASS A2o worker_done roster run_id alias (no runId) -> quarantined\n'
}
# current_handle 별칭(currentHandle 없음) → 후보 안 잡힘 → 0 → 격리
run_worker_done_roster_handle_alias_case() {
  local ro; ro=$(mktemp)
  printf '%s\n' '{"ok":true,"result":{"members":[{"id":"r1","project":"project_test","board":"board_test","role":"developer","runId":"run_2a88f926a4e0","pane":"pane_worker","status":"active","lifecycle":"active","live":true,"current_handle":"term_worker"}]}}' > "$ro"
  run_wd_scenario "$TL_IMPL" 0 "" developer term_worker completed "$ro"
  printf 'PASS A2p worker_done roster current_handle alias (no currentHandle) -> quarantined\n'
}
# live 문자열 "yes" → 격리
run_worker_done_roster_live_string_case() {
  local ro; ro=$(mktemp)
  printf '%s\n' '{"ok":true,"result":{"members":[{"id":"r1","project":"project_test","board":"board_test","role":"developer","runId":"run_2a88f926a4e0","pane":"pane_worker","status":"active","lifecycle":"active","live":"yes","currentHandle":"term_worker"}]}}' > "$ro"
  run_wd_scenario "$TL_IMPL" 0 "" developer term_worker completed "$ro"
  printf 'PASS A2q worker_done roster live string yes -> quarantined\n'
}
# ---- R4 중요2: task-list 공식 필드·상태 집합 ----
# result.run_id 별칭(runId 없음) → 격리
run_worker_done_tl_runid_alias_case() {
  local tl='{"ok":true,"result":{"run_id":"run_2a88f926a4e0","count":1,"tasks":[{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":"[]","status":"completed"}]}}'
  run_wd_scenario "$tl" 0 ""
  printf 'PASS A2r worker_done task-list result.run_id alias (no runId) -> quarantined\n'
}
# 행 runId 별칭(run_id 없음) → 격리
run_worker_done_tl_row_runid_alias_case() {
  local tl='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":1,"tasks":[{"id":"task_bf886c87af30","runId":"run_2a88f926a4e0","deps":"[]","status":"completed"}]}}'
  run_wd_scenario "$tl" 0 ""
  printf 'PASS A2s worker_done task-list row runId alias (no run_id) -> quarantined\n'
}
# 허용 외 상태 active/cancelled/done → 거부
run_worker_done_tl_status_active_case() {
  local tl='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":1,"tasks":[{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":"[]","status":"active"}]}}'
  run_wd_scenario "$tl" 0 ""
  printf 'PASS A2t worker_done task-list status active rejected -> quarantined\n'
}
run_worker_done_tl_status_done_case() {
  local tl='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":1,"tasks":[{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":"[]","status":"done"}]}}'
  run_wd_scenario "$tl" 0 ""
  printf 'PASS A2u worker_done task-list status done rejected -> quarantined\n'
}
# pending+blocked 혼합 정상 목록 → target completed 는 정상 기록
run_worker_done_tl_pending_blocked_mix_case() {
  local tl='{"ok":true,"result":{"runId":"run_2a88f926a4e0","count":3,"tasks":[{"id":"task_bf886c87af30","run_id":"run_2a88f926a4e0","deps":"[]","status":"completed"},{"id":"task_333333330000","run_id":"run_2a88f926a4e0","deps":"[]","status":"pending"},{"id":"task_444444440000","run_id":"run_2a88f926a4e0","deps":"[]","status":"blocked"}]}}'
  run_wd_scenario "$tl" 1 "$TID_TEST"
  printf 'PASS A2v worker_done task-list pending+blocked mixed -> target completed recorded\n'
}
# ---- R4 인접: dispatch-show 공식 필드·상태 ----
# camelCase taskId 별칭(task_id 없음) → 격리
run_worker_done_ds_camelcase_case() {
  run_wd_scenario "$TL_IMPL" 0 "" developer term_worker completed "" \
    '{"result":{"dispatch":{"id":"ctx_de177164da67","run_id":"run_2a88f926a4e0","taskId":"task_bf886c87af30","assignee_handle":"term_worker","assignee_pane_key":"pane_worker","status":"completed"}}}'
  printf 'PASS A2w worker_done dispatch-show camelCase taskId -> quarantined\n'
}
# dispatch-show status done(completed 아님) → 격리
run_worker_done_ds_status_done_case() {
  run_wd_scenario "$TL_IMPL" 0 "" developer term_worker completed "" \
    '{"result":{"dispatch":{"id":"ctx_de177164da67","run_id":"run_2a88f926a4e0","task_id":"task_bf886c87af30","assignee_handle":"term_worker","assignee_pane_key":"pane_worker","status":"done"}}}'
  printf 'PASS A2x worker_done dispatch-show status done -> quarantined\n'
}
# ---- R4: 파생 역할 정상 확인 ----
run_worker_done_dev_variant_case() {
  run_wd_scenario "$TL_IMPL" 1 "$TID_TEST" "developer-r4"
  printf 'PASS A2y worker_done developer-r4 -> roundId=self\n'
}
run_worker_done_researcher_variant_case() {
  run_wd_scenario "$TL_IMPL" 1 "$TID_TEST" "researcher-r4"
  printf 'PASS A2z worker_done researcher-r4 -> roundId=self\n'
}
run_portable_orca_case() {
  local state_dir bin_dir auto_status
  state_dir=$(new_state)
  bin_dir=$(mktemp -d /tmp/orca-relay-bin.XXXXXX)
  ln -s "$FIXTURE" "$bin_dir/orca"
  set +e
  env -u ORCA_BIN PATH="$bin_dir:/usr/bin:/bin" ORCA_TERMINAL_HANDLE=term_supervisor FAKE_ORCA_STATE_DIR="$state_dir" FAKE_RELAY_ALERT_MODE=clean FAKE_DELIVERY_MODE=none COMPANION_POLL_INTERVAL_SEC=0.05 WATCH_DEADLINE_SEC="$TEST_WAIT_CEILING_SEC" RELAY_LOG_FILE="$state_dir/relay.log" ROUTING_LEDGER_FILE="$state_dir/ledger.jsonl" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project 999 > "$state_dir/output.log" 2>&1 &
  local pid=$!
  wait_for_test_condition "$pid" "$state_dir" 'PATH auto-discovery completed one patrol' '[ "$(count_matches "orchestration check --run run_project --json" "$state_dir/calls.log")" -ge 2 ]'
  auto_status=$?
  set -e
  [ "$auto_status" -eq 0 ]
  [ -s "$state_dir/roster.log" ]
  printf 'PASS A3 PATH auto-discovery works without machine-specific path\n'
}
run_kicker_case() {
  local state_dir
  state_dir=$(new_state)
  FAKE_ORCA_STATE_DIR="$state_dir" ORCA_BIN="$FIXTURE" FAKE_RELAY_ALERT_MODE=clean FAKE_DELIVERY_MODE=none RELAY_LOG_FILE="$state_dir/relay.log" WATCH_DEADLINE_SEC="$TEST_WAIT_CEILING_SEC" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project 0 > "$state_dir/output.log" 2>&1 &
  local pid=$!
  wait_for_test_condition "$pid" "$state_dir" 'kicker guidance sent' '[ "$(count_matches "도구 실행 줄 또는 Context% 증가" "$state_dir/sends.log")" -ge 1 ]'
  [ "$(count_matches '도구 실행 줄 또는 Context% 증가' "$state_dir/sends.log")" -gt 0 ]
  [ "$(count_matches '연속 무진행 횟수' "$state_dir/sends.log")" -gt 0 ]
  [ "$(count_matches '2회 연속이면 정체' "$state_dir/sends.log")" -gt 0 ]
  [ "$(count_matches '스피너만으로 STARTED/정상 진행을 판정하지 마세요' "$state_dir/sends.log")" -gt 0 ]
  printf 'PASS A4 kicker keeps progress evidence and two no-progress warning\n'
}
run_relay_bounded_fixture_case() {
  local state_dir relay_json
  state_dir=$(new_state)
  export FAKE_ORCA_STATE_DIR="$state_dir" FAKE_RELAY_ALERT_MODE=relay_bounded
  relay_json=$("$FIXTURE" terminal read --terminal term_supervisor --cursor 10 --limit 50 --json)
  python3 -c 'import json,sys; t=(json.load(sys.stdin)["result"]["terminal"]); assert len(t["tail"]) == 1 and t["nextCursor"] == "12"' <<< "$relay_json"
  rg -q -- '--cursor 10 --limit 50' "$state_dir/calls.log"
  printf 'PASS relay fixture uses bounded cursor snippet input separately from companion\n'
}
run_no_mutation_gate_case() {
  assert_absent '^apply_mutation' "$TEST_FILE"
  assert_absent '^MUT-' "$TEST_FILE"
  printf 'PASS A6/A7 mutation gate is removed; focused mechanical contracts are the gate\n'
}

# 진짜 슈퍼감독 지시 권위는 매 조회 시점 run-show 가 돌려준 안정된 창 신분과 정확히
# 맞을 때만 인정한다. run-show 의 run.id 가 요청한 --super-run 과 같아야 하고,
# coordinator_handle 과 coordinator_pane_key 가 둘 다 있어야 하며, 메시지의 from_handle 과
# sender_pane_key 가 각각 그 둘과 정확히 일치해야 한다. pane 없는 메시지나 pane 없는
# run-show 응답은 wake 0 이다. 고정 handle·제목·본문·payload·단순 handle 불일치는 인증
# 근거가 아니다. 같은 판 worker/reviewer/relay 의 ID 포함 status 는 여기서 잡히지 않고
# wake 0 으로 ack 된다. 실제 권위 super status 는 taskId/dispatchId 가 없어도 messageId
# 단위 1회 wake. 인수 전 발신 편지는 소급 인증하지 않는다(coordinator 교대 후 다음 동적
# 조회부터 새 coordinator 에만 대조).
run_super_directive_once_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" super_directive
  [ "$(read_log "$state_dir/acks.log")" = delivery_super_dir ]
  assert_single_wake "$state_dir"
  rg -q -- 'SIGNAL super_directive sender=term_super_coord message=super_dir_1' "$state_dir/sends.log"
  assert_no_screen_reads "$state_dir"
  printf 'PASS super coordinator status -> one supervisor wake then one ack\n'
}

run_super_directive_duplicate_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" super_directive_duplicate
  [ "$(read_log "$state_dir/acks.log")" = delivery_super_dir ]
  assert_single_wake "$state_dir"
  [ "$(count_matches 'super_directive sender=term_super_coord' "$state_dir/sends.log")" -eq 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS repeated super coordinator messageId -> zero additional wake\n'
}

run_same_board_status_ids_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" same_board_status_ids
  [ "$(read_log "$state_dir/acks.log")" = delivery_same_board_ids ]
  [ "$(count_matches '--terminal term_supervisor' "$state_dir/sends.log")" -eq 0 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS same-board worker/reviewer status with IDs -> zero wake, normal ack\n'
}

run_pre_handover_status_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" pre_handover_status
  [ "$(read_log "$state_dir/acks.log")" = delivery_pre_handover ]
  [ "$(count_matches '--terminal term_supervisor' "$state_dir/sends.log")" -eq 0 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS pre-handover coordinator status -> zero wake under current coordinator (non-retroactive)\n'
}

run_super_handover_case() {
  local state_dir
  state_dir=$(new_state)
  printf 'term_super_coord\nterm_new_coord\n' > "$state_dir/coordinator-handle-seq"
  printf 'pane_super_coord\npane_new_coord\n' > "$state_dir/coordinator-pane-seq"
  # 위 run_fifo_case 와 같은 이유로 Delivery 2주기가 필요한 시험이라 창을 넓힌다.
  run_companion clean "$state_dir" super_handover "$COMPANION" "$state_dir/routing-ledger.jsonl" 'old and new coordinator deliveries acknowledged' '[ "$(count_matches . "$state_dir/acks.log")" -ge 2 ]'
  [ "$(read_log_flat "$state_dir/acks.log")" = 'delivery_super_handover_1 delivery_super_handover_2 ' ]
  [ "$(count_matches 'SIGNAL super_directive sender=term_super_coord message=sd_handover_1' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'SIGNAL super_directive sender=term_new_coord message=sd_new_1' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'sd_old_replay' "$state_dir/sends.log")" -eq 0 ]
  printf 'PASS coordinator handover: old replay non-retroactive, new coordinator auto-adapted\n'
}

run_super_directive_enter_failure_case() {
  local state_dir replay_json
  state_dir=$(new_state)
  export FAKE_ENTER_MODE=fail
  run_companion clean "$state_dir" super_directive
  [ ! -f "$state_dir/acks.log" ]
  [ "$(count_matches 'WAKE_FAIL term_supervisor' "$state_dir/output.log")" -gt 0 ]
  replay_json=$(FAKE_ORCA_STATE_DIR="$state_dir" FAKE_DELIVERY_MODE=super_directive "$FIXTURE" orchestration check --run run_project --json)
  python3 -c 'import json,sys; assert json.load(sys.stdin)["result"]["deliveryId"] == "delivery_super_dir"' <<< "$replay_json"
  export FAKE_ENTER_MODE=ok
  printf 'PASS super directive Enter failure -> no ack and same Delivery replays\n'
}

# 재사용된 coordinator handle 이라도 안정 pane 신분이 없으면 지시 권위가 없다.
run_reused_handle_missing_pane_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_SUPER_COORDINATOR_HANDLE=term_worker
  run_companion clean "$state_dir" ordinary_status
  [ "$(read_log "$state_dir/acks.log")" = delivery_ordinary_status ]
  [ "$(count_matches '--terminal term_supervisor' "$state_dir/sends.log")" -eq 0 ]
  unset FAKE_SUPER_COORDINATOR_HANDLE
  printf 'PASS reused coordinator handle without stable pane -> zero wake, normal ack\n'
}

# 메시지에 pane 이 아예 없는 슈퍼 handle 발신도 wake 0 이다.
run_super_directive_missing_pane_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" super_directive_no_pane
  [ "$(read_log "$state_dir/acks.log")" = delivery_super_dir_no_pane ]
  [ "$(count_matches '--terminal term_supervisor' "$state_dir/sends.log")" -eq 0 ]
  printf 'PASS super handle without sender_pane_key -> zero wake, normal ack\n'
}

# handle 은 맞지만 다른 창 pane 에서 온 지시도 wake 0 이다.
run_super_directive_wrong_pane_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" super_directive_wrong_pane
  [ "$(read_log "$state_dir/acks.log")" = delivery_super_dir_wrong_pane ]
  [ "$(count_matches '--terminal term_supervisor' "$state_dir/sends.log")" -eq 0 ]
  printf 'PASS super handle with wrong coordinator pane -> zero wake, normal ack\n'
}

# run-show 가 요청한 --super-run 과 다른 Run 을 돌려주면 그 응답은 권위가 아니다.
run_super_directive_wrong_run_id_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_SUPER_RUN_SHOW_ID=run_other
  run_companion clean "$state_dir" super_directive
  [ "$(read_log "$state_dir/acks.log")" = delivery_super_dir ]
  [ "$(count_matches '--terminal term_supervisor' "$state_dir/sends.log")" -eq 0 ]
  unset FAKE_SUPER_RUN_SHOW_ID
  printf 'PASS run-show returning a different run.id -> zero wake, normal ack\n'
}

# run-show 응답에 pane 이 없으면 안정된 창 신분이 없으므로 wake 0 이다.
run_super_directive_runshow_missing_pane_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_SUPER_COORDINATOR_PANE=""
  run_companion clean "$state_dir" super_directive
  [ "$(read_log "$state_dir/acks.log")" = delivery_super_dir ]
  [ "$(count_matches '--terminal term_supervisor' "$state_dir/sends.log")" -eq 0 ]
  unset FAKE_SUPER_COORDINATOR_PANE
  printf 'PASS run-show without coordinator pane -> zero wake, normal ack\n'
}

# Track G NUDGE/MISSING_RELAY 관찰과 권위 super 지시가 한 Delivery 에 섞여 와도
# 메시지 순서대로 각각 1회씩 wake 하고 Delivery 는 정확히 1회 ack 한다.
run_state_super_mix_case() {
  local state_dir order
  state_dir=$(new_state)
  run_companion start_missing_relay "$state_dir" state_super_mix
  [ "$(read_log "$state_dir/acks.log")" = delivery_state_super_mix ]
  [ "$(count_matches '--terminal term_supervisor --text' "$state_dir/sends.log")" -eq 3 ]
  [ "$(count_matches '--terminal term_supervisor --enter' "$state_dir/sends.log")" -eq 3 ]
  [ "$(count_matches 'NUDGE fingerprint=mix_nudge_fp' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'SIGNAL super_directive sender=term_super_coord message=mix_super_dir' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'MISSING_RELAY fingerprint=mix_start_fp' "$state_dir/sends.log")" -eq 1 ]
  order=$(rg -o -N -- 'NUDGE fingerprint=mix_nudge_fp|SIGNAL super_directive sender=term_super_coord|MISSING_RELAY fingerprint=mix_start_fp' "$state_dir/sends.log" | tr '\n' '|')
  [ "$order" = 'NUDGE fingerprint=mix_nudge_fp|SIGNAL super_directive sender=term_super_coord|MISSING_RELAY fingerprint=mix_start_fp|' ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS mixed NUDGE + super directive + MISSING_RELAY Delivery -> FIFO order, three wakes, one ack\n'
}

# 섞인 Delivery 에서도 Enter 실패는 fail-closed 다. ack 없이 같은 Delivery 가 재생된다.
run_state_super_mix_enter_failure_case() {
  local state_dir replay_json
  state_dir=$(new_state)
  export FAKE_ENTER_MODE=fail
  run_companion start_missing_relay "$state_dir" state_super_mix
  [ ! -f "$state_dir/acks.log" ]
  [ "$(count_matches 'WAKE_FAIL term_supervisor' "$state_dir/output.log")" -gt 0 ]
  replay_json=$(FAKE_ORCA_STATE_DIR="$state_dir" FAKE_RELAY_ALERT_MODE=start_missing_relay FAKE_DELIVERY_MODE=state_super_mix "$FIXTURE" orchestration check --run run_project --json)
  python3 -c 'import json,sys; assert json.load(sys.stdin)["result"]["deliveryId"] == "delivery_state_super_mix"' <<< "$replay_json"
  export FAKE_ENTER_MODE=ok
  printf 'PASS mixed Delivery Enter failure -> no ack and same Delivery replays\n'
}

TEST_FILE="$SCRIPT_DIR/test-conductor-companion.sh"
run_gate_companion() {
  local gate_mode="$1" gate_letters="${2:-none}" state_dir="$3" script="${4:-$COMPANION}"
  export FAKE_ORCA_STATE_DIR="$state_dir"
  export FAKE_RELAY_ALERT_MODE=clean
  export FAKE_DELIVERY_MODE=none
  export FAKE_GATE_MODE="$gate_mode"
  export FAKE_GATE_LETTERS="$gate_letters"
  export ORCA_BIN="$FIXTURE"
  export RELAY_LOG_FILE="$state_dir/relay.log"
  export ROUTING_LEDGER_FILE="$state_dir/routing-ledger.jsonl"
  local expected="${5:-one complete gate patrol}" condition="${6:-[ \"\$(count_matches 'orchestration check --run run_project --json' \"$state_dir/calls.log\")\" -ge 2 ]}"
  require_runnable "$script" "$expected"
  WATCH_DEADLINE_SEC="$TEST_WAIT_CEILING_SEC" "$script" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$state_dir/output.log" 2>&1 &
  local pid=$!
  wait_for_test_condition "$pid" "$state_dir" "$expected" "$condition"
}
gate_wake_count() {
  count_matches 'GATE_NUDGE gate=' "$1/sends.log"
}
# pending 1 + 대응 편지 0 => wake 1. 같은 스냅샷 반복 => 추가 wake 0 (gateId dedup).
#
# F-B7(2026-08-09): "같은 스냅샷 반복"을 보려면 루프가 **최소 2주기** 돌아야 한다
# (`GATE_NUDGE_DUPLICATE` 는 두 번째 주기에만 찍힌다). 창이 1초면 부하가 높을 때
# 1주기만 돌고 그 줄이 안 찍혀 떨어진다(실측: 부하 11.78 에서 재현).
# 주기 수에 의존하는 시험만 창을 넓힌다 — run_fifo_case 등과 같은 처방.
run_gate_nudge_basic_case() {
  local state_dir
  state_dir=$(new_state)
  run_gate_companion pending_one none "$state_dir" "$COMPANION" 'duplicate gate observation' '[ "$(count_matches "GATE_NUDGE_DUPLICATE gate=gate_p1" "$state_dir/output.log")" -ge 1 ]'
  [ "$(count_matches 'GATE_NUDGE gate=gate_p1' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches '--terminal term_supervisor --text' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches '--terminal term_supervisor --enter' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'gate_nudge gate=gate_p1' "$state_dir/relay.log")" -eq 1 ]
  [ "$(count_matches 'GATE_NUDGE_DUPLICATE gate=gate_p1' "$state_dir/output.log")" -ge 1 ]
  printf 'PASS gate nudge: pending 1 + 0 letters -> 1 wake, repeat snapshot -> 0 extra (gateId dedup)\n'
}
# pending 1 + 정확한 대응 편지 1 => wake 0.
run_gate_covered_case() {
  local state_dir
  state_dir=$(new_state)
  run_gate_companion pending_one matched_one "$state_dir"
  [ "$(gate_wake_count "$state_dir")" -eq 0 ]
  [ "$(count_matches '--terminal term_supervisor' "$state_dir/sends.log")" -eq 0 ]
  printf 'PASS gate nudge: pending 1 + exact 1 letter -> 0 wake\n'
}
# pending 0 => wake 0.
run_gate_none_case() {
  local state_dir
  state_dir=$(new_state)
  run_gate_companion empty none "$state_dir"
  [ "$(gate_wake_count "$state_dir")" -eq 0 ]
  printf 'PASS gate nudge: pending 0 -> 0 wake\n'
}
# 다른 gate/task/run 의 편지만 존재 => wake 1.
run_gate_other_letter_case() {
  local letters="$1" state_dir
  state_dir=$(new_state)
  run_gate_companion pending_one "$letters" "$state_dir"
  [ "$(count_matches 'GATE_NUDGE gate=gate_p1' "$state_dir/sends.log")" -eq 1 ]
  printf 'PASS gate nudge: only other %s letters -> wake 1\n' "$letters"
}
# gateId 없는 편지는 어떤 관문도 커버하지 않는다 => wake 1.
run_gate_no_gateid_letter_case() {
  local state_dir
  state_dir=$(new_state)
  run_gate_companion pending_one no_gateid "$state_dir"
  [ "$(count_matches 'GATE_NUDGE gate=gate_p1' "$state_dir/sends.log")" -eq 1 ]
  printf 'PASS gate nudge: letter without gateId does not cover -> wake 1\n'
}
# 대응 후보 2개 => 모호 => fail-closed wake 0.
run_gate_ambiguous_case() {
  local state_dir
  state_dir=$(new_state)
  run_gate_companion pending_one matched_two "$state_dir"
  [ "$(gate_wake_count "$state_dir")" -eq 0 ]
  [ "$(count_matches 'gate_nudge_ambiguous gate=gate_p1' "$state_dir/relay.log")" -ge 1 ]
  printf 'PASS gate nudge: 2 matching letters -> ambiguous -> 0 wake\n'
}
# gate-list 실패 / inbox 실패 / run-show 실패 / malformed => 모두 fail-closed wake 0.
run_gate_fail_closed_case() {
  local label="$1" gm="$2" gl="$3" extra_env="$4" reason="$5" state_dir
  state_dir=$(new_state)
  if [ "$extra_env" = "runshow_fail" ]; then export FAKE_RUN_SHOW_FAIL=1; fi
  run_gate_companion "$gm" "$gl" "$state_dir"
  unset FAKE_RUN_SHOW_FAIL
  [ "$(gate_wake_count "$state_dir")" -eq 0 ]
  [ "$(count_matches "$reason" "$state_dir/relay.log")" -ge 1 ]
  printf 'PASS gate nudge fail-closed %s -> 0 wake\n' "$label"
}
# text 성공 후 Enter 실패 => 성공 처리하지만 중복키 기록 금지, 다음 순찰 재시도.
#
# F-B7(2026-08-09): 이 시험은 "다음 순찰에서 다시 시도"를 보므로 루프가 **최소 2주기**
# 돌아야 한다. 그런데 창이 1초로 좁아서, 부하가 높으면 1주기만 돌고 `GATE_NUDGE` 가
# 1번만 찍혀 떨어졌다(실측: 부하 21.59 에서 재현). 형제 시험들(run_fifo_case 등)이 같은
# 이유로 이미 창을 넓혀 둔 것과 같은 부류다 — 주기 수에 의존하는 시험만 창을 넓힌다.
run_gate_enter_fail_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_ENTER_MODE=fail
  run_gate_companion pending_one none "$state_dir" "$COMPANION" 'gate wake retried after Enter failure' '[ "$(count_matches "GATE_NUDGE gate=gate_p1" "$state_dir/sends.log")" -ge 2 ]'
  export FAKE_ENTER_MODE=ok
  [ "$(count_matches 'GATE_NUDGE_ENTER_FAIL gate=gate_p1' "$state_dir/output.log")" -ge 1 ]
  [ "$(count_matches 'GATE_NUDGE gate=gate_p1' "$state_dir/sends.log")" -ge 2 ]
  [ "$(count_matches 'wake=1' "$state_dir/relay.log")" -eq 0 ]
  printf 'PASS gate nudge: text ok + enter fail -> no dedup key, retry next patrol\n'
}
# 구조화 신분이 어긋난 편지(다른 발신 쌍, pane 없음, 다른 수신 주소, 다른 판/작업 신분,
# 필수 판 신분 필드 누락)는 대응 편지로 세지 않는다. roster 스냅샷은 명확하므로 공식
# 편지 부재로 간주해 wake 1 한다(roster 자체가 모호한 경우 wake 0 과 구분된다).
run_gate_identity_mismatch_case() {
  local label="$1" letters="$2" state_dir
  state_dir=$(new_state)
  run_gate_companion pending_one "$letters" "$state_dir"
  [ "$(count_matches 'GATE_NUDGE gate=gate_p1' "$state_dir/sends.log")" -eq 1 ]
  printf 'PASS gate nudge: %s letter does not cover -> clear roster, wake 1\n' "$label"
}
# 세션 교대 전 정상 발송 편지: 발신 (pane, handle)이 roster retired 행의
# pane+lastSeenHandle 쌍과 정확히 맞으면 새 감독 인수 뒤에도 대응 편지로 인정한다 => wake 0.
run_gate_retired_pane_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_SUPERVISOR_RETIRED_PANE=pane_old_supervisor
  run_gate_companion pending_one retired_pane "$state_dir"
  unset FAKE_SUPERVISOR_RETIRED_PANE
  [ "$(gate_wake_count "$state_dir")" -eq 0 ]
  printf 'PASS gate nudge: pre-handover letter with exact retired pane+lastSeenHandle pair -> covered, 0 wake\n'
}
# roster 응답 권위 회귀 (B): resolve 는 정상이되 supervisor roster list 응답만 특정
# 방식으로 깨뜨리면(ok=false, 빈 active, 복수 active, 잘못된 status/lifecycle/live,
# resolve 와 불일치, 불명확 이력) 신분이 모호해 편지 부재를 확정할 수 없다 => wake 0.
run_gate_roster_fail_case() {
  local label="$1" env_name="$2" env_value="$3" state_dir
  state_dir=$(new_state)
  export "$env_name=$env_value"
  run_gate_companion pending_one none "$state_dir"
  unset "$env_name"
  [ "$(gate_wake_count "$state_dir")" -eq 0 ]
  [ "$(count_matches 'gate_nudge_suppressed reason=roster_history_failed' "$state_dir/relay.log")" -ge 1 ]
  printf 'PASS gate nudge roster fail-closed %s -> 0 wake\n' "$label"
}
# retired 행에 권위 핸들 이력(lastSeenHandle)이 없으면 불명확한 이력이다. 모양이
# 불명확한 이력을 버리고 계속 판단하지 말고 전체 wake 0 이어야 한다(B7).
run_gate_roster_retired_bad_history_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_SUPERVISOR_RETIRED_PANE=pane_old_supervisor
  export FAKE_ROSTER_LIST_RETIRED_BAD=1
  run_gate_companion pending_one none "$state_dir"
  unset FAKE_SUPERVISOR_RETIRED_PANE FAKE_ROSTER_LIST_RETIRED_BAD
  [ "$(gate_wake_count "$state_dir")" -eq 0 ]
  [ "$(count_matches 'gate_nudge_suppressed reason=roster_history_failed' "$state_dir/relay.log")" -ge 1 ]
  printf 'PASS gate nudge roster fail-closed retired-missing-lastSeenHandle -> 0 wake\n'
}
# 세션 교대 전 편지라도 retired 행의 pane+lastSeenHandle 쌍이 아니면(같은 pane 의 다른
# handle) 대응 편지가 아니다 => 공식 편지 부재로 wake 1 (C10).
run_gate_retired_wrong_handle_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_SUPERVISOR_RETIRED_PANE=pane_old_supervisor
  run_gate_companion pending_one retired_wrong_handle "$state_dir"
  unset FAKE_SUPERVISOR_RETIRED_PANE
  [ "$(count_matches 'GATE_NUDGE gate=gate_p1' "$state_dir/sends.log")" -eq 1 ]
  printf 'PASS gate nudge: retired pane + wrong handle letter does not cover -> wake 1\n'
}
# 정상 편지 1 + 신분 불량 편지 1 => 유효 1개로 covered (불량 편지는 모호함 근거가 아님) => wake 0.
run_gate_one_valid_one_invalid_case() {
  local state_dir
  state_dir=$(new_state)
  run_gate_companion pending_one matched_one_plus_invalid "$state_dir"
  [ "$(gate_wake_count "$state_dir")" -eq 0 ]
  printf 'PASS gate nudge: 1 valid + 1 invalid letter -> covered, 0 wake\n'
}
# inbox가 전용 한도만큼 포화(count >= limit)면 편지 부재를 확정할 수 없다 => wake 0.
run_gate_inbox_saturated_case() {
  local state_dir
  state_dir=$(new_state)
  export GATE_NUDGE_INBOX_LIMIT=1
  run_gate_companion pending_one other_gate "$state_dir"
  unset GATE_NUDGE_INBOX_LIMIT
  [ "$(gate_wake_count "$state_dir")" -eq 0 ]
  [ "$(count_matches 'gate_nudge_suppressed reason=inbox_saturated' "$state_dir/relay.log")" -ge 1 ]
  printf 'PASS gate nudge: inbox saturated (count >= limit) -> cannot prove absence -> 0 wake\n'
}
# B6 포화 실명 제거. 같은 순간에 전역 창은 한도에 닿지만 슈퍼 Run 자기 주소로 좁힌
# 창에는 대응 편지가 그대로 보인다 => 커버 판정 + wake 0 + inbox_saturated 없음.
assert_scoped_inbox_contract() {
  local state_dir="$1"
  [ "$(gate_wake_count "$state_dir")" -eq 0 ] || return 1
  [ "$(count_matches 'gate_nudge_suppressed reason=inbox_saturated' "$state_dir/relay.log")" -eq 0 ] || return 1
  [ "$(count_matches '--terminal run:run_super' "$state_dir/calls.log")" -ge 1 ] || return 1
}
run_gate_scoped_inbox_case() {
  local state_dir
  state_dir=$(new_state)
  export GATE_NUDGE_INBOX_LIMIT=2
  run_gate_companion pending_one scoped_window "$state_dir"
  unset GATE_NUDGE_INBOX_LIMIT
  assert_scoped_inbox_contract "$state_dir"
  printf 'PASS gate nudge: 자기 Run 으로 좁힌 조회 -> 닫힌 판 편지가 창을 먹어도 포화 실명 없음\n'
}
# 거부 증거 4: B6 이전 실제 구현(전역 조회)에 같은 검사를 걸면 포화 실명이 그대로 나온다.
run_gate_scoped_inbox_rejection_case() {
  local state_dir
  setup_prefix_companion >/dev/null
  state_dir=$(new_state)
  export GATE_NUDGE_INBOX_LIMIT=2
  run_gate_companion pending_one scoped_window "$state_dir" "$PREFIX_COMPANION"
  unset GATE_NUDGE_INBOX_LIMIT
  if assert_scoped_inbox_contract "$state_dir" >/dev/null 2>&1; then
    printf 'REJECTION_EVIDENCE_MISSING contract=assert_scoped_inbox_contract (B6 이전 구현이 통과했다)\n' >&2
    return 1
  fi
  [ "$(count_matches 'gate_nudge_suppressed reason=inbox_saturated' "$state_dir/relay.log")" -ge 1 ]
  printf 'PASS rejection evidence: B6 이전 전역 조회 구현은 포화 실명 검사에서 실제로 떨어진다\n'
}
# 여러 pending gate 는 각 gate별 정확히 1회.
run_gate_multi_case() {
  local state_dir
  state_dir=$(new_state)
  run_gate_companion pending_two none "$state_dir"
  [ "$(count_matches 'GATE_NUDGE gate=gate_p1' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'GATE_NUDGE gate=gate_p2' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'gate_nudge gate=gate_p1' "$state_dir/relay.log")" -eq 1 ]
  [ "$(count_matches 'gate_nudge gate=gate_p2' "$state_dir/relay.log")" -eq 1 ]
  printf 'PASS gate nudge: multiple pending gates -> each nudged exactly once\n'
}
# 여러 pending gate 가 모두 커버 => 0 wake.
run_gate_multi_covered_case() {
  local state_dir
  state_dir=$(new_state)
  run_gate_companion pending_two two_gates_matched "$state_dir"
  [ "$(gate_wake_count "$state_dir")" -eq 0 ]
  printf 'PASS gate nudge: multiple pending gates all covered -> 0 wake\n'
}
run_candidate_absent_case
run_candidate_present_case candidate_present
run_candidate_present_case candidate_ask
run_candidate_present_case candidate_escalation
run_candidate_present_case candidate_internal
run_candidate_context_case candidate_missing_id
run_candidate_context_case candidate_ambiguous
run_duplicate_cursor_case
run_candidate_absent_case
run_candidate_absent_case candidate_waiting
run_fifo_case
run_lifecycle_message_identity_case
run_malformed_case
run_head_of_line_case
run_lifecycle_cross_type_case
run_malformed_id_suite
run_malformed_id_two_good_case
run_malformed_id_four_good_case
run_malformed_id_secret_case
run_ack_retry_dedup_case
run_shape_report_echo_case
run_shape_report_echo_replay_case
run_shape_report_send_retry_case
run_shape_report_send_exhausted_case
run_shape_alert_provenance_suite
run_shape_report_no_emergency_when_ok_case
run_shape_report_emergency_replay_case
run_shape_emergency_wake_failure_case
run_shape_emergency_recovery_case
run_super_escalation_case
run_super_escalation_ask_case
run_super_escalation_duplicate_case
run_super_impostor_suite
run_candidate_scan_scoped_case
run_prefix_rejection_suite
run_enter_failure_case
run_wake_failure_bounded_case
run_super_reply_once_case
run_super_reply_duplicate_case
run_super_reply_enter_failure_case
run_ordinary_status_case
run_super_directive_once_case
run_super_directive_duplicate_case
run_reused_handle_missing_pane_case
run_super_directive_missing_pane_case
run_super_directive_wrong_pane_case
run_super_directive_wrong_run_id_case
run_super_directive_runshow_missing_pane_case
run_state_super_mix_case
run_state_super_mix_enter_failure_case
run_same_board_status_ids_case
run_pre_handover_status_case
run_super_handover_case
run_super_directive_enter_failure_case
run_consumer_fenced_case
run_owner_mismatch_case
run_worker_done_ledger_case
run_worker_done_reviewer_case
run_worker_done_reviewer_variant_case
run_worker_done_ambiguous_case
run_worker_done_assignee_mismatch_case
run_worker_done_dispatch_failed_case
run_worker_done_role_unknown_case
run_worker_done_bad_row_case
run_worker_done_missing_envelope_case
run_worker_done_row_missing_run_case
run_worker_done_wrong_board_case
run_worker_done_deps_array_object_case
run_worker_done_deps_bad_json_case
run_worker_done_count_mismatch_case
run_worker_done_twin_candidates_case
run_worker_done_roster_runid_alias_case
run_worker_done_roster_handle_alias_case
run_worker_done_roster_live_string_case
run_worker_done_tl_runid_alias_case
run_worker_done_tl_row_runid_alias_case
run_worker_done_tl_status_active_case
run_worker_done_tl_status_done_case
run_worker_done_tl_pending_blocked_mix_case
run_worker_done_ds_camelcase_case
run_worker_done_ds_status_done_case
run_worker_done_dev_variant_case
run_worker_done_researcher_variant_case
run_portable_orca_case
run_kicker_case
run_relay_bounded_fixture_case
run_no_mutation_gate_case
run_gate_nudge_basic_case
run_gate_covered_case
run_gate_none_case
run_gate_other_letter_case other_gate
run_gate_other_letter_case other_run
run_gate_no_gateid_letter_case
run_gate_ambiguous_case
run_gate_fail_closed_case "gate-list-failed" fail none "" 'gate_nudge_suppressed reason=gate_list_failed'
run_gate_fail_closed_case "inbox-failed" pending_one inbox_fail "" 'gate_nudge_suppressed reason=inbox_failed'
run_gate_fail_closed_case "run-show-failed" pending_one none runshow_fail 'gate_nudge_suppressed reason=super_run_unverified'
run_gate_fail_closed_case "malformed" malformed none "" 'gate_nudge_suppressed reason=gate_unknown'
run_gate_fail_closed_case "gate-ok-false" ok_false none "" 'gate_nudge_suppressed reason=gate_untrusted'
run_gate_fail_closed_case "gate-wrong-run" wrong_run none "" 'gate_nudge_suppressed reason=gate_untrusted'
run_gate_fail_closed_case "gate-mixed-malformed" mixed_malformed none "" 'gate_nudge_suppressed reason=gate_unknown'
run_gate_fail_closed_case "gate-duplicate" duplicate none "" 'gate_nudge_suppressed reason=gate_duplicate'
run_gate_fail_closed_case "inbox-ok-false" pending_one inbox_ok_false "" 'gate_nudge_suppressed reason=inbox_untrusted'
run_gate_fail_closed_case "inbox-mixed-malformed" pending_one inbox_mixed_malformed "" 'gate_nudge_suppressed reason=inbox_unknown'
run_gate_fail_closed_case "gate-count-missing" count_missing none "" 'gate_nudge_suppressed reason=gate_unknown'
run_gate_fail_closed_case "gate-count-mismatch" count_mismatch none "" 'gate_nudge_suppressed reason=gate_unknown'
run_gate_fail_closed_case "gate-count-negative" count_negative none "" 'gate_nudge_suppressed reason=gate_unknown'
run_gate_fail_closed_case "gate-count-bool" count_bool none "" 'gate_nudge_suppressed reason=gate_unknown'
run_gate_fail_closed_case "gate-row-task-missing" task_missing none "" 'gate_nudge_suppressed reason=gate_unknown'
run_gate_fail_closed_case "gate-row-status-wrong" status_wrong none "" 'gate_nudge_suppressed reason=gate_unknown'
run_gate_fail_closed_case "inbox-count-missing" pending_one inbox_count_missing "" 'gate_nudge_suppressed reason=inbox_unknown'
run_gate_fail_closed_case "inbox-count-mismatch" pending_one inbox_count_mismatch "" 'gate_nudge_suppressed reason=inbox_unknown'
run_gate_fail_closed_case "inbox-count-negative" pending_one inbox_count_negative "" 'gate_nudge_suppressed reason=inbox_unknown'
run_gate_fail_closed_case "inbox-count-bool" pending_one inbox_count_bool "" 'gate_nudge_suppressed reason=inbox_unknown'
run_gate_fail_closed_case "inbox-row-missing-id" pending_one inbox_row_missing_id "" 'gate_nudge_suppressed reason=inbox_unknown'
run_gate_fail_closed_case "inbox-row-missing-run" pending_one inbox_row_missing_run "" 'gate_nudge_suppressed reason=inbox_unknown'
run_gate_fail_closed_case "inbox-row-missing-type" pending_one inbox_row_missing_type "" 'gate_nudge_suppressed reason=inbox_unknown'
run_gate_roster_fail_case "ok-false" FAKE_ROSTER_LIST_OK_FALSE 1
run_gate_roster_fail_case "empty-active" FAKE_ROSTER_LIST_EMPTY_ACTIVE 1
run_gate_roster_fail_case "multiple-active" FAKE_ROSTER_MULTIPLE_ROLE project-supervisor
run_gate_roster_fail_case "wrong-status" FAKE_ROSTER_LIST_BAD_FIELD status
run_gate_roster_fail_case "wrong-lifecycle" FAKE_ROSTER_LIST_BAD_FIELD lifecycle
run_gate_roster_fail_case "wrong-live" FAKE_ROSTER_LIST_BAD_FIELD live
run_gate_roster_fail_case "resolve-pair-handle-mismatch" FAKE_ROSTER_LIST_BAD_FIELD handle
run_gate_roster_fail_case "resolve-pair-pane-mismatch" FAKE_ROSTER_LIST_BAD_FIELD pane
run_gate_roster_fail_case "malformed-history" FAKE_ROSTER_LIST_MALFORMED 1
run_gate_roster_retired_bad_history_case
run_gate_identity_mismatch_case "wrong sender pair" wrong_sender
run_gate_identity_mismatch_case "missing sender pane" missing_sender_pane
run_gate_identity_mismatch_case "same pane wrong handle" same_pane_wrong_handle
run_gate_identity_mismatch_case "same handle wrong pane" same_handle_wrong_pane
run_gate_identity_mismatch_case "wrong recipient" wrong_recipient
run_gate_identity_mismatch_case "wrong payload project" wrong_project
run_gate_identity_mismatch_case "wrong payload board" wrong_board
run_gate_identity_mismatch_case "wrong payload sourceTaskId" wrong_source_task
run_gate_identity_mismatch_case "missing payload project" missing_project
run_gate_identity_mismatch_case "missing payload board" missing_board
run_gate_identity_mismatch_case "missing payload sourceTaskId" missing_source_task
run_gate_retired_pane_case
run_gate_retired_wrong_handle_case
run_gate_one_valid_one_invalid_case
run_gate_inbox_saturated_case
run_gate_scoped_inbox_case
run_gate_scoped_inbox_rejection_case
run_gate_enter_fail_case
run_gate_multi_case
run_gate_multi_covered_case
unset FAKE_GATE_MODE FAKE_GATE_LETTERS FAKE_RUN_SHOW_FAIL
printf 'PASS mailbox-centered relay-misrouted focused suite; no companion screen reads; A1-A4 covered; A5 warning-only observations; A6/A7 non-blocking\n'
