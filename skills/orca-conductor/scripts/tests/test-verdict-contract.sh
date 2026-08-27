#!/bin/bash
# 판정 문구와 종료 코드가 어긋나지 못한다 — 계약 시험.
#
# Why: 2026-08-09에 `scripts/validate.sh` 가 종료 코드 1로 끝났는데 화면 마지막 줄은
# `ALL HEADLESS TESTS PASSED` 였고 FAIL 표시가 하나도 없었다. 초록 글씨인데 빨간
# 신호였다. 원인은 구조적이다 — 검증 스크립트가 자기 판정을 안 찍었고, 중간 관문이
# `set -e` 로 조용히 죽으면 그 직전 도구의 초록 문구가 마지막 줄로 남았다.
#
# 그래서 이제 각 스크립트는 끝에서 반드시 자기 판정을 찍는다. 이 시험은 그 판정이
# 실제로 종료 코드를 따라가는지 본다: 스크립트 사본에 일부러 실패를 끼워 넣고,
# (1) 종료 코드가 0이 아니고 (2) 마지막 줄이 실패 문구인지 확인한다.
#
# 여기서 "마지막 줄"을 보는 것이 핵심이다. 실패 문구가 어딘가에 있기만 해서는 부족하다.
# 사고 때 문제는 초록 문구가 마지막에 남은 것이었다.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
REPO_ROOT=$(cd "$SKILL_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS %s\n' "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL %s\n' "$1" >&2; }

# 대상 스크립트를 복사해 판정 트랩을 건 바로 다음 줄에 실패를 끼워 넣는다.
# 무거운 관문은 하나도 돌지 않는다 — 끼워 넣은 실패에서 바로 죽기 때문이다.
inject_failure_after() {
  local src="$1" anchor="$2" dest="$3"
  python3 - "$src" "$anchor" "$dest" <<'PY'
import sys
src, anchor, dest = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src, encoding='utf-8').read().splitlines(keepends=True)
for i, line in enumerate(lines):
    if line.strip() == anchor:
        lines.insert(i + 1, 'false  # F-B7 계약 시험이 끼워 넣은 실패\n')
        open(dest, 'w', encoding='utf-8').write(''.join(lines))
        raise SystemExit(0)
raise SystemExit(f'ANCHOR_NOT_FOUND {anchor!r} in {src}')
PY
}

# $1 라벨 / $2 대상 스크립트 / $3 트랩 설치 줄 / $4 기대하는 실패 문구 앞머리
assert_verdict_matches_exit() {
  local label="$1" target="$2" anchor="$3" marker="$4"
  local work poisoned out status last

  work=$(mktemp -d /tmp/orca-verdict-contract.XXXXXX)
  poisoned="$work/$(basename "$target")"
  if ! inject_failure_after "$target" "$anchor" "$poisoned" 2>"$work/inject.err"; then
    fail "$label: 판정 트랩 설치 줄을 못 찾았다 ($(cat "$work/inject.err"))"
    return 0
  fi
  chmod +x "$poisoned"

  out="$work/out.log"
  bash "$poisoned" > "$out" 2>&1
  status=$?

  if [ "$status" -eq 0 ]; then
    fail "$label: 실패를 끼워 넣었는데 종료 코드가 0이다"
    return 0
  fi
  last=$(tail -n 1 "$out")
  case "$last" in
    "$marker"*)
      pass "$label: 종료 코드 $status + 마지막 줄이 실패 판정 ($last)" ;;
    *)
      fail "$label: 종료 코드는 $status 인데 마지막 줄이 실패 판정이 아니다 (마지막 줄=${last:-빈 줄})" ;;
  esac
}

# 판정 문구가 종료 코드와 같은 자리에서 나오는지(=따로 놀 수 없는지) 구조로도 확인한다.
assert_verdict_bound_to_exit_code() {
  local label="$1" target="$2" fn="$3"
  if rg -q "^\s*trap $fn EXIT" "$target" && rg -q 'exit "\$rc"' "$target"; then
    pass "$label: 판정이 EXIT 트랩에 걸려 있고 받은 종료 코드를 그대로 돌려준다"
  else
    fail "$label: 판정이 종료 코드에 묶여 있지 않다 (EXIT 트랩 또는 exit \"\$rc\" 없음)"
  fi
}

echo "=== 판정 문구 / 종료 코드 일치 계약 시험 ==="

