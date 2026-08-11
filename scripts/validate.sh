#!/bin/bash
set -euo pipefail
# -E(errtrace): ERR 트랩은 함수 안에서 상속되지 않는다. 켜지 않으면
# 실패한 줄과 명령이 "불명"으로 나와 판정 문구가 반쪽이 된다.
set -E

# F-B7(2026-08-09): 종료 코드와 화면 문구가 어긋나지 못하게 만든다.
#
# Why: 2026-08-09에 이 스크립트가 종료 코드 1로 끝났는데 화면 마지막 줄은
# `ALL HEADLESS TESTS PASSED` 였고 FAIL 표시가 하나도 없었다. 초록 글씨인데 빨간
# 신호였다. 원인은 구조적이다 — 이 스크립트는 자기 판정 문구를 아예 찍지 않았고,
# 마지막에 보이던 `All checks passed!` / `0 errors, 0 warnings, 0 notes` 는
# ruff·basedpyright 가 자기 몫에 대해 찍는 말이었다. 그래서 중간 관문이 `set -e` 로
# 조용히 죽으면 그 직전 도구의 초록 문구가 마지막 줄로 남았다.
#
# 이제 이 스크립트는 끝에서 반드시 자기 판정을 찍는다. 통과면 VALIDATE PASSED,
# 실패면 어느 줄에서 어떤 명령이 몇 번으로 죽었는지까지 VALIDATE FAILED 로 찍는다.
# 판정 문구는 종료 코드와 같은 자리에서 나오므로 둘이 어긋날 수 없다.
VALIDATE_FAIL_LINE=""
VALIDATE_FAIL_CMD=""
trap 'VALIDATE_FAIL_LINE=$LINENO; VALIDATE_FAIL_CMD=$BASH_COMMAND' ERR
# F-I-COMPANION-MAIN-2(2026-08-11): 성공 판정을 정산 완료 영수증에 묶는다.
#
# Why: R-F-I-COMPANION-MAIN이 실측했다. 이 파일 마지막의 --settle 두 줄을 지운 사본이
# 종료 0과 VALIDATE PASSED 로 살아남았다. 판정이 종료 코드만 보고 있어서, 정산을 아예
# 부르지 않으면 "실패한 명령"이 없어 초록불이 됐다. 등록 관문 전체가 두 줄 삭제로
# 우회 가능한 상태였다.
#
# 이제 성공 판정은 이번 실행의 표에 묶인 완료 영수증을 확인해야만 나온다. 영수증이
# 없거나(정산이 안 돌았다), 표가 다르거나(이전 실행·형제 실행의 영수증이다), 내용이
# 어긋나면 그 자리에서 종료 1로 뒤집는다.
require_settle_receipt() {
  bash "${REPO_ROOT:-.}/scripts/check-test-registration.sh" --verify-receipt \
    "${ORCA_VALIDATE_RECEIPT:-}" "${ORCA_TEST_LEDGER_TOKEN:-}"
}
validate_verdict() {
  local rc=$?
  if [ "$rc" -eq 0 ] && ! require_settle_receipt; then
    rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    printf 'VALIDATE PASSED exit=0 (모든 관문 통과)\n'
  else
    printf 'VALIDATE FAILED exit=%s line=%s cmd=%s\n' \
      "$rc" "${VALIDATE_FAIL_LINE:-불명}" "${VALIDATE_FAIL_CMD:-불명}" >&2
    printf 'VALIDATE FAILED exit=%s line=%s cmd=%s\n' \
      "$rc" "${VALIDATE_FAIL_LINE:-불명}" "${VALIDATE_FAIL_CMD:-불명}"
  fi
  exit "$rc"
}
trap validate_verdict EXIT

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SKILL_ROOT="$REPO_ROOT/skills/orca-conductor"

