#!/bin/bash
set -uo pipefail

# 시험을 실제로 실행하는 단 하나의 자리이자, 그 실행을 증언하는 자리다.
#
# Why (F-B10-2, 2026-08-10): 그 전까지 "이 시험이 관문에 등록됐는가"를 validate.sh 의
# 글자를 읽어서 판정했다. 셸 문법을 흉내 내는 방식이라 구멍이 계속 새로 났다 —
# 주석 한 줄, 죽은 `false && ...` 분기, heredoc 본문이 실행으로 둔갑했고, 반대로
# `LC_ALL=C bash ...`, `if bash ...`, `! bash ...` 같은 진짜 실행은 놓쳤다.
#
# 그래서 판정 근거를 글자에서 실행으로 옮겼다. 시험은 전부 이 파일을 통해서만 돌고,
# 이 파일은 시험을 실행하기 직전에 "무엇을 지금 실행한다"를 실행 원장(append-only)에
# 한 줄 적는다. 관문 마지막에서 그 원장과 시험 목록을 대조한다. 그러면 실행되지 않은
# 글자는 원장에 없으니 통과할 수 없고, 실행된 것은 앞에 무슨 문법이 붙어 있든
# 원장에 남으니 놓치지 않는다. 셸 표면 문법을 아예 보지 않는 것이 요점이다.
#
# 실행기 선택도 이 파일이 한다. 부르는 쪽이 임의의 명령을 넘길 수 있으면
# `run-registered-test.sh true .../test-x.sh` 같은 위장이 다시 가능해지기 때문이다.
# 부르는 쪽은 방식 이름(sh|pytest)과 시험 경로만 준다.
#
# F-B10-3(2026-08-10): 증인을 적는 권한을 시험 자식에게 넘기지 않는다.
#
# Why: R-F-B10-2가 실측했다. 이 파일이 원장 경로와 표를 환경변수로 받아 `exec` 로
# 시험을 띄우면, 시험 자식이 그 둘을 그대로 물려받는다. 그러면 자식은 한 줄로
# 실행하지도 않은 형제 시험의 증인을 올바른 표로 적을 수 있다. 실제로 형제 3개가
# 0회 실행인데 관문 전체가 종료 0 초록불이 됐다. 증인 제도의 핵심 약속이 무너진다.
#
# 그래서 두 가지를 구조로 바꿨다.
#   1. 자식은 원장 관련 환경을 아예 못 받는다. `exec` 대신 subprocess 로 띄우고
#      ORCA_TEST_LEDGER·ORCA_TEST_LEDGER_TOKEN·ORCA_TEST_DIR 를 지운 채 실행한다.
#      증인을 적는 것은 자식이 돌아온 뒤 helper 자신이다.
#   2. 원장에 적는 첫 칸은 표 원본이 아니라 표·이름·경로를 함께 묶은 지문이다.
#      그래야 원장 파일 자체를 찾아낸 자식도 거기서 표를 주워 형제 줄을 지어낼 수 없다.
#      지문 계산은 check-test-registration.sh 한 곳에만 두고 양쪽이 같이 쓴다.
#
# 그리고 증인은 자식이 성공(종료 0)으로 돌아온 뒤에만 적는다. 자식이 떨어지면
# helper 도 같은 코드로 죽고, 관문은 --settle 에 닿기 전에 이미 실패로 끝난다.
# 그러니 실패한 시험의 "돌았다" 증인은 애초에 필요가 없다.
#
# 여기서 막는 것은 상속된 환경과 이 helper 의 API 를 통한 위조다. 같은 사용자 권한
# 전체를 막는 범용 샌드박스가 아니다(그건 이 관문이 감당할 문제가 아니다).
#
# 사용법: run-registered-test.sh sh     <시험.sh>
#         run-registered-test.sh pytest <시험.py> [<시험.py> ...]
#
# 필요한 환경변수(관문이 정해 준다. 없으면 실행하지 않고 막는다):
#   ORCA_TEST_LEDGER       이번 관문 호출의 실행 원장 파일
#   ORCA_TEST_LEDGER_TOKEN 이번 관문 호출에만 쓰는 표. 옛 원장 재사용을 막는다
#   ORCA_TEST_DIR          시험 진입점 폴더. 여기 밖 경로는 이름이 모호해지므로 막는다

# 판정 문구는 stdout·stderr 양쪽에 찍는다. 한쪽만 보는 호출자에게도 이유가 보여야 한다.
die() {
  printf 'WITNESS_FAILED %s\n' "$1" >&2
  printf 'WITNESS_FAILED %s\n' "$1"
  exit 1
}

MODE=${1:-}
if [ "$#" -lt 2 ]; then
  die "사용법: $(basename "$0") <sh|pytest> <시험 경로> [...]"
fi
shift

# 방식부터 확인한다. 모르는 방식이면 원장에 한 줄도 남기지 않고 막는다.
case "$MODE" in
  sh)
    if [ "$#" -ne 1 ]; then
      die "sh 방식은 시험 파일 1개만 받는다 (받은 개수 $#)"
    fi
    ;;
  pytest) ;;
  *) die "모르는 실행 방식: ${MODE:-빈 값} (sh 또는 pytest만 된다)" ;;