assert_verdict_matches_exit \
  "validate.sh" \
  "$REPO_ROOT/scripts/validate.sh" \
  "trap validate_verdict EXIT" \
  "VALIDATE FAILED"

assert_verdict_matches_exit \
  "test-conductor-companion.sh" \
  "$SCRIPT_DIR/test-conductor-companion.sh" \
  "trap companion_suite_verdict EXIT" \
  "FAIL test-conductor-companion.sh"

assert_verdict_matches_exit \
  "test-conductor-companion-state.sh" \
  "$SCRIPT_DIR/test-conductor-companion-state.sh" \
  "trap state_suite_verdict EXIT" \
  "FAIL test-conductor-companion-state.sh"

# 부르는 파일이 빠졌을 때(종료 127 부류) 검증이 명확한 메시지와 함께 떨어지는지 본다.
#
# Why: 2026-08-09 체크포인트 272a856 은 시험 파일 11개를 부르는데 10개만 커밋돼 있었다.
# 깨끗한 복제본에서는 `No such file or directory` 로 종료 127 인데, 그 오류가 stderr 로만
# 새고 화면 마지막 줄은 직전 시험의 초록 문구였다. 없는 파일을 부른 것과 시험이 떨어진
# 것이 화면에서 구분되지 않았다.
#
# 여기서는 validate.sh 사본의 SKILL_ROOT 를 빈 폴더로 돌려 "부르는 파일이 전부 없는"
# 상태를 만든다. 무거운 관문은 하나도 안 돈다 — preflight 에서 먼저 죽기 때문이다.
assert_missing_file_is_named() {
  local work poisoned empty_root out status last missing_lines
  work=$(mktemp -d /tmp/orca-verdict-missing.XXXXXX)
  empty_root="$work/빈-스킬-폴더"
  mkdir -p "$empty_root/scripts" "$work/scripts"
  # B10 등록 대조는 통과시키고, 그 다음 기존 preflight가 시험 외 필수 파일의
  # 부재를 이름으로 잡는지 본다. 시험 진입점 목록까지 비우면 새 앞단 검사만 재게 된다.
  cp -R "$SCRIPT_DIR" "$empty_root/scripts/tests"
  cp "$REPO_ROOT/scripts/check-test-registration.sh" "$work/scripts/check-test-registration.sh"
  # F-B10-2: 관문은 시험을 helper 를 통해서만 돌린다. 사본에도 helper 가 있어야
  # "helper 가 없다"가 아니라 원래 보려던 preflight 가 재게 된다.
  cp "$REPO_ROOT/scripts/run-registered-test.sh" "$work/scripts/run-registered-test.sh"
  poisoned="$work/scripts/validate.sh"
  sed 's|^SKILL_ROOT="\$REPO_ROOT/skills/orca-conductor"$|SKILL_ROOT="'"$empty_root"'"|' \
    "$REPO_ROOT/scripts/validate.sh" > "$poisoned"
  if ! rg -q "^SKILL_ROOT=\"$empty_root\"$" "$poisoned"; then
    fail "missing_file_named: SKILL_ROOT 치환에 실패했다(대상 줄이 바뀌었나)"
    return 0
  fi
  chmod +x "$poisoned"

  out="$work/out.log"
  bash "$poisoned" > "$out" 2>&1
  status=$?

  if [ "$status" -eq 0 ]; then
    fail "missing_file_named: 부르는 파일이 전부 없는데 종료 코드가 0이다"
    return 0
  fi
  # MISSING_FILE 은 stdout·stderr 양쪽에 찍히므로 같은 경로가 두 번 나온다.
  # 사람에게 보고할 숫자는 "없는 파일 수"여야 하니 경로 기준으로 센다.
  missing_lines=$(rg -o '^MISSING_FILE \S+' "$out" 2>/dev/null | sort -u | grep -c . || printf '0')
  last=$(tail -n 1 "$out")
  if [ "$missing_lines" -lt 1 ]; then
    fail "missing_file_named: 없는 파일을 이름으로 말하지 않았다 (MISSING_FILE 줄 $missing_lines개)"
    return 0
  fi
  case "$last" in
    "VALIDATE FAILED"*)
      pass "missing_file_named: 없는 파일 ${missing_lines}개를 이름으로 말하고 마지막 줄이 실패 판정 ($last)" ;;
    *)
      fail "missing_file_named: MISSING_FILE 은 찍혔는데 마지막 줄이 실패 판정이 아니다 (마지막 줄=${last:-빈 줄})" ;;
  esac
}

