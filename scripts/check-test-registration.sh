#!/bin/bash
set -euo pipefail

# Why: 시험 파일이 생긴 것과 관문이 그 시험을 실제로 돌리는 것은 다르다.
# 이 검사는 "돌아야 하는 시험 목록"과 "이번 관문 호출에서 진짜 돈 시험 목록"을 맞대,
# 실행도 이유 있는 예외도 아닌 시험을 이름으로 막는다.
#
# F-B10-2(2026-08-10): 판정 근거를 글자에서 실행으로 바꿨다.
#
# 그 전에는 validate.sh 본문을 셸 문법 흉내로 훑어 "호출됐다"를 셌다. R-B10과
# R-F-B10이 이 방식의 구멍을 연달아 실측했다.
#   - 실행 안 되는데 호출로 셌다: 주석 한 줄, 줄 끝 주석, `false && bash ...`,
#     heredoc 본문
#   - 실제로 실행되는데 못 봤다: `LC_ALL=C bash ...`, `if bash ...`, `! bash ...`
# 셸 문법을 반쯤 흉내 내는 한 이 목록은 계속 길어진다. 관문의 목적은 파일 이름이
# 적혔는지가 아니라 시험이 실제로 돌았는지 증명하는 것이다.
#
# 그래서 이제 시험은 전부 scripts/run-registered-test.sh 를 통해서만 돌고, 그 helper가
# 실행 직전에 실행 원장(append-only)에 한 줄씩 적는다. 이 검사는 두 때에 나뉘어 선다.
#   --declare : 관문 시작. 시험 진입점을 세고 예외 선언의 형식·이유·유효성만 본다.
#               이때는 무엇이 돌지 아직 모르므로 "미등록" 판정을 하지 않는다.
#   --settle  : 관문 끝(성공 주장 직전). 실행 원장과 시험 목록·예외를 대조해 판정한다.
#
# 시험이 떨어져 뒤 시험이 안 돌면 관문은 이미 그 실패로 떨어진다. --settle 은 관문이
# 성공을 주장하려는 순간에만 서므로, "성공인데 안 돈 시험이 있다"만 잡으면 된다.
#
# F-B10-3(2026-08-10): 증인 줄의 첫 칸이 표(token) 원본에서 지문으로 바뀌었다.
#
# Why: R-F-B10-2가 실측했다. 표를 환경변수로 물려받은 시험 자식이 실행하지 않은 형제의
# 증인 줄을 올바른 표로 직접 적어 관문을 종료 0 초록불로 만들었다. helper 쪽에서 자식에게
# 원장 환경을 넘기지 않도록 고쳤고, 여기서는 남은 한 갈래를 막는다 — 원장 파일 자체를
# 찾아낸 쪽이 이미 적힌 줄에서 표를 주워 쓰는 경우다. 첫 칸을 표·이름·경로를 함께 묶은
# 지문으로 두면 표를 모르는 쪽은 다른 이름의 줄을 만들 수 없다.

