#!/bin/bash
# B7 판 비움 감지 시험 — 거부 증거(변이 실측) 포함.
#
# Why: 작업자가 다 끝났는데 감독이 다음 행동을 안 하는 상태를 신고기가 잡아야 한다.
# 이 시험은 (1) 그 상태에서 신고기가 침묵하면 떨어지고, (2) 경우 A/B 문구가 다르고,
# (3) 정상 유휴에서는 오보가 안 나는 것을 보인다.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
# 시험 대상 구현을 밖에서 갈아끼울 수 있게 둔다. 변이 검증용 장치:
#   STALL_REPORTER_UNDER_TEST=<고장 낸 복사본> bash test-stall-reporter.sh  -> 실패해야 정상
REPORTER="${STALL_REPORTER_UNDER_TEST:-$SKILL_DIR/scripts/stall-reporter.sh}"
FIXTURE="$SCRIPT_DIR/fixtures/orca"

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS %s\n' "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL %s\n' "$1" >&2; }

new_state() {
  mktemp -d /tmp/orca-stall-reporter.XXXXXX
}

count_matches() {
  local pattern="$1" file="$2"
  [ -f "$file" ] || { printf '0\n'; return 0; }
  rg -c -- "$pattern" "$file" 2>/dev/null || printf '0\n'
}

# task_list.json 을 지정한 상태 목록으로 만든다.
make_task_list() {
  local dir="$1"; shift
  local tasks="" i=0
  for status in "$@"; do
    i=$((i + 1))
    [ -n "$tasks" ] && tasks="$tasks,"
    tasks="$tasks{\"id\":\"task_$i\",\"run_id\":\"run_project\",\"status\":\"$status\",\"deps\":\"[]\"}"
  done
  printf '{"ok":true,"result":{"runId":"run_project","count":%d,"tasks":[%s]}}\n' "$i" "$tasks" > "$dir/task_list.json"
}

# task_list 응답을 원문 그대로 심는다 (조회 실패·깨진 응답 재현용).
make_task_list_raw() {
  printf '%s\n' "$2" > "$1/task_list.json"
}

# 신고기를 한 번 돌린다. --board-idle-sec 300 고정.
run_reporter() {
  local state_dir="$1"
  export FAKE_ORCA_STATE_DIR="$state_dir"
  export ORCA_BIN="$FIXTURE"
  export STALL_REPORTER_STATE_DIR="$state_dir/reporter-state"
  export FAKE_RELAY_HANDLE="term_relay"
  mkdir -p "$STALL_REPORTER_STATE_DIR"
  set +e
  "$REPORTER" --project project_test --board board_test \
    --relay-log "$state_dir/relay.log" \
    --super-run run_super --project-run run_project --relay-role relay \
    --relay-silence-sec 999999 --board-idle-sec 300 --poll-sec 1 --once \
    > "$state_dir/reporter-output.log" 2>&1
  local status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    printf 'REPORTER_UNEXPECTED_EXIT status=%s\n' "$status" >&2
    tail -10 "$state_dir/reporter-output.log" >&2 2>/dev/null || true
  fi
}

# --board-idle-sec 를 아예 주지 않고 돌린다. 방어가 선택 인자에 매달려 있으면 여기서 떨어진다.
run_reporter_no_flag() {
  local state_dir="$1"
  export FAKE_ORCA_STATE_DIR="$state_dir"
  export ORCA_BIN="$FIXTURE"
  export STALL_REPORTER_STATE_DIR="$state_dir/reporter-state"
  export FAKE_RELAY_HANDLE="term_relay"
  mkdir -p "$STALL_REPORTER_STATE_DIR"
  set +e
  "$REPORTER" --project project_test --board board_test \
    --relay-log "$state_dir/relay.log" \
    --super-run run_super --project-run run_project --relay-role relay \
    --relay-silence-sec 999999 --poll-sec 1 --once \
    > "$state_dir/reporter-output-noflag.log" 2>&1
  set -e
}

