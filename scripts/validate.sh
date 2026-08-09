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
validate_verdict() {
  local rc=$?
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

uv run --with pytest --with 'pydantic>=2.12,<3' --with 'typer>=0.16,<1' \
  pytest -q \
  "$SKILL_ROOT/scripts/tests/test_select_routing_pair.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_shadow.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_boundaries.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_exploration.py"

bash "$SKILL_ROOT/scripts/tests/test-select-routing-wrapper.sh"
# 감독 주기적 자가 점검 깨우기(2026-08-10 B8). 이 관문에 깨우기 시험이 없으면 "감독을 깨우는
# 유일한 장치"가 검증 없이 바뀐다 — 열한 시간 정지를 만든 구멍이 정확히 그 자리다.
# companion 분리·조회 실패 fail-closed·내 판 경로 좁히기·깨우기 죽음 신고까지 이 안에서 돈다.
bash "$SKILL_ROOT/scripts/tests/test-supervisor-waker.sh"
# companion 우편함 소비 계약(2026-08-09 B6). 이 검증 관문에 companion 시험이 빠져 있어
# 선두 차단·슈퍼 지시 오분류가 검증 없이 통과했다. 거부 증거(B6 이전 실제 구현에 같은
# 계약 검사를 걸어 떨어뜨리기)까지 이 안에서 돈다.
bash "$SKILL_ROOT/scripts/tests/test-conductor-companion.sh"
bash "$SKILL_ROOT/scripts/tests/test-stall-reporter.sh"
# 판정 문구가 종료 코드와 어긋나지 못한다는 계약(2026-08-09 F-B7). 이 관문이 없어서
# 종료 코드 1이 초록 문구 뒤에 숨었다.
bash "$SKILL_ROOT/scripts/tests/test-verdict-contract.sh"
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
