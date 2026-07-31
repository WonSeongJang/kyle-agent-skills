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