# relay.log 를 만든다. 기본은 순찰 정상 줄 1개.
make_relay_log() {
  local dir="$1" mode="${2:-normal}"
  case "$mode" in
    normal)
      printf '2026-08-09 10:00:00 +0900|patrol_summary task=task_x dispatch=ctx_x pane=p:x active_dispatched=0 no_progress_streak=0 action=none\n' > "$dir/relay.log"
      ;;
    flood)
      # 순찰 데이터 1줄 뒤에 gate_nudge_suppressed 홍수 500줄.
      printf '2026-08-09 10:00:00 +0900|patrol_summary task=task_x dispatch=ctx_x pane=p:x active_dispatched=0 no_progress_streak=5 action=report_stall\n' > "$dir/relay.log"
      local k
      for k in $(seq 1 500); do
        printf '2026-08-09 10:0%d:00 +0900|gate_nudge_suppressed reason=inbox_saturated wake=0\n' "$k" >> "$dir/relay.log"
      done
      ;;
  esac
}

# state 파일을 미리 심는다 (지속 시간 시뮬레이션). 4번째 인자는 경우 C 시작 시각(생략 시 0).
seed_state() {
  local state_dir="$1" case_a_since="$2" case_b_since="$3" case_c_since="${4:-0}"
  mkdir -p "$state_dir/reporter-state"
  cat > "$state_dir/reporter-state/board_test.state" <<EOF
ALERTED_LEVEL=0
RELAY_SILENT_ALERTED=0
BOARD_CASE_A_SINCE=$case_a_since
BOARD_CASE_A_ALERTED=0
BOARD_CASE_B_SINCE=$case_b_since
BOARD_CASE_B_ALERTED=0
BOARD_CASE_C_SINCE=$case_c_since
BOARD_CASE_C_ALERTED=0
CARD_QUERY_FAIL_STREAK=0
CARD_QUERY_FAIL_ALERTED=0
CARD_CLASSIFICATION_UNAVAILABLE_STREAK=0
CARD_CLASSIFICATION_UNAVAILABLE_ALERTED=0
EOF
}

state_field() {
  sed -n "s/^$2=\(.*\)$/\1/p" "$1/reporter-state/board_test.state" 2>/dev/null | tail -1
}

# === 시험 케이스 ===

# 1. 경우 A 발신: 대기 카드 있음 + 발령 0 + 지속
test_case_a_fires() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd" pending pending completed
  seed_state "$sd" "$(($(date +%s) - 600))" 0
  run_reporter "$sd"
  local n
  n=$(count_matches '발령을 안 하고 있다' "$sd/project-sends.log")
  [ "$n" -ge 1 ] && pass "case_a_fires: 대기+발령0 지속 -> 발령 안 함 경고" \
    || fail "case_a_fires: 신고기 침묵 (대기 카드 있는데 발령 0인데 보고 안 함)"
}

# 2. 경우 B 발신: 대기 0 + 발령 0 + 지속
test_case_b_fires() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd" completed completed
  seed_state "$sd" 0 "$(($(date +%s) - 600))"
  run_reporter "$sd"
  local n
  n=$(count_matches '다음 카드를 요청하지 않고 있다' "$sd/project-sends.log")
  [ "$n" -ge 1 ] && pass "case_b_fires: 판 비움+지속 -> 다음 카드 요청 없음 경고" \
    || fail "case_b_fires: 신고기 침묵 (판 비었는데 다음 카드 요청 없음 보고 안 함)"
}

# 3. 경우 A와 B 문구가 서로 다르다
test_wording_differs() {
  local sd_a sd_b subj_a subj_b
  sd_a=$(new_state)
  make_relay_log "$sd_a" normal
  make_task_list "$sd_a" pending
  seed_state "$sd_a" "$(($(date +%s) - 600))" 0
  run_reporter "$sd_a"
  sd_b=$(new_state)
  make_relay_log "$sd_b" normal
  make_task_list "$sd_b"
  seed_state "$sd_b" 0 "$(($(date +%s) - 600))"
  run_reporter "$sd_b"
  subj_a=$(rg -o '발령을 안 하고 있다' "$sd_a/project-sends.log" 2>/dev/null | head -1 || printf '')
  subj_b=$(rg -o '다음 카드를 요청하지 않고 있다' "$sd_b/project-sends.log" 2>/dev/null | head -1 || printf '')
  if [ -n "$subj_a" ] && [ -n "$subj_b" ] && [ "$subj_a" != "$subj_b" ]; then
    pass "wording_differs: 경우 A·B 문구가 서로 다르다"
  else
    fail "wording_differs: 문구가 같거나 누락 (a=${subj_a:-없음} b=${subj_b:-없음})"
  fi
}

