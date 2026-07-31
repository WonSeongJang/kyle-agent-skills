#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
export PATH="$SCRIPT_DIR/fixtures:$PATH"
export COMPANION_POLL_INTERVAL_SEC=0.1
export COMPANION_WAKE_TERMINAL_HANDLE=term_supervisor
export WATCH_DEADLINE_SEC=2

run_case() {
  local mode="$1"
  local expected="$2"
  local state_dir
  local status
  state_dir=$(mktemp -d /tmp/orca-companion-test.XXXXXX)
  export FAKE_ORCA_STATE_DIR="$state_dir"
  export FAKE_RELAY_ALERT_MODE="$mode"
  export FAKE_WORKER_ALERT_MODE=none

  set +e
  "$SKILL_DIR/scripts/conductor-companion.sh" term_supervisor term_relay 999 > "$state_dir/output.log" 2>&1
  status=$?
  set -e

  [ "$status" -eq 1 ]
  [ "$(cat "$state_dir/status-count" 2>/dev/null || echo 0)" -gt 0 ]
  [ "$(wc -l < "$state_dir/sends.log")" -eq 4 ]
  [ "$(rg -c 'SIGNAL worker_done term_worker' "$state_dir/sends.log")" -eq 1 ]
  [ "$(rg -c "$expected" "$state_dir/sends.log")" -eq 1 ]
  ! rg -q 'term_relay.*mirrored done|SIGNAL worker_done term_relay' "$state_dir/sends.log"
  printf 'PASS companion wakes once for %s relay alert\n' "$mode"
  printf 'artifacts preserved: %s\n' "$state_dir"
}

run_case structured 'LEGACY_READ_ONLY term_relay.*task=task_legacy'
run_case raw 'LEGACY_READ_ONLY term_relay.*기존 중계기 출력'

run_worker_case() {
  local mode="$1"
  local expected_count="$2"
  local state_dir
  local status
  state_dir=$(mktemp -d /tmp/orca-companion-worker-test.XXXXXX)
  export FAKE_ORCA_STATE_DIR="$state_dir"
  export FAKE_RELAY_ALERT_MODE=clean
  export FAKE_WORKER_ALERT_MODE="$mode"

  set +e
  "$SKILL_DIR/scripts/conductor-companion.sh" term_supervisor term_relay 999 > "$state_dir/output.log" 2>&1
  status=$?
  set -e

  [ "$status" -eq 1 ]
  [ "$(rg -c 'WORKER_LEGACY_READ_ONLY' "$state_dir/sends.log")" -eq "$expected_count" ]
  [ "$(rg -c 'WORKER_LEGACY_READ_ONLY task=task_worker_1 dispatch=ctx_worker_1' "$state_dir/sends.log")" -eq 1 ]
  if [ "$expected_count" -eq 2 ]; then
    [ "$(rg -c 'WORKER_LEGACY_READ_ONLY task=task_worker_2 dispatch=ctx_worker_2' "$state_dir/sends.log")" -eq 1 ]
  fi
  printf 'PASS companion wakes once for %s worker legacy alerts\n' "$expected_count"
  printf 'artifacts preserved: %s\n' "$state_dir"
}

run_worker_case single 1
run_worker_case two 2

run_explicit_orca_bin_case() {
  local state_dir
  local status
  state_dir=$(mktemp -d /tmp/orca-companion-bin-test.XXXXXX)
  export FAKE_ORCA_STATE_DIR="$state_dir"
  export FAKE_RELAY_ALERT_MODE=structured
  export FAKE_WORKER_ALERT_MODE=none

  set +e
  PATH=/usr/bin:/bin ORCA_BIN="$SCRIPT_DIR/fixtures/orca" \
    "$SKILL_DIR/scripts/conductor-companion.sh" term_supervisor term_relay 999 > "$state_dir/output.log" 2>&1
  status=$?
  set -e

  [ "$status" -eq 1 ]
  [ "$(rg -c 'task=task_legacy' "$state_dir/sends.log")" -eq 1 ]
  printf 'PASS companion uses explicit ORCA_BIN with launchd-like PATH\n'
  printf 'artifacts preserved: %s\n' "$state_dir"
}

run_explicit_orca_bin_case

run_hup_survival_case() {
  local state_dir
  local companion_pid
  local status
  state_dir=$(mktemp -d /tmp/orca-companion-hup-test.XXXXXX)
  export FAKE_ORCA_STATE_DIR="$state_dir"
  export FAKE_RELAY_ALERT_MODE=clean
  export FAKE_WORKER_ALERT_MODE=none
  export WATCH_DEADLINE_SEC=30

  "$SKILL_DIR/scripts/conductor-companion.sh" term_supervisor term_relay 999 > "$state_dir/output.log" 2>&1 &
  companion_pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$state_dir/status-count" ] && break
    sleep 0.1
  done
  kill -HUP "$companion_pid"
  sleep 0.2
  kill -0 "$companion_pid"
  kill -TERM "$companion_pid"
  set +e
  wait "$companion_pid"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  printf 'PASS companion survives HUP and exits cleanly on TERM\n'
  printf 'artifacts preserved: %s\n' "$state_dir"
}

run_hup_survival_case