# 이 아래 경로 훑기는 판정 근거가 아니다. 관문 본문에 이름이 보이는 파일이 실제로
# 있는지 미리 세는 preflight 전용이다(2026-08-09 F-B7: 부르는 줄만 커밋되고 파일이
# 빠져 종료 127이 초록 문구 뒤에 숨은 사고). 여기서 몇 개를 더 세거나 덜 세도
# 등록 판정은 흔들리지 않는다 — 더 세면 없는 파일을 한 번 더 확인할 뿐이고,
# 덜 세면 그 파일은 helper가 실행 직전에 MISSING_FILE 로 잡는다.
# 그러니 이 추출기는 더 키우지 않는다.
referenced_paths() {
  python3 - "$1" <<'PY'
import re
import sys

# 실행기로 인정하는 첫 낱말. 여기 없으면 세지 않는다(막는 쪽으로 기운다).
RUNNERS = {"bash", "sh", "uv", "uvx", "python", "python3", "pytest", "jq"}
# 명령이 끊기는 자리. 이 뒤의 낱말은 다시 "첫 낱말"이 된다.
BREAKS = {";", "&", "|", "(", ")", "{", "}", "<", ">", "\n"}
WANTED = re.compile(r'^\$SKILL_ROOT/[A-Za-z0-9_./-]+\.(?:sh|py|json)$')

src = open(sys.argv[1], encoding="utf-8").read()

# (1) 셸 주석을 지운다. 따옴표 안의 #은 주석이 아니다.
kept = []
quote = None
prev = "\n"
i, n = 0, len(src)
while i < n:
    c = src[i]
    if quote is not None:
        kept.append(c)
        if c == "\\" and quote == '"' and i + 1 < n:
            kept.append(src[i + 1])
            prev = src[i + 1]
            i += 2
            continue
        if c == quote:
            quote = None
        prev = c
        i += 1
        continue
    if c in ("'", '"'):
        quote = c
        kept.append(c)
        prev = c
        i += 1
        continue
    if c == "\\" and i + 1 < n:
        kept.append(c)
        kept.append(src[i + 1])
        prev = src[i + 1]
        i += 2
        continue
    if c == "#" and prev in " \t\n;&|()":
        while i < n and src[i] != "\n":
            i += 1
        continue
    kept.append(c)
    prev = c
    i += 1

text = "".join(kept)
# 줄 이음(\ + 줄바꿈)은 한 명령이므로 붙인다.
text = re.sub(r"\\\n", " ", text)

TOKEN = re.compile(r"""'[^']*'|"(?:\\.|[^"\\])*"|[^\s;&|(){}<>]+|[;&|(){}<>\n]""")
found = []
runner = None
at_head = True
for m in TOKEN.finditer(text):
    tok = m.group(0)
    if tok in BREAKS:
        at_head = True
        runner = None
        continue
    word = tok
    if len(word) >= 2 and word[0] == word[-1] and word[0] in "\"'":
        word = word[1:-1]
    if at_head:
        at_head = False
        runner = word if word in RUNNERS else None
        continue
    if runner is not None and WANTED.match(word):
        found.append(word)

print("\n".join(found))
PY
}

# 증인 줄의 첫 칸에 적히는 지문이다. 표(token) 원본이 아니라 표·이름·경로를 함께
# 묶은 값이다.
#
# F-B10-3(2026-08-10): Why. 표 원본을 그대로 적으면, 원장 파일을 찾아낸 시험 자식이
# 이미 적힌 줄에서 표를 주워 실행하지 않은 형제의 줄을 지어낼 수 있다. 지문으로 적으면
# 표를 모르는 쪽은 다른 이름의 줄을 만들 수 없다 — 이름과 경로가 지문 안에 같이 묶여
# 있어, 남의 줄을 베껴 이름만 바꾸면 지문이 어긋난다.
#
# 계산은 여기 한 곳에만 둔다. run-registered-test.sh 는 --witness-proof 로 빌려 쓴다.
witness_proof() {
  local digest
  if command -v sha256sum >/dev/null 2>&1; then
    digest=$(printf '%s\t%s\t%s' "$1" "$2" "$3" | sha256sum) || return 1
  elif command -v shasum >/dev/null 2>&1; then
    digest=$(printf '%s\t%s\t%s' "$1" "$2" "$3" | shasum -a 256) || return 1
  else
    return 1
  fi
  digest=${digest%% *}
  [ "${#digest}" -eq 64 ] || return 1
  printf '%s\n' "$digest"
}

# F-I-COMPANION-MAIN-2(2026-08-11): 정산이 실제로 끝났다는 완료 영수증.
#
# Why: R-F-I-COMPANION-MAIN이 실측했다. 관문 마지막의 --settle 두 줄을 지운 사본이
# 종료 0과 VALIDATE PASSED 로 살아남았다. 성공 판정이 종료 코드만 보고 있었기 때문이다.
# 정산이 아예 불리지 않아도 "실패한 명령"이 없으니 종료 코드는 0이다. 즉 등록 관문
# 전체를 두 줄 삭제로 우회할 수 있었다.
#
# 그래서 정산은 성공을 주장하기 직전에 이번 실행에만 유효한 완료 영수증을 남기고,
# 관문의 성공 판정은 그 영수증을 확인해야만 초록불을 찍는다. 영수증의 지문은
# 증인 줄과 같은 계산기(witness_proof)로 이번 실행 표·집계·영수증 절대경로를 함께
# 묶으므로, 이전 실행의 영수증도 형제 실행의 영수증도 그 자리에서 어긋난다.
receipt_field() {
  awk -F'\t' -v key="$2" '$1 == key { print $2; exit }' "$1"
}