esac

LEDGER=${ORCA_TEST_LEDGER:-}
TOKEN=${ORCA_TEST_LEDGER_TOKEN:-}
TEST_DIR=${ORCA_TEST_DIR:-}

[ -n "$LEDGER" ] || die "실행 원장 경로(ORCA_TEST_LEDGER)가 없다. 관문 밖에서 불렀다."
[ -n "$TOKEN" ] || die "실행 표(ORCA_TEST_LEDGER_TOKEN)가 없다. 관문 밖에서 불렀다."
[ -n "$TEST_DIR" ] || die "시험 폴더(ORCA_TEST_DIR)가 없다. 관문 밖에서 불렀다."
[ -f "$LEDGER" ] || die "실행 원장 파일이 없다: $LEDGER"

CANON_DIR=$(cd "$TEST_DIR" 2>/dev/null && pwd -P) || die "시험 폴더를 열 수 없다: $TEST_DIR"

# 지문 계산은 이 파일에 베끼지 않고 관문 검사기 한 곳에서 빌려 쓴다. 두 곳에 같은
# 계산이 있으면 언젠가 한쪽만 바뀌고, 그때 증인 대조가 통째로 어긋난다.
CHECKER="$(cd "$(dirname "$0")" && pwd)/check-test-registration.sh"
[ -f "$CHECKER" ] || die "증인 지문 계산기를 찾을 수 없다: $CHECKER"

# 실행 전에는 경로만 굳힌다. 여기서 막히면 시험을 아예 돌리지 않는다.
# 증인은 자식이 성공으로 돌아온 뒤 아래에서 helper 자신이 적는다.
witness_count=0
witness_names=()
witness_paths=()
for path in "$@"; do
  case "$path" in
    -*) die "시험 경로 자리에 옵션이 왔다: $path" ;;
  esac
  if [ ! -f "$path" ]; then
    printf 'MISSING_FILE %s (관문이 부르는데 파일이 없다)\n' "$path" >&2
    printf 'MISSING_FILE %s (관문이 부르는데 파일이 없다)\n' "$path"
    exit 1
  fi

  # 폴더를 실제 경로로 굳혀 등록 폴더와 같은지 본다. 같은 이름의 다른 파일이
  # 원장에서 한 이름으로 뭉개지는 모호함을 구조로 없앤다.
  path_dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) \
    || die "시험 경로의 폴더를 열 수 없다: $path"
  if [ "$path_dir" != "$CANON_DIR" ]; then
    die "시험 경로가 등록 폴더 밖이다(이름이 모호해진다): $path (등록 폴더 $CANON_DIR)"
  fi

  witness_names[$witness_count]=$(basename "$path")
  witness_paths[$witness_count]="$path_dir/${witness_names[$witness_count]}"
  witness_count=$(( witness_count + 1 ))
done

# 자식에게는 원장 관련 환경을 넘기지 않는다. 시험이 볼 수 있는 값으로 남겨 두면
# 그 값 하나로 형제 증인을 지어낼 수 있다(R-F-B10-2 중요 1).
run_child() {
  env -u ORCA_TEST_LEDGER -u ORCA_TEST_LEDGER_TOKEN -u ORCA_TEST_DIR "$@"
}

case "$MODE" in
  sh)
    run_child bash "$1"
    ;;
  pytest)
    run_child uv run --with pytest --with 'pydantic>=2.12,<3' --with 'typer>=0.16,<1' \
      pytest -q "$@"
    ;;
esac
child_status=$?

# 떨어진 시험은 증인을 남기지 않는다. 같은 종료 코드로 그대로 죽으면 관문은
# --settle 에 닿기 전에 이미 실패로 끝난다. pytest 묶음도 마찬가지다 —
# 수집 실패든 시험 실패든 묶음 전체가 성공해야만 아래 5줄이 적힌다.
if [ "$child_status" -ne 0 ]; then
  exit "$child_status"
fi

# 여기부터가 증언이다. 자식은 이 코드에 손댈 수 없다(이미 끝났고, 환경도 못 받았다).
# 적기에 실패하면 시험이 통과했더라도 막는다(fail-closed): 증인 없이 돈 시험은
# 관문 마지막에서 "안 돌았다"로 보이므로, 조용히 넘어가면 원인을 못 찾는 실패가 된다.
i=0
while [ "$i" -lt "$witness_count" ]; do
  name=${witness_names[$i]}
  abs=${witness_paths[$i]}
  proof=$(bash "$CHECKER" --witness-proof "$TOKEN" "$name" "$abs") \
    || die "증인 지문을 만들지 못했다: $name"
  line=$(printf '%s\t%s\t%s' "$proof" "$name" "$abs")
  printf '%s\n' "$line" >> "$LEDGER" || die "실행 원장에 못 썼다: $LEDGER"
  # 적었다고 믿지 말고 되읽어 확인한다. 꽉 찬 디스크나 읽기 전용 파일에서
  # 기록만 조용히 사라지면 관문이 이유 없이 떨어진다.
  grep -qxF "$line" "$LEDGER" || die "실행 원장에 쓴 줄을 되읽지 못했다: $LEDGER"
  i=$(( i + 1 ))
done