assert_missing_file_is_named

# B10(2026-08-09) + F-B10-2(2026-08-10): 새 시험 파일이 생겼는데 이번 관문에서 실제로
# 돌지도 않고 이유 있는 예외도 아니면, 그 파일 이름으로 실패해야 한다.
#
# F-B10-2: 판정 근거가 "관문 본문에 이름이 보이는가"에서 "실행 원장에 있는가"로 바뀌었다.
# 그래서 이 시험은 진짜 시험 폴더 사본 + 진짜 validate.sh 사본에, 새 파일 하나만 빠진
# 실행 원장을 붙여 --settle 을 부른다. 원장에 넣을 이름 목록은 폴더에서 뽑고 예외 이름은
# validate.sh 에서 뽑는다 — 따로 적어 두면 그 목록이 또 어긋난다.
#
# $1 라벨 / $2 새 파일도 원장에 넣을지(yes|no) / $3 기대 종료 코드
assert_settle_sees_new_test() {
  local label="$1" record_new="$2" want_status="$3"
  local work copied_tests poisoned ledger token out status last named new_name proof

  work=$(mktemp -d /tmp/orca-verdict-unregistered.XXXXXX)
  copied_tests="$work/tests"
  cp -R "$SCRIPT_DIR" "$copied_tests"
  new_name="test-b10-unregistered.sh"
  printf '#!/bin/bash\nexit 0\n' > "$copied_tests/$new_name"

  poisoned="$work/validate.sh"
  cp "$REPO_ROOT/scripts/validate.sh" "$poisoned"

  token="tok-focused-settle-4b7e1d"
  ledger="$work/ledger.tsv"
  : > "$ledger"
  sed -nE 's/^# TEST_GATE_EXCEPTION:[[:space:]]*([^ |]+).*$/\1/p' "$poisoned" \
    | sort -u > "$work/exception-names.txt"
  find "$copied_tests" -maxdepth 1 -type f \
    \( -name 'test-*.sh' -o -name 'test_*.py' -o -name '*-test.sh' \) \
    -exec basename {} \; | sort -u \
    | grep -vxF -f "$work/exception-names.txt" > "$work/should-run.txt"
  if [ "$record_new" = no ]; then
    grep -vxF "$new_name" "$work/should-run.txt" > "$work/recorded.txt"
  else
    cp "$work/should-run.txt" "$work/recorded.txt"
  fi
  # F-B10-3: 증인 줄의 첫 칸은 표 원본이 아니라 지문이다. 계산식을 여기 베끼면
  # 언젠가 한쪽만 바뀌므로, 관문이 쓰는 그 계산기를 그대로 부른다.
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    proof=$(bash "$REPO_ROOT/scripts/check-test-registration.sh" \
      --witness-proof "$token" "$name" "$copied_tests/$name")
    printf '%s\t%s\t%s\n' "$proof" "$name" "$copied_tests/$name" >> "$ledger"
  done < "$work/recorded.txt"

  out="$work/out.log"
  set +e
  bash "$REPO_ROOT/scripts/check-test-registration.sh" --settle \
    "$copied_tests" "$poisoned" "$ledger" "$token" > "$out" 2>&1
  status=$?
  set -e

  if [ "$status" -ne "$want_status" ]; then
    fail "$label: 종료 코드가 $want_status 이어야 하는데 $status 다 ($(tail -n 1 "$out"))"
    return 0
  fi
  last=$(tail -n 1 "$out")
  if [ "$want_status" -eq 0 ]; then
    case "$last" in
      "TEST_REGISTRATION PASSED"*)
        pass "$label: 새 시험이 실제로 돌았으면 통과한다" ;;
      *)
        fail "$label: 종료는 0인데 마지막 줄이 통과 판정이 아니다 (마지막 줄=${last:-빈 줄})" ;;
    esac
    return 0
  fi
  named=$(rg -c "^UNREGISTERED_TEST $new_name " "$out" 2>/dev/null || printf '0')
  if [ "$named" -ne 1 ]; then
    fail "$label: 미등록 시험 이름을 정확히 1번 말하지 않았다 (줄=$named)"
    return 0
  fi
  case "$last" in
    "TEST_REGISTRATION 실패:"*)
      pass "$label: $new_name 이름을 대고 관문을 닫는다" ;;
    *)
      fail "$label: 이름은 나왔지만 마지막 줄이 실패 판정이 아니다 (마지막 줄=${last:-빈 줄})" ;;
  esac
}

