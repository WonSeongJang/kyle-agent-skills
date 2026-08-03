#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
COMPANION="$SKILL_DIR/scripts/conductor-companion.sh"
FIXTURE="$SCRIPT_DIR/fixtures/orca"
export COMPANION_POLL_INTERVAL_SEC=0.05
export WATCH_DEADLINE_SEC=1
export PROJECT_LEDGER_SCAN_LIMIT=100
export FAKE_CHECK_FAILURE=""
export FAKE_ENTER_MODE=ok
export ORCA_TERMINAL_HANDLE=term_supervisor

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
assert_no_screen_reads() {
  local state_dir="$1"
  assert_absent 'terminal read' "$state_dir/calls.log"
  assert_absent 'terminal read' "$COMPANION"
}
run_companion() {
  local mode="$1" state_dir="$2" delivery_mode="${3:-none}" script="${4:-$COMPANION}" ledger="${5:-$state_dir/routing-ledger.jsonl}"
  export FAKE_ORCA_STATE_DIR="$state_dir"
  export FAKE_RELAY_ALERT_MODE="$mode"
  export FAKE_DELIVERY_MODE="$delivery_mode"
  export ORCA_BIN="$FIXTURE"
  export RELAY_LOG_FILE="$state_dir/relay.log"
  export ROUTING_LEDGER_FILE="$ledger"
  set +e
  "$script" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project --super-run run_super 999 > "$state_dir/output.log" 2>&1
  run_status=$?
  set -e
  [ "$run_status" -eq 1 ]
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
  [ "$(cat "$state_dir/acks.log")" = delivery_candidate ]
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
  run_companion candidate_duplicate "$state_dir"
  [ "$(count_matches 'misrouted_human_decision:' "$state_dir/project-sends.log")" -eq 1 ]
  [ "$(count_matches '--terminal term_supervisor --text' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'RELAY_CANDIDATE_DUPLICATE task=task_candidate dispatch=ctx_candidate cursor=77 wake=0' "$state_dir/output.log")" -eq 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS duplicate task+dispatch+cursor -> zero duplicate wake\n'
}
run_fifo_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" fifo
  [ "$(tr '\n' ' ' < "$state_dir/acks.log")" = 'delivery_1 delivery_2 ' ]
  [ "$(count_matches '--run run_project --ack delivery_1' "$state_dir/calls.log")" -eq 1 ]
  [ "$(count_matches '--run run_project --ack delivery_2' "$state_dir/calls.log")" -eq 1 ]
  [ "$(count_matches --enter "$state_dir/sends.log")" -eq 2 ]
  [ "$(count_matches 'SIGNAL escalation term_worker task=task_1 dispatch=ctx_1' "$state_dir/sends.log")" -eq 1 ]
  [ "$(count_matches 'SIGNAL decision_gate term_worker task=task_2 dispatch=ctx_2' "$state_dir/sends.log")" -eq 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS FIFO lifecycle delivery and exact text+Enter ack path\n'
}
run_malformed_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" malformed_mix
  [ ! -f "$state_dir/acks.log" ]
  assert_absent '--ack delivery_1' "$state_dir/calls.log"
  [ "$(count_matches 'MALFORMED_LIFECYCLE_REPORT type=escalation' "$state_dir/sends.log")" -eq 1 ]
  assert_no_screen_reads "$state_dir"
  printf 'PASS malformed report stays unacked for Delivery replay\n'
}
run_enter_failure_case() {
  local state_dir
  state_dir=$(new_state)
  export FAKE_ENTER_MODE=fail
  run_companion clean "$state_dir" fifo
  [ ! -f "$state_dir/acks.log" ]
  [ "$(count_matches 'WAKE_FAIL term_supervisor' "$state_dir/output.log")" -gt 0 ]
  export FAKE_ENTER_MODE=ok
  printf 'PASS Enter failure leaves Delivery unacked for replay\n'
}
run_super_reply_once_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" super_reply
  [ "$(cat "$state_dir/acks.log")" = delivery_super_reply ]
  assert_single_wake "$state_dir"
  [ "$(count_matches 'SIGNAL super_reply sender=term_super message=super_reply_1 targetRunId=run_super' "$state_dir/sends.log")" -eq 1 ]
  printf 'PASS superReply status -> one supervisor text+Enter then one ack\n'
}
run_super_reply_duplicate_case() {
  local state_dir
  state_dir=$(new_state)
  run_companion clean "$state_dir" super_reply_duplicate
  [ "$(cat "$state_dir/acks.log")" = delivery_super_reply ]
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
  [ "$(cat "$state_dir/acks.log")" = delivery_ordinary_status ]
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
run_worker_done_ledger_case() {
  local state_dir
  state_dir=$(new_state)
  export ROUTING_BOARD=""
  run_companion clean "$state_dir" worker_done
  [ "$(cat "$state_dir/acks.log")" = delivery_1 ]
  [ "$(count_matches 'worker_done_auto' "$state_dir/routing-ledger.jsonl")" -eq 1 ]
  [ "$(count_matches 'task_w' "$state_dir/routing-ledger.jsonl")" -eq 1 ]
  [ "$(count_matches 'ctx_w' "$state_dir/routing-ledger.jsonl")" -eq 1 ]
  python3 -c 'import json,sys; event=json.loads(open(sys.argv[1]).readline()); assert event["board"] == "board_test"' "$state_dir/routing-ledger.jsonl"
  export ROUTING_BOARD=""
  printf 'PASS A2 worker_done task+dispatch provenance uses explicit board\n'
}
run_portable_orca_case() {
  local state_dir bin_dir auto_status
  state_dir=$(new_state)
  bin_dir=$(mktemp -d /tmp/orca-relay-bin.XXXXXX)
  ln -s "$FIXTURE" "$bin_dir/orca"
  set +e
  env -u ORCA_BIN PATH="$bin_dir:/usr/bin:/bin" ORCA_TERMINAL_HANDLE=term_supervisor FAKE_ORCA_STATE_DIR="$state_dir" FAKE_RELAY_ALERT_MODE=clean FAKE_DELIVERY_MODE=none COMPANION_POLL_INTERVAL_SEC=0.05 WATCH_DEADLINE_SEC=1 RELAY_LOG_FILE="$state_dir/relay.log" ROUTING_LEDGER_FILE="$state_dir/ledger.jsonl" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project 999 > "$state_dir/output.log" 2>&1
  auto_status=$?
  set -e
  [ "$auto_status" -eq 1 ]
  [ -s "$state_dir/roster.log" ]
  printf 'PASS A3 PATH auto-discovery works without machine-specific path\n'
}
run_kicker_case() {
  local state_dir
  state_dir=$(new_state)
  FAKE_ORCA_STATE_DIR="$state_dir" ORCA_BIN="$FIXTURE" FAKE_RELAY_ALERT_MODE=clean FAKE_DELIVERY_MODE=none RELAY_LOG_FILE="$state_dir/relay.log" "$COMPANION" --project project_test --board board_test --supervisor-role project-supervisor --relay-role relay --run run_project 0 > "$state_dir/output.log" 2>&1 || true
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

TEST_FILE="$SCRIPT_DIR/test-conductor-companion.sh"
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
run_malformed_case
run_enter_failure_case
run_super_reply_once_case
run_super_reply_duplicate_case
run_super_reply_enter_failure_case
run_ordinary_status_case
run_consumer_fenced_case
run_owner_mismatch_case
run_worker_done_ledger_case
run_portable_orca_case
run_kicker_case
run_relay_bounded_fixture_case
run_no_mutation_gate_case
printf 'PASS mailbox-centered relay-misrouted focused suite; no companion screen reads; A1-A4 covered; A5 warning-only observations; A6/A7 non-blocking\n'
