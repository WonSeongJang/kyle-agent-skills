#!/bin/bash
# 안전한 발령 시퀀스: 부팅 대기 -> 하단 확인창 점검 -> 재 idle -> 발령 -> 스타트 확인
# 사용: dispatch-safe.sh <task_id> <terminal_handle> <from_handle>
#
# 스타트 확인은 고정 sleep+단일 샘플이 아니라 발령 뒤 polling 으로 바뀌었다.
# 매 poll 마다 baseline 이후 새 active 와 Context 1~100% 를 누적하고,
# 둘 다 관찰되면 즉시 STARTED 한다. 부팅 문구가 있으면 BOOTING 으로 계속 poll 하고,
# 확인창이 나타나면 즉시 PROMPT_DETECTED 로 종료한다.
set -u

[ $# -eq 3 ] || { echo "usage: dispatch-safe.sh <task_id> <terminal_handle> <from_handle>"; exit 2; }
TASK_ID="$1"
TERMINAL_HANDLE="$2"
FROM_HANDLE="$3"

ORCA_BIN="${ORCA_BIN:-orca}"

# polling 설정
START_CHECK_INTERVAL_SEC="${START_CHECK_INTERVAL_SEC:-5}"
START_CHECK_TIMEOUT_SEC="${START_CHECK_TIMEOUT_SEC:-120}"

# 운영에서 timeout 이 너무 짧으면 최소 90초로 clamp. 테스트 모드는 허용.
if [[ "${DISPATCH_SAFE_TEST_MODE:-0}" != "1" ]]; then
  if [[ "$START_CHECK_TIMEOUT_SEC" -lt 90 ]]; then
    START_CHECK_TIMEOUT_SEC=90
  fi
fi

# bash 산술 연산은 정수만 받으므로 소수점 이하를 버리고 최소 1 로 올린다.
POLL_SLEEP="${START_CHECK_INTERVAL_SEC%%.*}"
[[ "$POLL_SLEEP" -ge 1 ]] 2>/dev/null || POLL_SLEEP=1

read_tail() {
  "$ORCA_BIN" terminal read --terminal "$TERMINAL_HANDLE" --limit 14 --json
}

# 맨 셸은 tui-idle 대기 자체가 끝나지 않을 수 있으므로 먼저 확인한다.
SHELL_RESULT=$(read_tail | python3 -c '
import json,re,sys
try:
    tail=json.load(sys.stdin)["result"]["terminal"]["tail"]
    text="\n".join(str(x) for x in tail[-8:]) if isinstance(tail,list) else str(tail)
except Exception:
    print("READ_ERROR"); raise SystemExit(0)
lines=[re.sub(r"\s+"," ",line).strip() for line in text.splitlines() if line.strip()]
shell=re.compile(r"(?:^|\s)(?:[^\s]+@[^\s]+\s+)?[^\n]*[%$]$")
print("SHELL_DETECTED " + lines[-1] if lines and shell.search(lines[-1]) else "CLEAR")
')
case "$SHELL_RESULT" in
  SHELL_DETECTED*)
    echo "NOT_STARTED"
    echo "HINT: orca orchestration dispatch-show --task $TASK_ID --preamble --from $FROM_HANDLE; then manually start the agent and redeliver the preamble"
    exit 4
    ;;
  READ_ERROR*) echo "$SHELL_RESULT"; exit 1;;
esac

if ! "$ORCA_BIN" terminal wait --terminal "$TERMINAL_HANDLE" --for tui-idle --timeout-ms 90000 --json >/dev/null; then
  echo "TUI_IDLE_TIMEOUT"
  exit 1
fi

# 첫 idle 직후 늦게 나타나는 훅/업데이트/폴더 신뢰 창은 자동 통과하지 않는다.
PROMPT_RESULT=$(read_tail | python3 -c '
import json, re, sys
try:
    tail = json.load(sys.stdin)["result"]["terminal"]["tail"]
    text = "\n".join(str(x) for x in tail[-10:]) if isinstance(tail, list) else str(tail)
except Exception:
    print("READ_ERROR")
    raise SystemExit(0)
patterns = re.compile(r"hooks? (?:need|to) review|review hooks|update now|self.update|folder trust|trust this folder|폴더.*신뢰|훅.*검토|업데이트", re.I)
matches = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()[-6:] if patterns.search(line)]
print("PROMPT_DETECTED " + " / ".join(matches[-2:]) if matches else "CLEAR")
')
case "$PROMPT_RESULT" in
  PROMPT_DETECTED*) echo "$PROMPT_RESULT"; exit 3;;
  READ_ERROR*) echo "$PROMPT_RESULT"; exit 1;;
esac

if ! "$ORCA_BIN" terminal wait --terminal "$TERMINAL_HANDLE" --for tui-idle --timeout-ms 90000 --json >/dev/null; then
  echo "TUI_IDLE_TIMEOUT_AFTER_PROMPT_CHECK"
  exit 1
fi

DISPATCH_OUT=$("$ORCA_BIN" orchestration dispatch --task "$TASK_ID" --to "$TERMINAL_HANDLE" --from "$FROM_HANDLE" --inject --json 2>&1) || {
  echo "DISPATCH_FAILED"
  # 오류 원문을 삼키지 않는다 (2026-07-28 실사고: pending 카드 오류가 숨겨져 터미널 사망으로 오진 → 불필요한 미등록 엔진 우회)
  echo "ERROR_DETAIL: $(printf '%s' "$DISPATCH_OUT" | tail -c 500)"
  echo "HINT: 카드 상태를 확인하라 — pending이면 task-update --status ready 후 재발령."
  exit 1
}