verify_settle_receipt() {
  local receipt="$1" token="$2"
  local dir abs head_line r_token r_all r_exec r_exc r_proof expect

  receipt_problem() {
    printf 'TEST_REGISTRATION_SETTLE_MISSING %s\n' "$1" >&2
    printf 'TEST_REGISTRATION_SETTLE_MISSING %s\n' "$1"
  }

  if [ -z "$receipt" ]; then
    receipt_problem '완료 영수증 경로가 비었다(관문이 정산에 영수증을 넘기지 않았다)'
    return 1
  fi
  if [ -z "$token" ]; then
    receipt_problem '이번 실행의 표가 비었다(영수증을 이번 실행에 묶을 수 없다)'
    return 1
  fi
  if [ ! -s "$receipt" ]; then
    receipt_problem "완료 영수증이 없거나 비었다: $receipt (정산이 이번 실행에서 성공하지 않았다)"
    return 1
  fi
  dir=$(cd "$(dirname "$receipt")" 2>/dev/null && pwd -P) || {
    receipt_problem "완료 영수증 폴더를 열 수 없다: $receipt"
    return 1
  }
  abs="$dir/$(basename "$receipt")"

  head_line=$(sed -n 1p "$receipt")
  if [ "$head_line" != "SETTLE_OK" ]; then
    receipt_problem "완료 영수증 첫 줄이 SETTLE_OK 가 아니다: ${head_line:-빈 줄}"
    return 1
  fi
  r_token=$(receipt_field "$receipt" token)
  r_all=$(receipt_field "$receipt" tests)
  r_exec=$(receipt_field "$receipt" executed)
  r_exc=$(receipt_field "$receipt" exceptions)
  r_proof=$(receipt_field "$receipt" proof)

  if [ "$r_token" != "$token" ]; then
    receipt_problem '완료 영수증의 표가 이번 실행의 표와 다르다(이전 실행 또는 형제 실행의 영수증이다)'
    return 1
  fi
  case "$r_all$r_exec$r_exc" in
    ''|*[!0-9]*)
      receipt_problem "완료 영수증의 집계 칸이 숫자가 아니다(tests=$r_all executed=$r_exec exceptions=$r_exc)"
      return 1 ;;
  esac
  if [ "$r_exec" -lt 1 ]; then
    receipt_problem '완료 영수증이 실제 실행 0개를 적고 있다'
    return 1
  fi
  expect=$(witness_proof "$token" "settle-receipt:$r_all:$r_exec:$r_exc" "$abs") || expect=""
  if [ -z "$expect" ] || [ "$r_proof" != "$expect" ]; then
    receipt_problem '완료 영수증의 지문이 이번 실행과 어긋난다(옮겨 온 영수증이거나 내용이 손댔다)'
    return 1
  fi
  printf 'TEST_REGISTRATION SETTLE_RECEIPT OK · 시험 %s개 · 실제 실행 %s개 · 예외 %s개\n' \
    "$r_all" "$r_exec" "$r_exc"
}

write_settle_receipt() {
  local receipt="$1" token="$2" all="$3" executed="$4" exceptions="$5"
  local dir abs proof
  dir=$(cd "$(dirname "$receipt")" 2>/dev/null && pwd -P) || return 1
  abs="$dir/$(basename "$receipt")"
  proof=$(witness_proof "$token" "settle-receipt:$all:$executed:$exceptions" "$abs") || return 1
  {
    printf 'SETTLE_OK\n'
    printf 'token\t%s\n' "$token"
    printf 'tests\t%s\n' "$all"
    printf 'executed\t%s\n' "$executed"
    printf 'exceptions\t%s\n' "$exceptions"
    printf 'proof\t%s\n' "$proof"
  } > "$abs" || return 1
  # 적었다고 믿지 않고 되읽어 확인한다(증인 줄과 같은 fail-closed 규칙).
  verify_settle_receipt "$abs" "$token" >/dev/null
}

