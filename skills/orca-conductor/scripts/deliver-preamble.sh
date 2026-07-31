#!/bin/bash
# orca-conductor 발령문 수동 배달 스크립트 (gjc 등 --inject 불가 CLI용)
# 사용: deliver-preamble.sh <terminal-handle> <preamble-file>
# 절차: 텍스트 전송 → 엔터 → 제출 판정 → 미제출이면 엔터 재전송 (최대 3회)
# 제출 판정 (2026-07-20 실사고 반영): 발령문의 "꼬리"(마지막 24자)가 화면 하단에
# 남아 있으면 미제출로 본다 — 머리 마커([판:...])는 입력창에서 스크롤돼 안 보이므로
# 머리 기준 판정은 오판을 낳는다 (실사고 2회: 엔터 씹힘을 제출로 오판).
set -u
[ $# -eq 2 ] || { echo "usage: deliver-preamble.sh <handle> <preamble-file>"; exit 2; }
HANDLE="$1"; FILE="$2"
[ -f "$FILE" ] || { echo "NO_SUCH_FILE $FILE"; exit 2; }

TAIL_SIG=$(python3 -c "
import re,sys
t=open('$FILE').read().strip()
t=re.sub(r'\s+',' ',t)
print(t[-24:])")

orca terminal send --terminal "$HANDLE" --text "$(cat "$FILE")" --json >/dev/null 2>&1 || { echo "SEND_FAILED"; exit 1; }
sleep 2

for i in 1 2 3; do
  orca terminal send --terminal "$HANDLE" --enter --json >/dev/null 2>&1
  sleep 4
  PENDING=$(orca terminal read --terminal "$HANDLE" --limit 15 --json 2>/dev/null | python3 -c "
import json,sys,re
try:
    tail=json.load(sys.stdin)['result']['terminal']['tail']
except Exception:
    print('READ_ERROR'); sys.exit()
t=re.sub(r'[⠀-⣿]','', '\n'.join(tail))
t=re.sub(r'[│╭╮╰╯─]',' ',t)
t=re.sub(r'\s+',' ',t)
sig=re.sub(r'\s+',' ','''$TAIL_SIG''')
# 화면 하단 500자 안에 발령문 꼬리가 남아 있으면 입력창 잔존 = 미제출
print('PENDING' if sig.strip() and sig.strip() in t[-500:] else 'SUBMITTED')")
  if [ "$PENDING" = "SUBMITTED" ]; then
    echo "SUBMITTED after ${i} enter(s)"
    exit 0
  fi
  echo "attempt ${i}: still pending, retrying enter"
done
echo "STILL_PENDING_AFTER_3 — 지휘자 수동 확인 필요"
exit 1
