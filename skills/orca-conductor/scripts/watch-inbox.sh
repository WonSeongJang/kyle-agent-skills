#!/bin/bash
# orca-conductor 우편함 감시 스크립트 — 지정한 명패(핸들) 앞으로 새 편지가 오면 내용을 출력하고 종료한다.
# 사용: watch-inbox.sh <coordinator-handle>
# 환경변수: WATCH_DEADLINE_MIN(기본 60분), WATCH_INTERVAL_SEC(기본 30초), WATCH_TYPES(기본 worker_done,escalation,decision_gate)
# 주의: run_in_background로 "직접" 실행할 것 (셸 안 '&' 금지 — watch-card.sh와 동일).
# 카드 상태 감시(watch-card.sh)와 역할이 다르다: 이쪽은 escalation/decision_gate처럼
# 카드 상태가 안 바뀌는 신호를 잡는다. 판마다 둘 다 띄우는 게 기본.
set -u
[ $# -eq 1 ] || { echo "usage: watch-inbox.sh <coordinator-handle>"; exit 2; }
HANDLE="$1"
# 기본에서 worker_done 제외 (2026-07-20): worker_done은 watch-card가 잡는다 — 역할이 겹치면
# "inbox 감시는 중복"이라는 오판을 낳아 생략 드리프트를 유발한다 (실사고: decision_gate 2분 미수신).
TYPES="${WATCH_TYPES:-escalation,decision_gate}"
DEADLINE=$(( $(date +%s) + ${WATCH_DEADLINE_MIN:-60} * 60 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  OUT=$(orca orchestration check --terminal "$HANDLE" --types "$TYPES" --unread --json 2>/dev/null)
  COUNT=$(printf '%s' "$OUT" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    msgs=(d.get('result') or {}).get('messages') or []
    print(len(msgs))
except Exception:
    print(0)")
  if [ "${COUNT:-0}" -gt 0 ]; then
    echo "NEW_MESSAGES ${COUNT}"
    printf '%s\n' "$OUT"
    exit 0
  fi
  sleep "${WATCH_INTERVAL_SEC:-30}"
done
echo "DEADLINE_REACHED"
exit 1