usage() {
  cat >&2 <<'USAGE'
사용법:
  check-test-registration.sh --declare <시험 폴더> <validate.sh>
  check-test-registration.sh --settle  <시험 폴더> <validate.sh> <실행 원장> <실행 표> [<완료 영수증>]
  check-test-registration.sh --verify-receipt <완료 영수증> <실행 표>
  check-test-registration.sh --referenced-paths <셸 스크립트>
  check-test-registration.sh --witness-proof <실행 표> <시험 이름> <시험 절대경로>
USAGE
  exit 2
}

MODE=${1:-}

if [ "$MODE" = "--referenced-paths" ]; then
  if [ "$#" -ne 2 ] || [ ! -f "$2" ]; then
    printf '사용법: %s --referenced-paths <셸 스크립트>\n' "$0" >&2
    exit 2
  fi
  referenced_paths "$2"
  exit 0
fi

if [ "$MODE" = "--verify-receipt" ]; then
  [ "$#" -eq 3 ] || usage
  verify_settle_receipt "$2" "$3"
  exit $?
fi

if [ "$MODE" = "--witness-proof" ]; then
  [ "$#" -eq 4 ] || usage
  witness_proof "$2" "$3" "$4" \
    || { printf 'WITNESS_NO_HASH_TOOL (sha256sum·shasum 둘 다 못 쓴다)\n' >&2; exit 1; }
  exit 0
fi

case "$MODE" in
  --declare) [ "$#" -eq 3 ] || usage ;;
  --settle)  [ "$#" -eq 5 ] || [ "$#" -eq 6 ] || usage ;;
  *) usage ;;
esac

TEST_DIR="$2"
VALIDATE_SCRIPT="$3"

if [ ! -d "$TEST_DIR" ]; then
  printf 'TEST_REGISTRATION 실패: 시험 폴더가 없다: %s\n' "$TEST_DIR" >&2
  exit 1
fi
if [ ! -f "$VALIDATE_SCRIPT" ]; then
  printf 'TEST_REGISTRATION 실패: 관문 파일이 없다: %s\n' "$VALIDATE_SCRIPT" >&2
  exit 1
fi

work=$(mktemp -d /tmp/orca-test-registration.XXXXXX)
all="$work/all.txt"
exceptions="$work/exceptions.txt"
bad_reasons="$work/bad-reasons.txt"
executed="$work/executed.txt"

# 시험 진입점은 저장소의 세 가지 기존 이름 규칙을 모두 포함한다.
find "$TEST_DIR" -maxdepth 1 -type f \
  \( -name 'test-*.sh' -o -name 'test_*.py' -o -name '*-test.sh' \) \
  -exec basename {} \; | sort -u > "$all"

# 형식: # TEST_GATE_EXCEPTION: 파일명 | 사람이 지울 수 있을 만큼 구체적인 이유
#
# F-B10(2026-08-10): 이유 칸은 "글자가 있는지"가 아니라 "공백을 걷어내고도 남는지"로 본다.
# Why: R-B10이 실측했다. 완전히 빈 이유는 막혔지만 공백 두 칸은 이유 있는 예외로
# 통과했다. 이유를 써야만 열리는 예외 계약이 빈칸으로 열리면 계약이 아니다.
# 형식이 아예 어긋난 줄도 조용히 무시하지 않고 이름을 대며 막는다.
sed -nE 's/^# TEST_GATE_EXCEPTION:[[:space:]]*([^ |]+)[[:space:]]*\|(.*)$/\1|\2/p' \
  "$VALIDATE_SCRIPT" > "$work/exception-raw.txt"
: > "$exceptions"
: > "$bad_reasons"
while IFS='|' read -r ex_name ex_reason; do
  [ -n "$ex_name" ] || continue
  trimmed=$(printf '%s' "$ex_reason" | tr -d '[:space:]')
  if [ -z "$trimmed" ]; then
    printf '%s\n' "$ex_name" >> "$bad_reasons"
  else
    printf '%s|%s\n' "$ex_name" "$ex_reason" >> "$exceptions"
  fi
done < "$work/exception-raw.txt"

# 형식이 깨져 위 규칙에 아예 안 잡힌 예외 선언도 이름 없이 사라지면 안 된다.
# grep -c 는 0건일 때도 "0"을 찍으면서 종료 1이다. 그래서 || 로 값을 덧붙이면 안 되고,
# 실패했을 때만 통째로 0으로 덮어써야 한다.
declared_total=$(grep -cE '^# TEST_GATE_EXCEPTION:' "$VALIDATE_SCRIPT") || declared_total=0
parsed_total=$(wc -l < "$work/exception-raw.txt" | tr -d ' ')
malformed_total=$(( declared_total - parsed_total ))