# 4. 정상: 발령 있음 -> 판 비움 오보 없음
test_normal_dispatched() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd" dispatched dispatched pending
  seed_state "$sd" 0 0
  run_reporter "$sd"
  local na nb
  na=$(count_matches '발령을 안 하고 있다' "$sd/project-sends.log")
  nb=$(count_matches '다음 카드를 요청하지 않고 있다' "$sd/project-sends.log")
  [ "$na" -eq 0 ] && [ "$nb" -eq 0 ] \
    && pass "normal_dispatched: 발령 중이면 판 비움 오보 없음" \
    || fail "normal_dispatched: 발령 중인데 오보 (a=$na b=$nb)"
}

# 5. 정상: 임계값 미달 -> 오보 없음 (잠깐 유휴는 정상이다)
test_normal_below_threshold() {
  local sd now
  now=$(date +%s)
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd" pending pending
  seed_state "$sd" "$now" 0
  run_reporter "$sd"
  local n
  n=$(count_matches '발령을 안 하고 있다' "$sd/project-sends.log")
  [ "$n" -eq 0 ] \
    && pass "normal_below_threshold: 임계값 미달이면 오보 없음" \
    || fail "normal_below_threshold: 임계값 미달인데 발신 (n=$n)"
}

# 6. 정상 유휴: 판 비었다가 제때 카드 나타남 -> 오보 없음 (2회 --once 시뮬레이션)
test_normal_idle_recovered() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd"
  seed_state "$sd" 0 "$(($(date +%s) - 100))"
  run_reporter "$sd"
  local n1
  n1=$(count_matches '다음 카드를 요청하지 않고 있다' "$sd/project-sends.log")
  make_task_list "$sd" dispatched
  seed_state "$sd" 0 "$(($(date +%s) - 100))"
  run_reporter "$sd"
  local n2
  n2=$(count_matches '다음 카드를 요청하지 않고 있다' "$sd/project-sends.log")
  [ "$n1" -eq 0 ] && [ "$n2" -eq 0 ] \
    && pass "normal_idle_recovered: 판 비었다가 제때 카드 나타나면 오보 없음" \
    || fail "normal_idle_recovered: 정상 유휴인데 오보 (n1=$n1 n2=$n2)"
}

# 7. 잡음 견딤: gate_nudge_suppressed 홍수 뒤에 숨은 순찰 데이터를 읽는다
test_flood_robust() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" flood
  make_task_list "$sd" dispatched dispatched
  seed_state "$sd" 0 0
  run_reporter "$sd"
  local n
  n=$(count_matches '감독 무진행' "$sd/project-sends.log")
  [ "$n" -ge 1 ] \
    && pass "flood_robust: 홍수 뒤 순찰 데이터(no_progress=5)를 읽어 정체 발신" \
    || fail "flood_robust: 홍수가 순찰 데이터를 가림 (정체 미발신)"
}

# 8. 재장전: 발신 후 카드 발령되면 상태 리셋
test_rearm_after_dispatch() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd" pending
  seed_state "$sd" "$(($(date +%s) - 600))" 0
  run_reporter "$sd"
  make_task_list "$sd" dispatched
  run_reporter "$sd"
  grep -q 'BOARD_CASE_A_ALERTED=0' "$sd/reporter-state/board_test.state" 2>/dev/null \
    && pass "rearm_after_dispatch: 발령 후 BOARD_CASE_A_ALERTED 리셋" \
    || fail "rearm_after_dispatch: 발령 후 재장전 안 됨"
}