# F-I-COMPANION-MAIN-2: 완료 영수증 배선이 이 파일 안에 실제로 남아 있는지 먼저 본다.
#
# Why: 영수증은 "정산이 이번 실행에서 성공했다"를 증명하지만, 확인하는 줄 자체를 지우면
# 그 증명이 아무 데도 쓰이지 않는다. 그래서 관문 시작에서 세 자리를 함께 센다 —
# 정산 호출, 성공 판정이 부르는 영수증 확인, 확인 실패를 종료 코드로 옮기는 줄.
# 셋 중 하나라도 빠지면 무거운 관문을 돌기 전에 등록 이름으로 막는다.
settle_wiring_selfcheck() {
  local self="$1" broken=0 settle_call verdict_region
  settle_call=$(sed -n '/^bash .*--settle/,/[^\\]$/p' "$self")
  verdict_region=$(sed -n '/^validate_verdict() {$/,/^}$/p' "$self")

  if [ -z "$settle_call" ]; then
    printf 'TEST_REGISTRATION_SETTLE_MISSING 정산 호출(--settle)이 관문에서 사라졌다\n' >&2
    broken=1
  elif ! printf '%s' "$settle_call" | grep -qF 'ORCA_VALIDATE_RECEIPT'; then
    printf 'TEST_REGISTRATION_SETTLE_MISSING 정산 호출이 완료 영수증 자리를 넘기지 않는다\n' >&2
    broken=1
  fi
  if ! printf '%s' "$verdict_region" | grep -qF 'require_settle_receipt'; then
    printf 'TEST_REGISTRATION_SETTLE_MISSING 성공 판정이 완료 영수증 확인을 부르지 않는다\n' >&2
    broken=1
  elif ! printf '%s' "$verdict_region" | grep -qF 'rc=1'; then
    printf 'TEST_REGISTRATION_SETTLE_MISSING 영수증 확인이 실패해도 성공 판정이 바뀌지 않는다\n' >&2
    broken=1
  fi
  if [ "$broken" -ne 0 ]; then
    printf 'TEST_REGISTRATION_SETTLE_MISSING 위 배선을 되돌려라(등록 관문이 통째로 우회된다)\n' >&2
    return 1
  fi
  printf 'SETTLE_WIRING 정산 호출·영수증 확인·성공 판정 3자리 확인\n'
}
settle_wiring_selfcheck "$0"

# F-B7(2026-08-09): 부르는 파일이 실제로 있는지 먼저 센다.
#
# Why: 2026-08-09에 체크포인트 272a856 에서 이 스크립트가 종료 코드 127 로 끝났다.
# 이 스크립트는 시험 파일 11개를 부르는데 그 커밋에는 10개만 들어 있었다 —
# `test-stall-reporter.sh` 는 부르는 줄만 커밋되고 파일이 빠졌다. 그러면
# `No such file or directory` 가 stderr 로만 새고, 화면에는 직전 시험의 초록 문구가
# 남는다. 없는 파일을 부른 것과 시험이 떨어진 것이 화면에서 구분되지 않았다.
#
# 그래서 무거운 관문을 돌기 전에 "부를 파일"을 전부 세어 확인한다. 목록은 이 스크립트
# 자신에서 뽑는다 — 따로 적어 두면 그 목록이 또 어긋난다(이번 사고가 정확히 목록과
# 실물이 어긋난 사고다).
preflight_called_files() {
  local self="$1" path total=0 missing=0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    total=$(( total + 1 ))
    if [ ! -f "$path" ]; then
      printf 'MISSING_FILE %s (부르는 줄은 있는데 파일이 없다)\n' "$path" >&2
      printf 'MISSING_FILE %s (부르는 줄은 있는데 파일이 없다)\n' "$path"
      missing=$(( missing + 1 ))
    fi
  done < <(grep -oE '\$SKILL_ROOT/[A-Za-z0-9_./-]+\.(sh|py|json)' "$self" \
             | sed "s|\$SKILL_ROOT|$SKILL_ROOT|" | sort -u)
  printf 'PREFLIGHT 부르는 파일 %s개 확인 · 없는 파일 %s개\n' "$total" "$missing"
  if [ "$missing" -ne 0 ]; then
    printf 'PREFLIGHT 실패: 없는 파일 %s개. 커밋에 파일이 빠졌는지 확인하라.\n' "$missing" >&2
    return 1
  fi
  if [ "$total" -eq 0 ]; then
    printf 'PREFLIGHT 실패: 부를 파일을 한 개도 못 찾았다(목록 추출이 깨졌다).\n' >&2
    return 1
  fi
}
preflight_called_files "$0"