assert_settle_sees_new_test "unregistered_test_named" no 1
assert_settle_sees_new_test "executed_new_test_accepted" yes 0

# F-B10-2(2026-08-10): "이 시험이 관문에서 돌았다"를 글자가 아니라 실행으로만 인정한다.
#
# Why: 같은 자리에서 우회가 세 번 났다. R-B10은 주석 한 줄과 공백뿐인 예외 이유로
# 관문을 초록불로 만들었고, R-F-B10은 그것을 막은 셸 문법 흉내 추출기마저 뚫었다 —
# 실행되지 않는 `false && bash ...` 와 heredoc 본문이 호출로 둔갑했고, 반대로
# 실제로 도는 `LC_ALL=C bash ...`, `if bash ...`, `! bash ...` 는 놓쳤다.
# 셸 표면 문법을 반쯤 흉내 내는 한 이 목록은 끝나지 않는다.
#
# 그래서 이제 시험은 run-registered-test.sh 를 통해서만 돌고, 그 helper 가 실행 직전에
# 실행 원장에 적는다. 관문 끝의 --settle 이 그 원장으로 판정한다. 아래 사례들은 진짜
# 관문 대신 같은 구조의 작은 가짜 관문을 만들어, 본문을 실제로 돌린 뒤 판정을 본다.
# 무거운 시험은 하나도 돌지 않는다.
#
# $1 라벨 / $2 만들 시험 파일 이름들(공백 구분) / $3 가짜 관문 본문
# / $4 기대 종료 코드 / $5 출력에 반드시 있어야 할 문구(없으면 빈 문자열)
# / $6 시험이 실제로 돌았어야 하는가(yes|no, 첫 시험 이름 기준)
assert_witness_case() {
  local label="$1" test_names="$2" body="$3" want_status="$4" want_marker="$5" want_ran="$6"
  local work tests fake out status ran name first

  work=$(mktemp -d /tmp/orca-witness-case.XXXXXX)
  tests="$work/scripts/tests"
  mkdir -p "$tests"
  # 시험은 실행되면 자기 이름의 marker 를 남긴다. 종료 코드나 셸 문법과 무관하게
  # "정말 돌았는가"를 사실로 잰다.
  for name in $test_names; do
    printf '#!/bin/bash\nprintf ran > "%s/marker.%s"\nexit 0\n' "$work" "$name" > "$tests/$name"
    chmod +x "$tests/$name"
  done
  first=${test_names%% *}

  fake="$work/validate.sh"
  {
    printf '#!/bin/bash\n'
    printf 'set -uo pipefail\n'
    printf 'SKILL_ROOT="%s"\n' "$work"
    printf 'RUN_TEST="%s/scripts/run-registered-test.sh"\n' "$REPO_ROOT"
    printf 'export ORCA_TEST_DIR="$SKILL_ROOT/scripts/tests"\n'
    printf 'export ORCA_TEST_LEDGER="%s/ledger.tsv"\n' "$work"
    printf 'export ORCA_TEST_LEDGER_TOKEN="tok-%s-9c4f"\n' "$label"
    printf ': > "$ORCA_TEST_LEDGER"\n'
    printf '%s\n' "$body"
    printf 'bash "%s/scripts/check-test-registration.sh" --settle \\\n' "$REPO_ROOT"
    printf '  "$ORCA_TEST_DIR" "$0" "$ORCA_TEST_LEDGER" "$ORCA_TEST_LEDGER_TOKEN"\n'
  } > "$fake"

  out="$work/out.log"
  set +e
  bash "$fake" > "$out" 2>&1
  status=$?
  set -e

  if [ -f "$work/marker.$first" ]; then ran=yes; else ran=no; fi

  if [ "$status" -ne "$want_status" ]; then
    fail "$label: 종료 코드가 $want_status 이어야 하는데 $status 다 ($(tail -n 1 "$out"))"
    return 0
  fi
  if [ -n "$want_marker" ] && ! rg -q -F -- "$want_marker" "$out"; then
    fail "$label: 종료 코드는 맞는데 '$want_marker' 를 말하지 않았다"
    return 0
  fi
  if [ "$ran" != "$want_ran" ]; then
    fail "$label: 시험 실제 실행이 $want_ran 여야 하는데 $ran 다"
    return 0
  fi
  pass "$label: 종료 $status · 실제실행 $ran${want_marker:+ · '$want_marker'}"
}