cut -d '|' -f 1 "$exceptions" | sort -u > "$work/exception-names.txt"
comm -13 "$all" "$work/exception-names.txt" > "$work/stale-exceptions.txt"

all_total=$(wc -l < "$all" | tr -d ' ')
exception_total=$(wc -l < "$exceptions" | tr -d ' ')
bad_reason_total=$(wc -l < "$bad_reasons" | tr -d ' ')
stale_total=$(wc -l < "$work/stale-exceptions.txt" | tr -d ' ')

name_lines() {
  local file="$1" fmt="$2" name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    # shellcheck disable=SC2059
    printf "$fmt" "$name" >&2
  done < "$file"
}

name_lines "$bad_reasons" 'EMPTY_EXCEPTION_REASON %s (이유 칸이 공백뿐이다. 지울 수 있을 만큼 구체적으로 적어라)\n'
name_lines "$work/stale-exceptions.txt" 'STALE_TEST_EXCEPTION %s (예외에는 있지만 시험 파일이 없다)\n'
if [ "$malformed_total" -gt 0 ]; then
  printf 'MALFORMED_TEST_EXCEPTION %s줄 (형식은 "# TEST_GATE_EXCEPTION: 파일명 | 이유")\n' \
    "$malformed_total" >&2
fi

declare_broken=0
if [ "$bad_reason_total" -ne 0 ] || [ "$stale_total" -ne 0 ] || [ "$malformed_total" -gt 0 ]; then
  declare_broken=1
fi

if [ "$MODE" = "--declare" ]; then
  printf 'TEST_REGISTRATION 선언 확인 · 시험 진입점 %s개 · 이유 있는 예외 %s개\n' \
    "$all_total" "$exception_total"
  if [ "$all_total" -eq 0 ]; then
    printf 'TEST_REGISTRATION 실패: 시험 진입점을 한 개도 못 찾았다\n' >&2
    exit 1
  fi
  if [ "$declare_broken" -ne 0 ]; then
    printf 'TEST_REGISTRATION 실패: 위 예외 선언을 고쳐라\n' >&2
    exit 1
  fi
  printf 'TEST_REGISTRATION DECLARED\n'
  exit 0
fi

# ---- 여기부터 --settle: 실행 원장과 대조한다 ----
LEDGER="$4"
TOKEN="$5"
RECEIPT=${6:-}

witness_broken=0
witness_problem() {
  printf '%s\n' "$1" >&2
  witness_broken=$(( witness_broken + 1 ))
}

if [ -z "$TOKEN" ]; then
  witness_problem 'WITNESS_NO_TOKEN (이번 관문 호출의 실행 표가 비었다)'
fi
if [ ! -f "$LEDGER" ]; then
  witness_problem "WITNESS_MISSING $LEDGER (실행 원장 파일이 없다. 증인 없이 성공을 주장할 수 없다)"
fi
# 지문을 못 만들면 어떤 줄도 검증할 수 없다. 그 상태로 줄을 받아들이면 대조가
# 형식 검사로 주저앉으므로, 성공을 주장하지 못하게 여기서 막는다.
if ! witness_proof "probe" "probe" "probe" >/dev/null; then
  witness_problem 'WITNESS_NO_HASH_TOOL (지문을 만들 도구가 없다. 증인을 검증할 수 없다)'
fi