# === F-B7 경계 시험: 세 경우가 각각 서로 다른 문구로 나가는가 ===
# Why: B7 검수에서 "판 비움 + 다음 요청 있음"(경우 C)이 경우 B로 접혀 나가는 것이
# 드러났다. 경계 시험이 A와 B만 봤기 때문이다. 세 경우를 각각 인위적으로 만들어 넣고
# 문구가 실제로 다르게 나오는지 여기서 박는다.

# 9. 경우 C 발신: 미결 카드(blocked) 남음 + 대기 0 + 발령 0
test_case_c_fires() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd" completed blocked
  seed_state "$sd" 0 0 "$(($(date +%s) - 600))"
  run_reporter "$sd"
  local n
  n=$(count_matches '미결 카드가 남았는데' "$sd/project-sends.log")
  [ "$n" -ge 1 ] && pass "case_c_fires: 판 비움+미결 카드 -> 미결 카드 경고" \
    || fail "case_c_fires: 미결 카드가 남았는데 침묵"
}

# 10. [검수 발견 1 회귀] 미결 카드가 있으면 경우 B로 접히면 안 된다
test_case_c_not_folded_into_b() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd" completed blocked
  seed_state "$sd" 0 "$(($(date +%s) - 600))" "$(($(date +%s) - 600))"
  run_reporter "$sd"
  local nb ncomplete
  nb=$(count_matches '다음 카드를 요청하지 않고 있다' "$sd/project-sends.log")
  ncomplete=$(count_matches '판이 완전히 비었다' "$sd/project-sends.log")
  { [ "$nb" -eq 0 ] && [ "$ncomplete" -eq 0 ]; } \
    && pass "case_c_not_folded_into_b: 미결 카드 있으면 '판이 완전히 비었다'로 보고하지 않음" \
    || fail "case_c_not_folded_into_b: 할 일이 남았는데 끝난 상태로 오보 (b=$nb empty=$ncomplete)"
}

# 11. 세 문구가 서로 전부 다르다
test_three_wordings_differ() {
  local sd_a sd_b sd_c seen
  sd_a=$(new_state); make_relay_log "$sd_a" normal
  make_task_list "$sd_a" pending
  seed_state "$sd_a" "$(($(date +%s) - 600))" 0 0
  run_reporter "$sd_a"
  sd_b=$(new_state); make_relay_log "$sd_b" normal
  make_task_list "$sd_b" completed
  seed_state "$sd_b" 0 "$(($(date +%s) - 600))" 0
  run_reporter "$sd_b"
  sd_c=$(new_state); make_relay_log "$sd_c" normal
  make_task_list "$sd_c" blocked
  seed_state "$sd_c" 0 0 "$(($(date +%s) - 600))"
  run_reporter "$sd_c"
  # 각 판에서 실제로 나간 제목 줄을 뽑아 서로 다른지 본다.
  local ta tb tc
  ta=$(rg -o -- '--subject [^ ]*\[정체신고\][^"]*' "$sd_a/project-sends.log" 2>/dev/null | head -1 || printf '')
  tb=$(rg -o -- '--subject [^ ]*\[정체신고\][^"]*' "$sd_b/project-sends.log" 2>/dev/null | head -1 || printf '')
  tc=$(rg -o -- '--subject [^ ]*\[정체신고\][^"]*' "$sd_c/project-sends.log" 2>/dev/null | head -1 || printf '')
  seen=$(printf '%s\n%s\n%s\n' "$ta" "$tb" "$tc" | sort -u | grep -c . || printf '0')
  if [ -n "$ta" ] && [ -n "$tb" ] && [ -n "$tc" ] && [ "$seen" -eq 3 ]; then
    pass "three_wordings_differ: 경우 A·B·C 문구가 셋 다 서로 다르다"
  else
    fail "three_wordings_differ: 문구가 겹치거나 누락 (구분된 문구 수=$seen a=${ta:-없음} b=${tb:-없음} c=${tc:-없음})"
  fi
}

