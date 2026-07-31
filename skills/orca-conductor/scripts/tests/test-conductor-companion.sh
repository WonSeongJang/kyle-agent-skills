#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
STATE_DIR=$(mktemp -d /tmp/orca-companion-test.XXXXXX)
export FAKE_ORCA_STATE_DIR="$STATE_DIR"
export PATH="$SCRIPT_DIR/fixtures:$PATH"
export COMPANION_POLL_INTERVAL_SEC=0.1
export COMPANION_WAKE_TERMINAL_HANDLE=term_supervisor
export WATCH_DEADLINE_SEC=2

set +e
"$SKILL_DIR/scripts/conductor-companion.sh" term_supervisor term_relay 999 > "$STATE_DIR/output.log" 2>&1
status=$?
set -e

[ "$status" -eq 1 ]
[ "$(cat "$STATE_DIR/status-count" 2>/dev/null || echo 0)" -gt 0 ]
[ "$(wc -l < "$STATE_DIR/sends.log")" -eq 2 ]
[ "$(rg -c 'SIGNAL worker_done term_worker' "$STATE_DIR/sends.log")" -eq 1 ]
! rg -q 'term_relay.*mirrored done|SIGNAL worker_done term_relay' "$STATE_DIR/sends.log"
printf 'PASS companion drains status and wakes once per direct dispatch\n'
printf 'artifacts preserved: %s\n' "$STATE_DIR"