# R-F-B10 중요 1 — 실행되지 않는 죽은 분기와 heredoc 본문은 실행이 아니다.
assert_witness_case \
  "dead_branch_rejected" "test-b10-dead.sh" \
  'false && bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-dead.sh"' \
  1 'UNREGISTERED_TEST test-b10-dead.sh' no
assert_witness_case \
  "heredoc_body_rejected" "test-b10-heredoc.sh" \
  'cat <<EOF
bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-heredoc.sh"
EOF' \
  1 'UNREGISTERED_TEST test-b10-heredoc.sh' no

# R-F-B10 중요 2 — 실제로 도는 호출은 앞에 무슨 문법이 붙어도 인정한다.
assert_witness_case \
  "env_prefix_accepted" "test-b10-env.sh" \
  'LC_ALL=C bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-env.sh"' \
  0 'TEST_REGISTRATION PASSED' yes
assert_witness_case \
  "if_prefix_accepted" "test-b10-if.sh" \
  'if bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-if.sh"; then :; fi' \
  0 'TEST_REGISTRATION PASSED' yes
assert_witness_case \
  "bang_prefix_accepted" "test-b10-bang.sh" \
  '! bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-bang.sh"' \
  0 'TEST_REGISTRATION PASSED' yes

# R-B10 중요 1 — 주석에만 적힌 경로는 실행이 아니다. 실제 실행 대조군은 통과해야 한다.
assert_witness_case \
  "comment_only_call_rejected" "test-b10-comment.sh" \
  '# bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-comment.sh"' \
  1 'UNREGISTERED_TEST test-b10-comment.sh' no
assert_witness_case \
  "trailing_comment_call_rejected" "test-b10-tail.sh" \
  'true  # bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-tail.sh"' \
  1 'UNREGISTERED_TEST test-b10-tail.sh' no
assert_witness_case \
  "real_call_accepted" "test-b10-real.sh" \
  'bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-real.sh"' \
  0 'TEST_REGISTRATION PASSED' yes

# R-B10 중요 2 — 이유 칸은 공백을 걷어내고도 남아야 한다.
assert_witness_case \
  "whitespace_reason_rejected" "test-b10-real.sh test-b10-ws.sh" \
  'bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-real.sh"
# TEST_GATE_EXCEPTION: test-b10-ws.sh |  ' \
  1 'EMPTY_EXCEPTION_REASON test-b10-ws.sh' yes
assert_witness_case \
  "blank_reason_rejected" "test-b10-real.sh test-b10-blank.sh" \
  'bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-real.sh"
# TEST_GATE_EXCEPTION: test-b10-blank.sh |' \
  1 'EMPTY_EXCEPTION_REASON test-b10-blank.sh' yes
assert_witness_case \
  "explicit_reason_accepted" "test-b10-real.sh test-b10-exp.sh" \
  'bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-real.sh"
# TEST_GATE_EXCEPTION: test-b10-exp.sh | 단독 96초짜리 느린 회귀라 별도 느린 관문이 필요하다.' \
  0 'TEST_REGISTRATION PASSED' yes

# F-B10-2 — 실행 원장 자체를 노린 위조는 초록불이 되지 못한다.
assert_witness_case \
  "stale_witness_reuse_rejected" "test-b10-stale.sh" \
  'printf "%s\t%s\t%s\n" "tok-이전실행-000000" "test-b10-stale.sh" "$ORCA_TEST_DIR/test-b10-stale.sh" >> "$ORCA_TEST_LEDGER"' \
  1 'WITNESS_FOREIGN_RUN' no
assert_witness_case \
  "foreign_witness_mixed_rejected" "test-b10-real.sh test-b10-other.sh" \
  'bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-real.sh"
printf "%s\t%s\t%s\n" "tok-다른판-999999" "test-b10-other.sh" "$ORCA_TEST_DIR/test-b10-other.sh" >> "$ORCA_TEST_LEDGER"' \
  1 'WITNESS_FOREIGN_RUN' yes
assert_witness_case \
  "named_but_never_run_rejected" "test-b10-namedonly.sh" \
  ':' \
  1 'UNREGISTERED_TEST test-b10-namedonly.sh' no