# 12. 경우 C 재장전: 미결 카드가 대기로 풀리면 C가 꺼진다
test_case_c_rearm() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd" blocked
  seed_state "$sd" 0 0 "$(($(date +%s) - 600))"
  run_reporter "$sd"
  make_task_list "$sd" dispatched
  run_reporter "$sd"
  local since alerted
  since=$(state_field "$sd" BOARD_CASE_C_SINCE)
  alerted=$(state_field "$sd" BOARD_CASE_C_ALERTED)
  { [ "$since" = 0 ] && [ "$alerted" = 0 ]; } \
    && pass "case_c_rearm: 발령되면 경우 C 상태 리셋" \
    || fail "case_c_rearm: 재장전 안 됨 (since=$since alerted=$alerted)"
}

# === F-B7 경계 시험: 카드 장부 조회 실패는 "카드 0장"이 아니다 ===

# 13. [검수 발견 2 회귀] ok=false 응답으로 판 비움 경고가 나가면 안 된다
test_query_ok_false_never_reports_empty() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list_raw "$sd" '{"ok":false,"error":"run_not_found","result":{"runId":"run_project","count":0,"tasks":[]}}'
  seed_state "$sd" "$(($(date +%s) - 600))" "$(($(date +%s) - 600))" "$(($(date +%s) - 600))"
  run_reporter "$sd"
  local na nb nc
  na=$(count_matches '발령을 안 하고 있다' "$sd/project-sends.log")
  nb=$(count_matches '다음 카드를 요청하지 않고 있다' "$sd/project-sends.log")
  nc=$(count_matches '미결 카드가 남았는데' "$sd/project-sends.log")
  { [ "$na" -eq 0 ] && [ "$nb" -eq 0 ] && [ "$nc" -eq 0 ]; } \
    && pass "query_ok_false_never_reports_empty: 조회 실패를 판 비움으로 접지 않음" \
    || fail "query_ok_false_never_reports_empty: 실패 응답을 믿고 판정 (a=$na b=$nb c=$nc)"
}

# 14. 조회 실패 중에는 경우 A/B/C 상태를 얼려 둔다 (성급한 재장전 금지)
test_query_fail_freezes_case_state() {
  local sd since_before since_after
  sd=$(new_state)
  make_relay_log "$sd" normal
  since_before=$(($(date +%s) - 100))
  make_task_list_raw "$sd" '{"ok":false,"result":{"tasks":[]}}'
  seed_state "$sd" "$since_before" 0 0
  run_reporter "$sd"
  since_after=$(state_field "$sd" BOARD_CASE_A_SINCE)
  [ "$since_after" = "$since_before" ] \
    && pass "query_fail_freezes_case_state: 조회 실패 중 경우 상태를 건드리지 않음" \
    || fail "query_fail_freezes_case_state: 실패인데 상태 변경 (before=$since_before after=$since_after)"
}

# 15. 연속 실패가 한계에 닿으면 판정 불가를 한 번 신고한다
test_query_fail_alerts_after_limit() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list_raw "$sd" '{"ok":false,"result":{"tasks":[]}}'
  seed_state "$sd" 0 0 0
  run_reporter "$sd"
  local n1; n1=$(count_matches '판정 불가' "$sd/project-sends.log")
  run_reporter "$sd"
  local n2; n2=$(count_matches '판정 불가' "$sd/project-sends.log")
  run_reporter "$sd"
  local n3; n3=$(count_matches '판정 불가' "$sd/project-sends.log")
  run_reporter "$sd"
  local n4; n4=$(count_matches '판정 불가' "$sd/project-sends.log")
  { [ "$n1" -eq 0 ] && [ "$n2" -eq 0 ] && [ "$n3" -eq 1 ] && [ "$n4" -eq 1 ]; } \
    && pass "query_fail_alerts_after_limit: 3회 연속 실패에 1번만 판정 불가 신고" \
    || fail "query_fail_alerts_after_limit: 신고 시점/횟수 어긋남 (n1=$n1 n2=$n2 n3=$n3 n4=$n4)"
}

