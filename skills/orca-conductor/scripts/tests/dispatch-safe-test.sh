#!/bin/bash
# dispatch-safe-test.sh — dispatch-safe.sh 시작 판정 회귀 테스트
#
# 6개 시나리오: polling + accumulation + booting + prompt + timeout + 단독 신호
# mock orca 를 PATH 앞에 넣어 terminal read 가 시나리오별 JSON 을 반환하게 한다.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISPATCH_SAFE="${DISPATCH_SAFE_SCRIPT:-$SCRIPT_DIR/../dispatch-safe.sh}"

PASS=0
FAIL=0
FAILED_TESTS=""

setup_mock() {
  local state_dir="$1"
  local mock_bin="$2"
  mkdir -p "$state_dir" "$mock_bin"

  cat > "$state_dir/pre_dispatch.json" <<'JSON'
{"result":{"terminal":{"tail":["codex v0.144.5","Ready",""]}}}
JSON

  cat > "$mock_bin/orca" <<'MOCK'
#!/usr/bin/env bash
STATE_DIR="${MOCK_STATE_DIR}"
cmd="$1"; subcmd="$2"
if [[ "$cmd" == "terminal" && "$subcmd" == "read" ]]; then
  if [[ -f "$STATE_DIR/dispatched" ]]; then
    count=$(cat "$STATE_DIR/post_count" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$STATE_DIR/post_count"
    if [[ -f "$STATE_DIR/post_${count}.json" ]]; then
      cat "$STATE_DIR/post_${count}.json"
    elif [[ -f "$STATE_DIR/post_last.json" ]]; then
      cat "$STATE_DIR/post_last.json"
    else
      echo '{"result":{"terminal":{"tail":[""]}}}'
    fi
  else
    cat "$STATE_DIR/pre_dispatch.json"
  fi
  exit 0
fi
if [[ "$cmd" == "terminal" && "$subcmd" == "wait" ]]; then exit 0; fi
if [[ "$cmd" == "orchestration" && "$subcmd" == "dispatch" ]]; then
  touch "$STATE_DIR/dispatched"
  echo 0 > "$STATE_DIR/post_count"
  exit 0
fi
exit 0
MOCK
  chmod +x "$mock_bin/orca"
}

# JSON tail 배열을 python 으로 안전하게 생성
make_post_json() {
  local state_dir="$1"; local index="$2"; shift 2
  python3 -c '
import json, sys
lines = sys.argv[1:]
print(json.dumps({"result":{"terminal":{"tail":lines}}}))
' "$@" > "$state_dir/post_${index}.json"
}

make_post_last() {
  local state_dir="$1"; shift
  python3 -c '
import json, sys
lines = sys.argv[1:]
print(json.dumps({"result":{"terminal":{"tail":lines}}}))
' "$@" > "$state_dir/post_last.json"
}

run_case() {
  local label="$1"; local expected_exit="$2"; local expected_pattern="$3"
  local state_dir="$4"; local mock_bin="$5"
  export MOCK_STATE_DIR="$state_dir"
  output=$(env \
    "PATH=$mock_bin:$PATH" \
    START_CHECK_DELAY_SEC=0 \
    START_CHECK_INTERVAL_SEC=1 \
    START_CHECK_TIMEOUT_SEC=15 \
    DISPATCH_SAFE_TEST_MODE=1 \
    bash "$DISPATCH_SAFE" "test-task-001" "term_mock" "term_conductor" 2>&1)
  local actual_exit=$?
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    if [[ -z "$expected_pattern" ]] || echo "$output" | grep -qE "$expected_pattern"; then
      pass "$label" "exit=$actual_exit"
    else
      fail "$label" "exit OK but output missing /$expected_pattern/"
    fi
  else
    fail "$label" "exit=$actual_exit (expected $expected_exit)"
  fi
}

pass() { local label="$1"; shift; echo "  PASS: $label ($*)"; PASS=$((PASS + 1)); }
fail() { local label="$1"; shift; echo "  FAIL: $label ($*)"; FAIL=$((FAIL + 1)); FAILED_TESTS="$FAILED_TESTS $label"; }

echo "=== dispatch-safe regression tests ==="
echo "  target: $DISPATCH_SAFE"
echo ""

# (1) active@poll3 + context@poll5 -> STARTED (accumulation across polls)
echo "--- Test 1: STARTED via accumulation (active@3, context@5) ---"
{ tmp=$(mktemp -d); mock=$(mktemp -d)
  setup_mock "$tmp" "$mock"
  make_post_json "$tmp" 1 "Working..."
  make_post_json "$tmp" 2 "Thinking..."
  make_post_json "$tmp" 3 "Press Esc to interrupt"
  make_post_json "$tmp" 4 "Processing..."
  make_post_json "$tmp" 5 "Context 3%"
  make_post_last "$tmp" "Working..."
  run_case "started_accumulate" 0 "STARTED" "$tmp" "$mock"
  rm -rf "$tmp" "$mock"; }

# (2) booting polls 1-2, then active+context at poll 3 -> STARTED
echo "--- Test 2: BOOTING then STARTED ---"
{ tmp=$(mktemp -d); mock=$(mktemp -d)
  setup_mock "$tmp" "$mock"
  make_post_json "$tmp" 1 "MCP servers connecting..."
  make_post_json "$tmp" 2 "SessionStart hooks running"
  make_post_json "$tmp" 3 "Press Esc to interrupt" "Context 5%"
  make_post_last "$tmp" "Press Esc to interrupt" "Context 5%"
  run_case "booting_then_started" 0 "STARTED" "$tmp" "$mock"
  rm -rf "$tmp" "$mock"; }

# (3) confirmation dialog -> PROMPT_DETECTED exit 3
echo "--- Test 3: PROMPT_DETECTED exit 3 ---"
{ tmp=$(mktemp -d); mock=$(mktemp -d)
  setup_mock "$tmp" "$mock"
  make_post_json "$tmp" 1 "21 hooks need review" "1. Review" "2. Skip"
  make_post_last "$tmp" "21 hooks need review"
  run_case "prompt_detected" 3 "PROMPT_DETECTED" "$tmp" "$mock"
  rm -rf "$tmp" "$mock"; }

# (4) Context 0% + no active -> NOT_STARTED exit 4
echo "--- Test 4: NOT_STARTED timeout ---"
{ tmp=$(mktemp -d); mock=$(mktemp -d)
  setup_mock "$tmp" "$mock"
  make_post_json "$tmp" 1 "Context 0%"
  make_post_last "$tmp" "Context 0%"
  run_case "not_started_timeout" 4 "NOT_STARTED" "$tmp" "$mock"
  rm -rf "$tmp" "$mock"; }

# (5a) active only -> NOT_STARTED
echo "--- Test 5a: active-only -> NOT_STARTED ---"
{ tmp=$(mktemp -d); mock=$(mktemp -d)
  setup_mock "$tmp" "$mock"
  make_post_json "$tmp" 1 "Press Esc to interrupt"
  make_post_last "$tmp" "Press Esc to interrupt"
  run_case "active_only" 4 "NOT_STARTED" "$tmp" "$mock"
  rm -rf "$tmp" "$mock"; }

# (5b) context only -> NOT_STARTED
echo "--- Test 5b: context-only -> NOT_STARTED ---"
{ tmp=$(mktemp -d); mock=$(mktemp -d)
  setup_mock "$tmp" "$mock"
  make_post_json "$tmp" 1 "Context 12%"
  make_post_last "$tmp" "Context 12%"
  run_case "context_only" 4 "NOT_STARTED" "$tmp" "$mock"
  rm -rf "$tmp" "$mock"; }

# (5c) claude-style: context 없음 + 내용이 변하는 active 2회 -> STARTED (2026-07-27 폴백)
echo "--- Test 5c: changing active w/o context -> STARTED (claude fallback) ---"
{ tmp=$(mktemp -d); mock=$(mktemp -d)
  setup_mock "$tmp" "$mock"
  make_post_json "$tmp" 1 "Booting session"
  make_post_json "$tmp" 2 "* Pondering... (3s - esc to interrupt)"
  make_post_json "$tmp" 3 "* Pondering... (8s - esc to interrupt)"
  make_post_last "$tmp" "* Pondering... (8s - esc to interrupt)"
  run_case "claude_active_fallback" 0 "STARTED" "$tmp" "$mock"
  rm -rf "$tmp" "$mock"; }

# (5d) 내용이 안 변하는 active 반복 -> NOT_STARTED (잔상 가드 유지)
echo "--- Test 5d: static active repeated -> NOT_STARTED ---"
{ tmp=$(mktemp -d); mock=$(mktemp -d)
  setup_mock "$tmp" "$mock"
  make_post_json "$tmp" 1 "old line: esc to interrupt"
  make_post_last "$tmp" "old line: esc to interrupt"
  run_case "static_active_guard" 4 "NOT_STARTED" "$tmp" "$mock"
  rm -rf "$tmp" "$mock"; }

# (6) NOT_STARTED gives guidance, not auto-redeliver
echo "--- Test 6: NOT_STARTED guidance (no auto-redeliver) ---"
{ tmp=$(mktemp -d); mock=$(mktemp -d)
  setup_mock "$tmp" "$mock"
  make_post_json "$tmp" 1 "Context 0%"
  make_post_last "$tmp" "Context 0%"
  export MOCK_STATE_DIR="$tmp"
  output=$(env \
    "PATH=$mock:$PATH" \
    START_CHECK_DELAY_SEC=0 \
    START_CHECK_INTERVAL_SEC=1 \
    START_CHECK_TIMEOUT_SEC=15 \
    DISPATCH_SAFE_TEST_MODE=1 \
    bash "$DISPATCH_SAFE" "test-task-001" "term_mock" "term_conductor" 2>&1)
  exit_code=$?
  if [[ "$exit_code" -ne 4 ]]; then
    fail "not_started_guidance" "exit=$exit_code (expected 4)"
  elif ! echo "$output" | grep -qE "NOT_STARTED"; then
    fail "not_started_guidance" "output missing NOT_STARTED"
  elif ! echo "$output" | grep -qE "dispatch-show"; then
    fail "not_started_guidance" "output missing dispatch-show hint"
  else
    pass "not_started_guidance" "exit=4 + hint, no auto-redeliver"
  fi
  rm -rf "$tmp" "$mock"; }

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED:$FAILED_TESTS"
  exit 1
fi
exit 0