# 라우팅 원장 자동 기록 (2026-07-27) — 실패해도 발령 흐름에 영향 없음. 테스트 모드에선 스킵.
[[ "${DISPATCH_SAFE_TEST_MODE:-0}" == "1" ]] || "$(dirname "$0")/routing-ledger-append.sh" "dispatch_auto" "${ROUTING_BOARD:-unknown}" "$TASK_ID" \
  "{\"terminal\":\"$TERMINAL_HANDLE\",\"from\":\"$FROM_HANDLE\"}" 2>/dev/null || true

# ---- polling-based start check ----
# 발령 직전 화면을 baseline 으로 저장한다. 이후 매 poll 에서 baseline 이후
# 새로 나타난 양성 신호를 누적한다. active 와 context 가 서로 다른 poll 에
# 관찰돼도 둘 다 보이면 STARTED 다.
START_BASELINE=$(read_tail)
export START_BASELINE_JSON="$START_BASELINE"

seen_active=0
seen_context=0
active_hash_1=""
active_hash_2=""
elapsed=0

while [[ "$elapsed" -lt "$START_CHECK_TIMEOUT_SEC" ]]; do
  sleep "$POLL_SLEEP"
  elapsed=$((elapsed + POLL_SLEEP))

  POLL_RESULT=$(read_tail | python3 -c '
import json, os, re, sys
try:
    tail = json.load(sys.stdin)["result"]["terminal"]["tail"]
    text = "\n".join(str(x) for x in tail[-14:]) if isinstance(tail, list) else str(tail)
except Exception:
    print("READ_ERROR"); raise SystemExit(0)
try:
    old_tail = json.loads(os.environ["START_BASELINE_JSON"])["result"]["terminal"]["tail"]
    old_text = "\n".join(str(x) for x in old_tail[-14:]) if isinstance(old_tail, list) else str(old_tail)
except Exception:
    old_text = ""

lines = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()]
old_lines = {re.sub(r"\s+", " ", line).strip() for line in old_text.splitlines()}
new_lines = [line for line in lines if line and line not in old_lines]

# (1) 확인창 — 즉시 PROMPT_DETECTED
prompt_re = re.compile(r"hooks? (?:need|to) review|review hooks|update now|self\.update|folder trust|trust this folder|폴더.*신뢰|훅.*검토|업데이트", re.I)
prompt_matches = [line for line in lines[-6:] if prompt_re.search(line)]
if prompt_matches:
    print("PROMPT_DETECTED " + " / ".join(prompt_matches[-2:]))
    raise SystemExit(0)

# (2) 부팅 문구 — BOOTING 으로 계속 (이 poll 의 신호는 무시)
boot_re = re.compile(r"mcp|session.?start|loading|initializing|starting up|booting|connecting", re.I)
if any(boot_re.search(line) for line in new_lines[-4:]):
    print("BOOTING")
    raise SystemExit(0)

# (3) 양성 신호 누적
active_re = re.compile(r"esc to interrupt|updated plan|[•·*] ran|[•·*] explored", re.I)
context_re = re.compile(r"context\s+(?:[1-9]\d?|100)%", re.I)
signals = []
active_lines = [line for line in new_lines if active_re.search(line)]
if active_lines:
    import hashlib
    digest = hashlib.md5("\n".join(active_lines).encode()).hexdigest()[:12]
    signals.append("ACTIVE:" + digest)
if any(context_re.search(line) for line in new_lines):
    signals.append("CONTEXT")
if signals:
    print(" ".join(signals))
else:
    print("WAITING")
')

  case "$POLL_RESULT" in
    READ_ERROR*) echo "$POLL_RESULT"; exit 1;;
    PROMPT_DETECTED*) echo "$POLL_RESULT"; exit 3;;
    BOOTING*) continue;;
    *ACTIVE*)
      seen_active=1
      poll_hash="${POLL_RESULT##*ACTIVE:}"; poll_hash="${poll_hash%% *}"
      if [[ -z "$active_hash_1" ]]; then
        active_hash_1="$poll_hash"
      elif [[ "$poll_hash" != "$active_hash_1" ]]; then
        active_hash_2="$poll_hash"
      fi
      ;;
  esac
  case "$POLL_RESULT" in
    *CONTEXT*) seen_context=1;;
  esac

  if [[ "$seen_active" -eq 1 && "$seen_context" -eq 1 ]]; then
    echo "STARTED"
    exit 0
  fi

  # 2026-07-27 오판 2건 대응: Context 신호가 구조적으로 안 잡히는 화면이 있다.
  # (1) Claude Code 작업자 — "Context N%" 상태바 자체가 없음(codex 전용)
  # (2) 좁은 pane — 상태바가 "Context…"로 잘려 퍼센트 숫자 소실
  # 서로 다른 poll 에서 "내용이 다른" ACTIVE 가 2회 관찰되면(스피너 경과·리페인트 변화
  # = 실제 진행 증거) Context 없이도 STARTED 로 판정한다. 같은 내용 반복은 잔상일 수
  # 있어 세지 않는다 — 기존 잔상 가드(test 5a)와 양립.
  if [[ -n "$active_hash_1" && -n "$active_hash_2" ]]; then
    echo "STARTED (active-progress fallback — context unavailable)"
    exit 0
  fi
done

# timeout 도달 — NOT_STARTED. 자동 재배달하지 않고 화면 근거 확인 안내만 출력.
echo "NOT_STARTED"
echo "HINT: orca orchestration dispatch-show --task $TASK_ID --preamble --from $FROM_HANDLE"
echo "HINT: terminal read 로 화면 하단을 직접 확인한 뒤 수동 재배달 여부를 결정한다. 자동 재배달하지 않는다."
echo "HINT: 직접 판정 대신 중계기(luna)에 판정을 위임해도 된다 — 저렴한 모델이 화면을 읽고 시작/미시작만 보고 (mechanics.md 시작 판정 절)."
exit 4