# 16. 조회가 회복되면 실패 연속 횟수가 재장전된다
test_query_fail_rearm() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list_raw "$sd" '{"ok":false,"result":{"tasks":[]}}'
  seed_state "$sd" 0 0 0
  run_reporter "$sd"
  run_reporter "$sd"
  make_task_list "$sd" dispatched
  run_reporter "$sd"
  local streak; streak=$(state_field "$sd" CARD_QUERY_FAIL_STREAK)
  [ "$streak" = 0 ] \
    && pass "query_fail_rearm: 조회 성공하면 실패 연속 횟수 리셋" \
    || fail "query_fail_rearm: 리셋 안 됨 (streak=$streak)"
}

# 17. ok 필드가 아예 없는 응답도 못 믿는다 (fail-closed)
test_query_missing_ok_is_failure() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list_raw "$sd" '{"result":{"runId":"run_project","count":0,"tasks":[]}}'
  seed_state "$sd" 0 "$(($(date +%s) - 600))" 0
  run_reporter "$sd"
  local nb streak
  nb=$(count_matches '다음 카드를 요청하지 않고 있다' "$sd/project-sends.log")
  streak=$(state_field "$sd" CARD_QUERY_FAIL_STREAK)
  { [ "$nb" -eq 0 ] && [ "$streak" = 1 ]; } \
    && pass "query_missing_ok_is_failure: ok 없는 응답을 실패로 처리" \
    || fail "query_missing_ok_is_failure: ok 없는 응답을 믿음 (b=$nb streak=$streak)"
}

# 18. 줄 하나가 깨진 응답도 전체를 못 믿는다 (fail-closed)
test_query_malformed_row_is_failure() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list_raw "$sd" '{"ok":true,"result":{"runId":"run_project","count":2,"tasks":[{"id":"t1","status":"completed"},"oops"]}}'
  seed_state "$sd" 0 "$(($(date +%s) - 600))" 0
  run_reporter "$sd"
  local nb streak
  nb=$(count_matches '다음 카드를 요청하지 않고 있다' "$sd/project-sends.log")
  streak=$(state_field "$sd" CARD_QUERY_FAIL_STREAK)
  { [ "$nb" -eq 0 ] && [ "$streak" = 1 ]; } \
    && pass "query_malformed_row_is_failure: 깨진 줄이 섞이면 전체를 실패로 처리" \
    || fail "query_malformed_row_is_failure: 깨진 응답을 믿음 (b=$nb streak=$streak)"
}

# 19. 모르는 상태는 경우 C로 추정하지 않고 판정 불가로 보낸다
test_unknown_status_is_unavailable() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd" completed weird_new_status
  seed_state "$sd" 0 "$(($(date +%s) - 600))" "$(($(date +%s) - 600))"
  run_reporter "$sd"
  run_reporter "$sd"
  run_reporter "$sd"
  local na nb nc nu value next_action
  na=$(count_matches '발령을 안 하고 있다' "$sd/project-sends.log")
  nb=$(count_matches '다음 카드를 요청하지 않고 있다' "$sd/project-sends.log")
  nc=$(count_matches '미결 카드가 남았는데' "$sd/project-sends.log")
  nu=$(count_matches '판정 불가' "$sd/project-sends.log")
  value=$(count_matches '"classification":"unavailable"' "$sd/project-sends.log")
  next_action=$(count_matches '"nextAction":"remeasure"' "$sd/project-sends.log")
  { [ "$na" -eq 0 ] && [ "$nb" -eq 0 ] && [ "$nc" -eq 0 ] && [ "$nu" -ge 1 ] && [ "$value" -eq 1 ] && [ "$next_action" -eq 1 ]; } \
    && pass "unknown_status_is_unavailable: 정식 판정값 unavailable과 재측정 행동이 밖으로 나감" \
    || fail "unknown_status_is_unavailable: 판정값이 밖으로 안 나감 (a=$na b=$nb c=$nc unavailable=$nu value=$value remeasure=$next_action)"
}

