#!/bin/bash
# orca-conductor 표준 감시 스크립트 — 지정한 카드가 전부 종결(completed/failed)되면 스스로 종료한다.
# 사용: watch-card.sh <taskId> [taskId...]
# 환경변수: WATCH_DEADLINE_MIN(기본 60분), WATCH_INTERVAL_SEC(기본 30초)
# 주의: run_in_background로 "직접" 실행할 것. 셸 안에서 '&'로 띄우면 부모 종료와 함께 죽는다(2026-07-13 실측).
# 감시는 카드 상태 기반 — check --wait 단독 대기는 우편함 어긋남으로 영원히 빈손일 수 있다(2026-07-13 실측).
set -u
[ $# -ge 1 ] || { echo "usage: watch-card.sh <taskId> [taskId...]"; exit 2; }
DEADLINE=$(( $(date +%s) + ${WATCH_DEADLINE_MIN:-60} * 60 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  SNAP=$(python3 - "$@" <<'PY'
import json, subprocess, sys
ids = set(sys.argv[1:])
try:
    out = subprocess.run(['orca','orchestration','task-list','--json'],
                         capture_output=True, text=True, timeout=30).stdout
    d = json.loads(out)
    rows = {t['id']: t['status'] for t in d['result']['tasks'] if t['id'] in ids}
except Exception as e:
    print(f'ERROR {e}'); raise SystemExit
missing = ids - set(rows)
open_states = {'pending', 'ready', 'dispatched'}
settled = bool(rows) and not missing and all(s not in open_states for s in rows.values())
line = ('SETTLED' if settled else 'OPEN') + ' ' + '|'.join(f"{k[-6:]}:{v}" for k, v in sorted(rows.items()))
if missing: line += f' missing:{len(missing)}'
print(line)
PY
)
  echo "$(date +%H:%M:%S) $SNAP"
  case "$SNAP" in SETTLED*) echo "ALL_SETTLED"; exit 0;; esac
  sleep "${WATCH_INTERVAL_SEC:-30}"
done
echo "DEADLINE_REACHED"
exit 1