# F-I-COMPANION-MAIN(2026-08-11): 시험이 "글자로 적혀 있다"가 아니라 "실제로 돌았다"로
# 증명되게 만든다. R-I-COMPANION-MAIN이 실측했다 — companion 시험 호출 한 줄을 빼도
# 선재 routing 실패 7건에 가려 VALIDATE PASSED exit=0 으로 살아남았다. 검사 부품
# (check-test-registration.sh·run-registered-test.sh)는 있었으나 전체 검증 배선이 없었다.
#
# 시험은 전부 run-registered-test.sh 를 통해서만 돈다. helper는 시험을 실행 직전에
# 실행 원장(append-only)에 증인 줄을 적고, 자식에게 원장 환경을 넘기지 않아 형제 증인
# 위조를 구조로 막는다. 관문 끝에서 check-test-registration.sh --settle 이 원장과 시험
# 진입점 목록을 대조해 "적혀만 있고 안 돈 시험"을 이름으로 잡는다. declare 는 관문
# 시작에 예외 선언의 형식·이유만 보고, settle 은 성공을 주장하려는 순간 실제 실행과 대조한다.
#
# dispatch-safe-test.sh·test_luna_max_routing.py는 이 판이 들어오기 전부터 validate.sh
# 에서 돌지 않던 회귀다. F-I-COMPANION-MAIN 범위는 companion 등록 배선이지 새 시험
# 등록이 아니므로, 이 둘은 구체적 이유와 함께 예외로 둔다. 별도 카드에서 돌린다.
# TEST_GATE_EXCEPTION: dispatch-safe-test.sh | dispatch-safe 시작 판정 회귀. F-I-COMPANION-MAIN 범위(companion 등록 배선) 밖이며 이 작업에서 새로 돌리지 않는다. 별도 관문 카드에서 다룬다.
# TEST_GATE_EXCEPTION: test_luna_max_routing.py | Luna 라우팅 회귀. F-I-COMPANION-MAIN 범위(companion 등록 배선) 밖이며 이 작업에서 새로 돌리지 않는다. 별도 관문 카드에서 다룬다.
export ORCA_TEST_DIR="$SKILL_ROOT/scripts/tests"
ORCA_VALIDATE_LEDGER=$(mktemp /tmp/orca-validate-ledger.XXXXXX)
# 완료 영수증은 이번 실행에만 쓰는 새 파일이다. 경로가 지문에 함께 묶이므로
# 형제 실행의 영수증을 여기 옮겨 놔도 통하지 않는다.
ORCA_VALIDATE_RECEIPT=$(mktemp /tmp/orca-validate-receipt.XXXXXX)
: > "$ORCA_VALIDATE_RECEIPT"
export ORCA_TEST_LEDGER="$ORCA_VALIDATE_LEDGER"
export ORCA_TEST_LEDGER_TOKEN="tok-validate-$(date +%s)-$$"
: > "$ORCA_TEST_LEDGER"
bash "$REPO_ROOT/scripts/check-test-registration.sh" --declare "$ORCA_TEST_DIR" "$0"

bash "$REPO_ROOT/scripts/run-registered-test.sh" pytest \
  "$SKILL_ROOT/scripts/tests/test_select_routing_pair.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_shadow.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_boundaries.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_exploration.py"