assert_witness_case \
  "fake_runner_rejected" "test-b10-real.sh" \
  'bash "$RUN_TEST" true "$ORCA_TEST_DIR/test-b10-real.sh"' \
  1 'WITNESS_FAILED' no
assert_witness_case \
  "missing_test_file_named" "test-b10-real.sh" \
  'bash "$RUN_TEST" sh "$ORCA_TEST_DIR/test-b10-없는파일.sh"' \
  1 'MISSING_FILE' no

# F-B10-3(2026-08-10): 증인을 적는 권한은 시험 자식에게 넘어가지 않는다.
#
# Why: R-F-B10-2가 실측했다. 시험 자식이 원장 경로와 표를 환경변수로 물려받아,
# 실행하지도 않은 형제 시험의 증인을 올바른 표로 한 줄 적었다. 형제 3개가 0회 실행인데
# 관문 전체가 종료 0 초록불이 됐다. "시험이 실제로 돌았는가"라는 관문의 핵심 약속이
# 자식 앞에서만 무너지는 상태였다.
#
# 아래 사례들은 위 assert_witness_case 와 달리 공격 코드를 관문 본문이 아니라
# 시험 파일 안에 넣는다. 자식의 자리에서 두드려야 자식이 닿을 수 있는 통로가 보인다.
#
# $1 라벨 / $2 만들 시험 이름들(첫 개가 공격자) / $3 공격자 본문
# / $4 관문이 helper 로 부를 시험 이름들 / $5 기대 종료 코드
# / $6 출력에 반드시 있어야 할 문구 / $7 실제로 돌았어야 할 시험 개수
assert_child_witness_case() {
  local label="$1" names="$2" attack="$3" called="$4"
  local want_status="$5" want_marker="$6" want_ran="$7"
  local work tests fake out status name attacker ran=0

  work=$(mktemp -d /tmp/orca-child-witness.XXXXXX)
  tests="$work/scripts/tests"
  mkdir -p "$tests"
  attacker=${names%% *}

  for name in $names; do
    if [ "$name" = "$attacker" ]; then
      # 공격자에게는 최악을 가정해 준다: 원장 파일 경로는 이미 알아냈다고 치고
      # (실제로도 /tmp 훑기로 알아낼 수 있다), helper 경로도 손에 쥐여 준다.
      # 그래도 형제 증인을 만들 수 없어야 한다.
      {
        printf '#!/bin/bash\n'
        printf 'WORK=%s\n' "$work"
        printf 'TESTS=%s\n' "$tests"
        printf 'LEDGER_HINT="$WORK/ledger.tsv"\n'
        printf 'RUN_TEST=%s\n' "$REPO_ROOT/scripts/run-registered-test.sh"
        printf 'printf ran > "$WORK/marker.%s"\n' "$name"
        printf '%s\n' "$attack"
      } > "$tests/$name"
    else
      printf '#!/bin/bash\nprintf ran > "%s/marker.%s"\nexit 0\n' "$work" "$name" > "$tests/$name"
    fi
    chmod +x "$tests/$name"
  done

  fake="$work/validate.sh"
  {
    printf '#!/bin/bash\n'
    printf 'set -uo pipefail\n'
    printf 'export ORCA_TEST_DIR="%s"\n' "$tests"
    printf 'export ORCA_TEST_LEDGER="%s/ledger.tsv"\n' "$work"
    printf 'export ORCA_TEST_LEDGER_TOKEN="tok-%s-3f7a"\n' "$label"
    printf ': > "$ORCA_TEST_LEDGER"\n'
    for name in $called; do
      printf 'bash "%s/scripts/run-registered-test.sh" sh "$ORCA_TEST_DIR/%s"\n' "$REPO_ROOT" "$name"
    done
    printf 'bash "%s/scripts/check-test-registration.sh" --settle \\\n' "$REPO_ROOT"
    printf '  "$ORCA_TEST_DIR" "$0" "$ORCA_TEST_LEDGER" "$ORCA_TEST_LEDGER_TOKEN"\n'
  } > "$fake"

  out="$work/out.log"
  set +e
  bash "$fake" > "$out" 2>&1
  status=$?
  set -e

  for name in $names; do
    [ -f "$work/marker.$name" ] && ran=$(( ran + 1 ))
  done

  if [ "$status" -ne "$want_status" ]; then
    fail "$label: 종료 코드가 $want_status 이어야 하는데 $status 다 ($(tail -n 1 "$out"))"
    return 0
  fi
  if [ -n "$want_marker" ] && ! rg -q -F -- "$want_marker" "$out"; then
    fail "$label: 종료 코드는 맞는데 '$want_marker' 를 말하지 않았다"
    return 0
  fi
  if [ "$ran" -ne "$want_ran" ]; then
    fail "$label: 실제로 돈 시험이 ${want_ran}개여야 하는데 ${ran}개다"
    return 0
  fi
  pass "$label: 종료 $status · 실제실행 ${ran}개${want_marker:+ · '$want_marker'}"
}