: > "$executed"
if [ -f "$LEDGER" ] && [ -n "$TOKEN" ]; then
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$(( lineno + 1 ))
    if [ -z "$line" ]; then
      witness_problem "WITNESS_MALFORMED ${lineno}줄 (빈 줄)"
      continue
    fi
    tabs=$(printf '%s' "$line" | tr -cd '\t' | wc -c | tr -d ' ')
    if [ "$tabs" -ne 2 ]; then
      witness_problem "WITNESS_MALFORMED ${lineno}줄 (칸이 3개가 아니다: $line)"
      continue
    fi
    w_proof=${line%%$'\t'*}
    w_rest=${line#*$'\t'}
    w_name=${w_rest%%$'\t'*}
    w_path=${w_rest#*$'\t'}
    if [ -z "$w_name" ] || [ "$(basename "$w_path")" != "$w_name" ]; then
      witness_problem "WITNESS_MALFORMED ${lineno}줄 (이름과 경로가 어긋난다: $line)"
      continue
    fi
    # 지문은 이번 호출의 표 + 이 줄의 이름 + 이 줄의 경로로만 나온다. 그래서
    # (1) 다른 판·과거 실행의 증인, (2) 표를 모르는 쪽이 지어낸 줄, (3) 남의 줄을
    # 베껴 이름만 바꾼 줄이 전부 같은 자리에서 걸린다.
    expected_proof=$(witness_proof "$TOKEN" "$w_name" "$w_path") || expected_proof=""
    if [ -z "$expected_proof" ] || [ "$w_proof" != "$expected_proof" ]; then
      witness_problem "WITNESS_FOREIGN_RUN ${lineno}줄 (이번 관문이 남긴 증인이 아니다: $w_name)"
      continue
    fi
    printf '%s\n' "$w_name" >> "$executed"
  done < "$LEDGER"
fi

sort -u "$executed" -o "$executed"
executed_total=$(wc -l < "$executed" | tr -d ' ')

# 원장에 있는데 시험 진입점 목록에 없는 이름은 대조 자체가 어긋난 상태다.
comm -13 "$all" "$executed" > "$work/unknown-witness.txt"
name_lines "$work/unknown-witness.txt" 'WITNESS_UNKNOWN_TEST %s (원장에 있는데 시험 진입점이 아니다)\n'
if [ -s "$work/unknown-witness.txt" ]; then
  witness_broken=$(( witness_broken + 1 ))
fi

cat "$executed" "$work/exception-names.txt" | sort -u > "$work/covered.txt"
comm -23 "$all" "$work/covered.txt" > "$work/unregistered.txt"
comm -12 "$executed" "$work/exception-names.txt" > "$work/overlap.txt"

unregistered_total=$(wc -l < "$work/unregistered.txt" | tr -d ' ')
overlap_total=$(wc -l < "$work/overlap.txt" | tr -d ' ')

printf 'TEST_REGISTRATION 시험 진입점 총 %s개 · 실제 실행 %s개 · 이유 있는 예외 %s개 · 미등록 %s개\n' \
  "$all_total" "$executed_total" "$exception_total" "$unregistered_total"

name_lines "$work/unregistered.txt" 'UNREGISTERED_TEST %s (이번 관문에서 실제로 돌지도, 이유 있는 예외도 아니다)\n'
name_lines "$work/overlap.txt" 'REDUNDANT_TEST_EXCEPTION %s (이미 관문이 실제로 돌리므로 예외에서 빼라)\n'

if [ "$all_total" -eq 0 ]; then
  printf 'TEST_REGISTRATION 실패: 시험 진입점을 한 개도 못 찾았다\n' >&2
  exit 1
fi
if [ "$executed_total" -eq 0 ]; then
  printf 'TEST_REGISTRATION 실패: 실행 원장이 비었다. 시험이 한 개도 안 돌았다.\n' >&2
  exit 1
fi
if [ "$witness_broken" -ne 0 ]; then
  printf 'TEST_REGISTRATION 실패: 실행 원장을 믿을 수 없다(위 WITNESS_ 줄 참고)\n' >&2
  exit 1
fi
if [ "$declare_broken" -ne 0 ] || [ "$unregistered_total" -ne 0 ] || [ "$overlap_total" -ne 0 ]; then
  printf 'TEST_REGISTRATION 실패: 위 이름을 실제 실행 또는 이유 있는 예외와 맞춰라\n' >&2
  exit 1
fi

# 여기까지 왔으면 이번 실행의 정산이 실제로 통과했다. 성공을 주장하기 직전에
# 이번 실행에만 유효한 완료 영수증을 남긴다. 못 적으면 성공을 주장하지 않는다.
if [ -n "$RECEIPT" ]; then
  if ! write_settle_receipt "$RECEIPT" "$TOKEN" "$all_total" "$executed_total" "$exception_total"; then
    printf 'TEST_REGISTRATION_SETTLE_MISSING 완료 영수증을 남기지 못했다: %s\n' "$RECEIPT" >&2
    exit 1
  fi
fi

printf 'TEST_REGISTRATION PASSED\n'