bash "$REPO_ROOT/scripts/run-registered-test.sh" sh "$SKILL_ROOT/scripts/tests/test-select-routing-wrapper.sh"
# 감독 주기적 자가 점검 깨우기(2026-08-10 B8). 이 관문에 깨우기 시험이 없으면 "감독을 깨우는
# 유일한 장치"가 검증 없이 바뀐다 — 열한 시간 정지를 만든 구멍이 정확히 그 자리다.
# companion 분리·조회 실패 fail-closed·내 판 경로 좁히기·깨우기 죽음 신고까지 이 안에서 돈다.
bash "$REPO_ROOT/scripts/run-registered-test.sh" sh "$SKILL_ROOT/scripts/tests/test-supervisor-waker.sh"
# companion 우편함 소비 계약(2026-08-09 B6). 이 검증 관문에 companion 시험이 빠져 있어
# 선두 차단·슈퍼 지시 오분류가 검증 없이 통과했다. 거부 증거(B6 이전 실제 구현에 같은
# 계약 검사를 걸어 떨어뜨리기)까지 이 안에서 돈다.
bash "$REPO_ROOT/scripts/run-registered-test.sh" sh "$SKILL_ROOT/scripts/tests/test-conductor-companion.sh"
# companion 상태·대기 시험(2026-08-11 I-COMPANION-MAIN). companion 본체 통합과 같은 커밋에
# 원자적으로 연결한다 — 본체만 들어오고 이 시험이 빠지면 check --wait 재측정·UNRESOLVED
# 소비·type+messageId 중복 억제·malformed 진단 상신이 검증 없이 바뀐다. 세 companion
# 시험(main·state·wait)과 verdict 검사가 각각 정확히 한 번씩 이 관문에 연결된다.
bash "$REPO_ROOT/scripts/run-registered-test.sh" sh "$SKILL_ROOT/scripts/tests/test-conductor-companion-state.sh"
bash "$REPO_ROOT/scripts/run-registered-test.sh" sh "$SKILL_ROOT/scripts/tests/test-conductor-companion-wait.sh"
bash "$REPO_ROOT/scripts/run-registered-test.sh" sh "$SKILL_ROOT/scripts/tests/test-stall-reporter.sh"
# 판정 문구가 종료 코드와 어긋나지 못한다는 계약(2026-08-09 F-B7). 이 관문이 없어서
# 종료 코드 1이 초록 문구 뒤에 숨었다.
bash "$REPO_ROOT/scripts/run-registered-test.sh" sh "$SKILL_ROOT/scripts/tests/test-verdict-contract.sh"
bash -n "$SKILL_ROOT/scripts/conductor-companion.sh"
bash -n "$SKILL_ROOT/scripts/stall-reporter.sh"
bash -n "$SKILL_ROOT/scripts/select-routing-pair.sh"
bash -n "$SKILL_ROOT/scripts/supervisor-waker.sh"
bash -n "$SKILL_ROOT/scripts/waker-heartbeat-path.sh"
jq empty \
  "$SKILL_ROOT/references/routing-providers.json" \
  "$SKILL_ROOT/references/routing-events.schema.json"

uvx ruff check \
  "$SKILL_ROOT/scripts/routing_exploration.py" \
  "$SKILL_ROOT/scripts/routing_shadow.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_boundaries.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_exploration.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_shadow.py"

uv run --with basedpyright --with 'pydantic>=2.12,<3' --with 'typer>=0.16,<1' \
  basedpyright \
  "$SKILL_ROOT/scripts/routing_exploration.py" \
  "$SKILL_ROOT/scripts/routing_shadow.py"

# F-I-COMPANION-MAIN: 모든 관문이 통과한 뒤, 실행 원장과 시험 진입점을 대조한다.
# 이 정산이 서야 "적혀 있고 실제로도 돈 시험"만 남는다. 호출 한 줄을 빼면 그 시험은
# 증인 없이 settle 에서 UNREGISTERED_TEST 로 이름으로 잡힌다.
bash "$REPO_ROOT/scripts/check-test-registration.sh" --settle \
  "$ORCA_TEST_DIR" "$0" "$ORCA_TEST_LEDGER" "$ORCA_TEST_LEDGER_TOKEN" \
  "$ORCA_VALIDATE_RECEIPT"
rm -f "$ORCA_TEST_LEDGER"
