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

# I-B7-MAIN 범위: companion 계열 verdict 계약(companion_suite_verdict / state_suite_verdict)은
# companion 본체 통합(별개 카드)까지 보류한다. companion 본체가 main에 없어 지금 검사하면
# 항상 실패한다. 이 카드에서는 판 비움 사슬과 함께 들어온 validate.sh 판정 계약만 검사한다.

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
  mkdir -p "$empty_root"
  poisoned="$work/validate.sh"
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

assert_verdict_bound_to_exit_code "validate.sh" "$REPO_ROOT/scripts/validate.sh" validate_verdict

echo ""
echo "결과: PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