# 20. 상태 미상과 조회 실패는 같은 판정 불가 사건 안에서도 원인과 원문 값이 구분된다
test_unknown_status_logs_value_and_reason() {
  local sd_unknown sd_query unknown_reason unknown_value query_reason
  sd_unknown=$(new_state); make_relay_log "$sd_unknown" normal
  make_task_list "$sd_unknown" completed weird_new_status
  seed_state "$sd_unknown" 0 0 0
  run_reporter "$sd_unknown"
  unknown_reason=$(count_matches 'card_classification=unavailable reason=unknown_status' "$sd_unknown/reporter-output.log")
  unknown_value=$(count_matches 'weird_new_status' "$sd_unknown/reporter-output.log")

  sd_query=$(new_state); make_relay_log "$sd_query" normal
  make_task_list_raw "$sd_query" '{"ok":false,"result":{"tasks":[]}}'
  seed_state "$sd_query" 0 0 0
  run_reporter "$sd_query"
  query_reason=$(count_matches 'reason=unusable_response' "$sd_query/reporter-output.log")
  { [ "$unknown_reason" -ge 1 ] && [ "$unknown_value" -ge 1 ] && [ "$query_reason" -ge 1 ]; } \
    && pass "unknown_status_logs_value_and_reason: 상태 미상 값과 조회 실패 원인을 구분해 기록" \
    || fail "unknown_status_logs_value_and_reason: 구분 로그 부족 (unknown_reason=$unknown_reason value=$unknown_value query_reason=$query_reason)"
}

# 21. 아는 상태 전체는 기존 A/B/C·정상 분류를 유지한다
test_known_statuses_still_classify() {
  local sd na nb nc nu
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd" pending ready dispatched blocked completed failed cancelled canceled skipped superseded
  seed_state "$sd" 0 0 0
  run_reporter "$sd"
  na=$(count_matches '발령을 안 하고 있다' "$sd/project-sends.log")
  nb=$(count_matches '다음 카드를 요청하지 않고 있다' "$sd/project-sends.log")
  nc=$(count_matches '미결 카드가 남았는데' "$sd/project-sends.log")
  nu=$(count_matches '판정 불가' "$sd/project-sends.log")
  { [ "$na" -eq 0 ] && [ "$nb" -eq 0 ] && [ "$nc" -eq 0 ] && [ "$nu" -eq 0 ]; } \
    && pass "known_statuses_still_classify: 아는 상태 전체를 정상 처리" \
    || fail "known_statuses_still_classify: 아는 상태가 오분류됨 (a=$na b=$nb c=$nc unavailable=$nu)"
}

# 22. 방어는 선택 인자가 아니다 — --board-idle-sec 없이도 작동한다
test_default_enabled_without_flag() {
  local sd
  sd=$(new_state)
  make_relay_log "$sd" normal
  make_task_list "$sd" completed blocked
  seed_state "$sd" 0 0 "$(($(date +%s) - 600))"
  run_reporter_no_flag "$sd"
  local n
  n=$(count_matches '미결 카드가 남았는데' "$sd/project-sends.log")
  [ "$n" -ge 1 ] \
    && pass "default_enabled_without_flag: --board-idle-sec 없이도 방어 작동" \
    || fail "default_enabled_without_flag: 플래그 없을 때 방어 미작동"
}

# === 실행 ===
echo "=== stall-reporter B7 시험 (대상: $REPORTER) ==="
bash -n "$REPORTER" || { echo "SYNTAX_FAIL $REPORTER"; exit 1; }

test_case_a_fires
test_case_b_fires
test_wording_differs
test_normal_dispatched
test_normal_below_threshold
test_normal_idle_recovered
test_flood_robust
test_rearm_after_dispatch
test_case_c_fires
test_case_c_not_folded_into_b
test_three_wordings_differ
test_case_c_rearm
test_query_ok_false_never_reports_empty
test_query_fail_freezes_case_state
test_query_fail_alerts_after_limit
test_query_fail_rearm
test_query_missing_ok_is_failure
test_query_malformed_row_is_failure
test_unknown_status_is_unavailable
test_unknown_status_logs_value_and_reason
test_known_statuses_still_classify
test_default_enabled_without_flag

echo ""
echo "결과: PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
