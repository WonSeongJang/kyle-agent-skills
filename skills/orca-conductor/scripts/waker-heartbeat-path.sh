#!/bin/bash
# 깨우기(supervisor-waker)의 심박 파일 경로를 정하는 **단 하나의 자리**다.
#
# Why: 심박을 적는 쪽(supervisor-waker.sh)과 끊긴 것을 신고하는 쪽(stall-reporter.sh)이
# 각자 경로를 계산하면 언젠가 한쪽만 바뀐다. 그러면 신고기는 아무도 쓰지 않는 파일을
# 보며 "깨우기 죽음"을 계속 외치거나, 반대로 영원히 조용해진다. 둘 다 오늘 하루 잡은
# 부류다 — 대상이 어긋난 채로 판정이 나가는 것. 그래서 계산을 한 곳에만 둔다.
#
# 왜 인자가 아니라 유도(derive)인가: 신고기 쪽 방어를 선택 인자로 만들면 "안 주면 안 켜지는"
# 방어가 된다. 판 이름과 중계기 일기 경로는 신고기가 이미 필수로 받으므로, 심박 경로는
# 그 둘에서 항상 유도된다. 즉 **끄는 방법이 없다.**
#
# 왜 중계기 일기에 같이 적지 않는가 (임시 운영 판본에서 바꾼 유일한 지점):
#   신고기의 "중계기 순찰이 멈췄다" 판정은 중계기 일기의 **파일 수정 시각**을 본다.
#   깨우기가 같은 파일에 심박을 append 하면 중계기가 죽어도 그 파일이 계속 새것이 된다.
#   깨우는 주기가 중계기 침묵 임계값보다 짧아지는 순간(예: 주기 600초 vs 임계값 900초)
#   중계기 사망은 **영영 신고되지 않는다.** 우리가 만든 장치가 이미 있는 감시의 눈을 가리는
#   초록불 위장이다. 그래서 심박은 중계기 일기 **옆의 자기 파일**에 적는다.
#   감시하는 쪽은 그대로 이미 있는 정체 신고기 하나다 — 새 감시 프로세스는 만들지 않는다.
#   이 위장은 시험 waker_heartbeat_in_relay_log_would_mask_relay_death 가 실측으로 보인다.

# $1 = 중계기 일기 경로, $2 = 판 이름
waker_heartbeat_path() {
  local relay_log="$1" board="$2" dir safe
  [ -n "$relay_log" ] || return 1
  [ -n "$board" ] || return 1
  dir=$(dirname "$relay_log")
  # 판 이름은 파일명이 되므로 경로 문자를 남기지 않는다. stall-reporter 의 상태 파일
  # 이름과 같은 규칙을 쓴다.
  safe=$(printf '%s' "$board" | tr -c 'A-Za-z0-9._-' '_')
  printf '%s/%s.waker-heartbeat.log' "$dir" "$safe"
}

# 직접 실행하면 경로를 찍는다. 사람이 확인할 때와 시험이 두 쪽의 계산이 같은지 대조할 때 쓴다.
# 사용법: waker-heartbeat-path.sh <중계기 일기 경로> <판 이름>
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  if [ "$#" -ne 2 ]; then
    echo "usage: waker-heartbeat-path.sh <relay-log> <board>" >&2
    exit 2
  fi
  waker_heartbeat_path "$1" "$2" || exit 2
  printf '\n'
fi