# 자식 눈에 원장 환경이 실제로 비어 있는지. 하나라도 남아 있으면 공격자가 종료 9로
# 죽고 증인이 없어 관문이 떨어진다 — 즉 이 사례가 통과했다는 건 셋 다 비었다는 뜻이다.
assert_child_witness_case \
  "child_ledger_env_stripped" "test-b103-probe.sh" \
  '[ -z "${ORCA_TEST_LEDGER:-}${ORCA_TEST_LEDGER_TOKEN:-}${ORCA_TEST_DIR:-}" ] || exit 9
exit 0' \
  "test-b103-probe.sh" 0 'TEST_REGISTRATION PASSED' 1

# R-F-B10-2 중요 1 원본: 상속받은 표로 형제 증인을 지어낸다.
assert_child_witness_case \
  "sibling_forgery_rejected" "test-b103-forger.sh test-b103-sib.sh" \
  'printf "%s\t%s\t%s\n" "${ORCA_TEST_LEDGER_TOKEN:-}" "test-b103-sib.sh" "${ORCA_TEST_DIR:-}/test-b103-sib.sh" >> "${ORCA_TEST_LEDGER:-/dev/null}"
exit 0' \
  "test-b103-forger.sh" 1 'UNREGISTERED_TEST test-b103-sib.sh' 1

# 원장 파일 자체를 찾아낸 자식이 남의 줄 지문을 베껴 이름만 바꾼다.
assert_child_witness_case \
  "ledger_path_known_forgery_rejected" \
  "test-b103-copier.sh test-b103-real.sh test-b103-sib.sh" \
  'first=$(head -n 1 "$LEDGER_HINT" | cut -f1)
printf "%s\t%s\t%s\n" "$first" "test-b103-sib.sh" "$TESTS/test-b103-sib.sh" >> "$LEDGER_HINT"
exit 0' \
  "test-b103-real.sh test-b103-copier.sh" 1 'WITNESS_FOREIGN_RUN' 2

# 자식이 helper 를 직접 불러 형제 증인을 만들려 해도, 원장 환경이 없어 helper 가 막는다.
assert_child_witness_case \
  "child_helper_api_rejected" "test-b103-api.sh test-b103-sib.sh" \
  'bash "$RUN_TEST" sh "$TESTS/test-b103-sib.sh" > "$WORK/api.log" 2>&1
exit 0' \
  "test-b103-api.sh" 1 'UNREGISTERED_TEST test-b103-sib.sh' 1

# 떨어진 시험은 증인을 남기지 않는다. 증인은 성공으로 돌아온 뒤에만 붙는다.
assert_child_witness_case \
  "failed_child_leaves_no_witness" "test-b103-fail.sh" \
  'exit 3' \
  "test-b103-fail.sh" 1 'UNREGISTERED_TEST test-b103-fail.sh' 1

# R-F-B10-2 사소 1: 형제가 원장을 비우려 해도 돈 시험의 증인이 사라지지 않는다.
# 자식에게 원장 경로를 주지 않으므로 이 손짓은 헛손질이 된다.
assert_child_witness_case \
  "sibling_truncate_no_false_alarm" "test-b103-wipe.sh test-b103-mate.sh" \
  ': > "${ORCA_TEST_LEDGER:-$WORK/헛손질.tsv}"
exit 0' \
  "test-b103-wipe.sh test-b103-mate.sh" 0 'TEST_REGISTRATION PASSED' 2

assert_verdict_bound_to_exit_code "validate.sh" "$REPO_ROOT/scripts/validate.sh" validate_verdict
assert_verdict_bound_to_exit_code "test-conductor-companion.sh" "$SCRIPT_DIR/test-conductor-companion.sh" companion_suite_verdict
assert_verdict_bound_to_exit_code "test-conductor-companion-state.sh" "$SCRIPT_DIR/test-conductor-companion-state.sh" state_suite_verdict

echo ""
echo "결과: PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
