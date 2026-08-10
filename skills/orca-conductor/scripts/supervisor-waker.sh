#!/bin/bash
# 감독 주기적 자가 점검 깨우기 — **companion 과 분리된 별도 프로세스**.
#
# Why (2026-08-09 kyle 지적 -> 슈퍼 지시):
#   우리 구조에는 **감독을 주기적으로 깨우는 장치가 없었다.**
#   - 중계기(relay)에는 kicker 가 있어 주기적으로 깨워진다.
#   - 감독에게는 companion 뿐인데 그것은 **편지가 왔을 때만** 깨운다.
#   - 그래서 편지가 안 오거나 companion 이 막히면 감독은 영원히 안 깨어난다.
#   2026-08-09 아침 **열한 시간 정지가 정확히 그 상태**였다.
#
#   그리고 그때 판은 더 나빴다. kicker 가 별도 프로세스가 아니라 **companion 안의 루프**였다
#   (conductor-companion.sh 의 NEXT_KICKER). **하나가 죽으면 배달과 깨우기가 같이 죽는다.**
#   그래서 이 장치는 companion 과 **완전히 분리된 프로세스**로 돈다.
#
#   "자연법칙이 아니라 장치가 없는 것이다."
#
# B7 과 무엇이 다른가 (합치지 마라):
#   B7(stall-reporter 의 판 비움 감지) = **판이 멈춘 상태**. 대기가 있는데 발령이 0이다. 판 쪽 사실.
#   B8(이 스크립트)                   = **감독이 안 깨어나는 상태**. 판이 어떻든 감독이 아무것도 안 한다.
#   B7 이 정상 판정을 내려도 감독이 그 판정을 읽지 않으면 소용없다. B8 은 **읽을 계기**를 만든다.
#
# 이 스크립트가 지키는 다섯 가지:
#   1. companion 과 완전히 분리된 프로세스다. 배달이 죽어도 깨우기는 산다.
#   2. **무조건 깨운다.** 이상할 때만 깨우지 않는다 — 이상 판정이 틀리면 영영 안 깨어나기 때문이다.
#   3. **조회 실패를 "0장"으로 읽지 않는다.** task-list 가 실패하면 판정불가를 따로 낸다(fail-closed).
#   4. 감시 프로세스 생존 확인을 **내 판으로 좁힌다** — 내 판 런타임 경로 아래이거나,
#      명령줄에 `--board <내 판>` 이 있는 것만 센다. 스크립트 이름만으로 세면 다른 판과
#      /tmp 시험 사본까지 잡혀 **내 것이 죽어도 살아 있음으로 읽힌다**(2026-08-09 실측: 7개가
#      잡혔고 내 것은 2개였다). 반대로 경로로만 좁혀도 안 된다 — 자세한 근거는 scan_toplevel 에 있다.
#   5. **자기 생존은 심박 파일에 적어 이미 있는 정체 신고기(stall-reporter)가 보게 한다.**
#      깨우는 것을 깨우는 것을 또 만들지 않는다. 감시는 한 겹으로 끝난다.
#      심박 파일 경로는 waker-heartbeat-path.sh 한 곳에서만 정한다(왜 중계기 일기가 아닌지도 거기 적혀 있다).
#
# 판 이름·감독 핸들·Run 을 **상수로 박지 않는다.** 전부 인자로 받는다.
# 2026-08-09 에 다른 판 kicker 가 핸들을 상수로 들고 있어서 감독을 못 깨웠다. 같은 실수를 반복하지 않는다.
set -u

usage() {
  echo "usage: supervisor-waker.sh --board <board> --supervisor <term_handle> --run <run_id> --relay-log <path> --runtime-dir <path> [--interval-sec 1800] [--once]" >&2
  exit 2
}

BOARD=""
SUPERVISOR=""
RUN_ID=""
RELAY_LOG=""
RUNTIME_DIR=""
# 주기 기본값 1800초(30분)의 근거:
#   이 판의 카드 한 라운드가 대략 20~60분이다. 30분이면 **정지가 카드 한 라운드 안에서 드러난다.**
#   더 짧게 하면 정상일 때도 감독을 계속 깨워 감독의 문맥만 축낸다.
#   더 길게 하면 2026-08-09 같은 장시간 정지를 늦게 잡는다.
#   (B8 검토 결론: 30분을 유지한다. 라운드 길이가 바뀌면 이 근거부터 다시 쓴다.
#    깨우기 자체는 비용이 거의 없지만 감독을 깨우는 것은 감독의 한 턴을 쓰는 일이라,
#    "더 자주 깨우면 더 안전하다"가 성립하지 않는다.)
INTERVAL=1800
ONCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --board) [ $# -ge 2 ] || usage; BOARD="$2"; shift 2 ;;
    --supervisor) [ $# -ge 2 ] || usage; SUPERVISOR="$2"; shift 2 ;;
    --run) [ $# -ge 2 ] || usage; RUN_ID="$2"; shift 2 ;;
    --relay-log) [ $# -ge 2 ] || usage; RELAY_LOG="$2"; shift 2 ;;
    --runtime-dir) [ $# -ge 2 ] || usage; RUNTIME_DIR="$2"; shift 2 ;;
    --interval-sec) [ $# -ge 2 ] || usage; INTERVAL="$2"; shift 2 ;;
    --once) ONCE=1; shift ;;
    *) echo "UNKNOWN_FLAG $1" >&2; usage ;;
  esac
done

[ -n "$BOARD" ] || { echo "REQUIRED board" >&2; usage; }
[ -n "$SUPERVISOR" ] || { echo "REQUIRED supervisor" >&2; usage; }
[ -n "$RUN_ID" ] || { echo "REQUIRED run" >&2; usage; }
[ -n "$RELAY_LOG" ] || { echo "REQUIRED relay-log" >&2; usage; }
# 내 판 경로다. 이것이 없으면 프로세스 생존 확인이 "이름만으로 세기"로 되돌아가고,
# 그 순간 다른 판 프로세스가 내 생존으로 읽힌다. 그래서 선택 인자가 아니다.
[ -n "$RUNTIME_DIR" ] || { echo "REQUIRED runtime-dir" >&2; usage; }
case "$INTERVAL" in ''|*[!0-9]*) echo "INVALID interval-sec=$INTERVAL" >&2; usage ;; esac
[ "$INTERVAL" -ge 1 ] || { echo "INVALID interval-sec=$INTERVAL" >&2; usage; }

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"
# 심박 파일 경로 계산은 신고기와 같은 파일에서 빌려 쓴다. 두 곳에 베끼면 언젠가 한쪽만 바뀐다.
# shellcheck source=./waker-heartbeat-path.sh
. "$SCRIPT_DIR/waker-heartbeat-path.sh"

# orca CLI 위치 해석은 companion·stall-reporter 와 같은 규칙을 따른다.
REQUESTED_ORCA_BIN="${ORCA_BIN:-}"
if [ -n "$REQUESTED_ORCA_BIN" ] && [ -x "$REQUESTED_ORCA_BIN" ]; then
  ORCA_BIN="$REQUESTED_ORCA_BIN"
elif [ -n "$REQUESTED_ORCA_BIN" ]; then
  ORCA_BIN=$(command -v "$REQUESTED_ORCA_BIN" 2>/dev/null || true)
elif command -v orca >/dev/null 2>&1; then
  ORCA_BIN=$(command -v orca)
elif [ -x /usr/local/bin/orca ]; then
  ORCA_BIN=/usr/local/bin/orca
elif [ -x /opt/homebrew/bin/orca ]; then
  ORCA_BIN=/opt/homebrew/bin/orca
else
  ORCA_BIN=""
fi
if [ -z "$ORCA_BIN" ] || [ ! -x "$ORCA_BIN" ]; then
  echo "ORCA_BIN_UNAVAILABLE requested=${REQUESTED_ORCA_BIN:-auto}" >&2
  exit 3
fi

HEARTBEAT_LOG=$(waker_heartbeat_path "$RELAY_LOG" "$BOARD") || {
  echo "HEARTBEAT_PATH_UNRESOLVED relay_log=$RELAY_LOG board=$BOARD" >&2
  exit 3
}
mkdir -p "$(dirname "$HEARTBEAT_LOG")" 2>/dev/null || true

START_EPOCH=$(date +%s)

log() { printf '%s supervisor-waker board=%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$BOARD" "$*"; }

# 심박. 정체 신고기가 이 줄이 끊긴 것을 보고 "깨우기 죽음"을 신고한다.
# interval 을 줄에 함께 적는 이유: 신고기가 침묵 임계값을 **내 주기에서 유도**하기 위해서다.
# 임계값을 신고기 쪽에 따로 적어 두면 주기를 바꿀 때 한쪽만 바뀌어 오보가 난다.
heartbeat() {
  printf '%s SUPERVISOR_WAKER_ALIVE board=%s pid=%s interval=%s %s\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$BOARD" "$$" "$INTERVAL" "$1" >> "$HEARTBEAT_LOG" 2>/dev/null || true
}

# 프로세스 한 번 훑기. **내 판 것만** 내보낸다. 출력 한 줄 = "pid|기동시각|명령줄".
#
# "내 판 것"을 어떻게 가리는가 — 두 가지 중 하나면 내 것이다.
#   (1) 명령줄이 내 판 런타임 폴더 아래 경로다   (판마다 스크립트 사본을 두는 배치)
#   (2) 명령줄에 `--board <내 판 이름>` 이 있다  (여러 판이 스크립트 하나를 같이 쓰는 배치)
#
# 왜 (2)가 반드시 필요한가 (2026-08-11 실측): 이 판의 companion 은 판별 사본이 아니라
# `~/.claude/skills/orca-conductor/scripts/conductor-companion.sh --project ... --board mailbox-relay-1`
# 로 돌고 있었다. **판 신분이 경로가 아니라 인자에 있다.** 경로로만 좁히면 멀쩡히 살아 있는
# companion 을 0개로 세어 "companion 죽음"을 계속 외친다. 오늘 잡은 것의 거울상이다 —
# 초록불 위장이 아니라 **빨간불 위장**이고, 둘 다 숫자가 대상을 안 가리켜서 생긴다.
#
# 이름만으로 세지 않는 원칙은 그대로다. 스크립트 이름 + (내 경로 또는 내 판 이름) 둘 다 맞아야 한다.
#
# 왜 최상위(PPID 1)만 세는가 — 둘 다 2026-08-09 실측이다.
#   1. companion 은 자식 프로세스를 하나 띄운다. 그대로 세면 하나가 도는데 2로 세진다.
#   2. 패턴 문자열이 명령줄에 들어 있으므로 **검사하는 셸 자신**도 잡힌다. 실제로 companion 이
#      4로 보고됐는데 진짜는 부모 1 + 자식 1 이었고 나머지 2는 확인 명령 자신이었다.
#   살아있음 판정(>0)에는 영향이 없지만 **숫자가 뜻과 달라지면 그 숫자를 믿을 수 없다.**
#
# 왜 `ps` 를 한 번만 부르는가 (2026-08-10 이 기계에서 실측, 프로세스 874개, 부하 3.52):
#   `ps -o ppid= -p <PID 1개>`        중앙값   5.7ms
#   `ps -o ppid= -p <PID 2개 쉼표>`   중앙값  96.5ms   <- **PID 1개에서 2개로 갈 때 절벽**
#   `ps -Ao pid=,ppid=,lstart=,command=` 중앙값 41.9ms  <- 매치 개수와 무관하게 일정
#   즉 여러 PID 를 쉼표로 한 번에 넘기는 "최적화"는 17배 느려진다. PID 를 하나씩 부르는 것도
#   맞는 방법이지만, 여기서는 pid·부모·기동시각·명령줄이 **전부** 필요해서 어차피 여러 번
#   불러야 한다. 전체 한 번 훑기는 그 값을 한 번에 주고 비용도 일정하다.
#
# **반드시 LC_ALL=C 로 부른다.** 한국어 로케일에서 `ps -o lstart` 는
# "2026년  8월 10일 월요일 23시 59분 16초" 처럼 **토막 수가 다른 모양**으로 찍힌다.
# 그러면 아래의 "앞 5토막이 기동 시각" 가정이 깨져 명령줄 앞부분이 시각으로 먹히고,
# 기동 시각도 `date -j -f` 로 되읽히지 않는다. 2026-08-10 이 시험에서 실제로 겪었다 —
# 세기는 우연히 맞고 낡은코드 검사만 조용히 죽어 있었다. 로케일에 매달린 침묵이다.

# **정규식을 쓰지 않고 부분문자열로 맞춘다.** 경로도 판 이름도 스크립트 이름도 전부 그냥 글자다.
#
# Why (2026-08-11 실측): 처음에는 판 이름을 정규식에 넣고 특수문자를 escape 했는데,
# **awk 가 `-v` 로 받은 값의 escape 를 먼저 풀어 버려서** `b\.test` 가 다시 `b.test` 가 됐다.
# 그래서 판 `b.test` 가 판 `bXtest` 의 프로세스를 자기 것으로 읽었다 — escape 를 했는데
# 안 한 것과 같았고, 코드만 보면 막아 놓은 것처럼 보였다. **한 겹 더 있는 침묵하는 미적용이다.**
# 부분문자열 비교에는 escape 라는 단계 자체가 없으므로 이 함정이 사라진다.
#
# $1 = 스크립트 파일 이름 (예: conductor-companion.sh)
scan_toplevel() {
  local script_name="$1"
  LC_ALL=C ps -Ao pid=,ppid=,lstart=,command= 2>/dev/null \
    | awk -v sname="$script_name" -v dir="$RUNTIME_DIR" -v board="$BOARD" -v self="$$" '
    # `--board <내 판>` 이 있고, 그 뒤가 공백이거나 줄 끝일 때만 내 판이다.
    # 뒤를 안 보면 판 `b` 가 판 `b_extra` 를 자기 것으로 읽는다.
    # 내 런타임 폴더 **자체이거나 그 아래**일 때만 내 것이다.
    # 그냥 부분문자열로 맞추면 내 폴더가 `/mine` 일 때 다른 판 `/mine-shadow` 한 대가
    # 내 companion 으로 세어져 **내 것의 죽음을 조용히 가린다**(2026-08-11 R-B8 실측 반례).
    # 그래서 앞뒤 경계를 같이 본다: 앞은 줄 시작·공백·`=`(--runtime-dir=... 모양),
    # 뒤는 줄 끝·공백·`/`. 정규식이 아니라 글자 위치로만 보므로 판 이름·경로에
    # 점·대괄호·별표가 있어도 escape 단계가 아예 없다(is_my_board 와 같은 이유).
    # 첫 자리 하나만 보지 않고 **모든 등장 자리를 훑는다.** 명령줄 앞쪽에
    # `/mine-shadow/...` 가 먼저 나오고 뒤쪽에 진짜 `/mine` 이 오는 순서도 실제로 생긴다.
    function is_my_dir(cmd,   d, n, from, p, prevc, nextc) {
      d = dir
      while (length(d) > 1 && substr(d, length(d), 1) == "/") d = substr(d, 1, length(d) - 1)
      n = length(d)
      if (n == 0) return 0
      from = 1
      while (from <= length(cmd)) {
        p = index(substr(cmd, from), d)
        if (p == 0) return 0
        p = p + from - 1
        prevc = (p == 1) ? "" : substr(cmd, p - 1, 1)
        nextc = substr(cmd, p + n, 1)
        if ((prevc == "" || prevc == " " || prevc == "=") \
            && (nextc == "" || nextc == " " || nextc == "/")) return 1
        from = p + 1
      }
      return 0
    }

    function is_my_board(cmd,   marker, p, nextc) {
      marker = "--board " board
      p = index(cmd, marker)
      if (p == 0) return 0
      nextc = substr(cmd, p + length(marker), 1)
      return (nextc == "" || nextc == " ")
    }
    $2 == 1 && $1 != self {
      # LC_ALL=C 에서 lstart 는 항상 5토막이다("Sun Aug 10 09:33:12 2026"). 그 뒤부터가 명령줄이다.
      started = $3" "$4" "$5" "$6" "$7
      cmd = ""
      for (i = 8; i <= NF; i++) cmd = cmd (i > 8 ? " " : "") $i
      if (index(cmd, sname) > 0 && (is_my_dir(cmd) || is_my_board(cmd))) \
        printf "%s|%s|%s\n", $1, started, cmd
    }'
}

# `grep -c .` 를 쓰지 않는다. 0줄일 때 "0" 을 찍으면서 종료 코드 1로 끝나므로
# `|| printf 0` 같은 보정을 붙이면 "00" 이 된다. 세는 일은 awk 한 곳에서 끝낸다.
count_toplevel() {
  scan_toplevel "$1" | awk 'END { print NR + 0 }'
}

# 상주 프로세스가 **고친 코드로 돌고 있는지** 결정적으로 검사한다.
#
# Why (2026-08-09 실사고): 세는 법을 파일에서 고쳤는데 **도는 프로세스는 옛 코드**였다.
# 그때 알아챈 이유는 숫자가 뜻과 어긋나서였고 그건 운이다. 어긋나는 숫자가 없었으면 못 봤다.
#   결정적 검사: **프로세스 기동 시각 < 그 프로세스가 실행 중인 파일의 수정 시각 -> 낡은 코드다.**
#   뿌리: `파일이 고쳐졌다` 와 `고친 것이 돌고 있다` 는 다른데 우리는 `고쳤다` 하나로 말해 왔다.
#
# 비교 대상 파일은 **인자로 받지 않고 그 프로세스의 명령줄에서 뽑는다.** 경로를 밖에서 받으면
# 배치가 바뀔 때마다 상수가 어긋나 엉뚱한 파일과 비교하게 된다(임시 운영 판본이 v3/·v2/ 경로를
# 상수로 들고 있던 자리다). 실제로 도는 파일과 비교해야 이 검사가 뜻을 갖는다.
stale_code() {
  local script_name="$1" pid started cmd script started_epoch mtime out=""
  while IFS='|' read -r pid started cmd; do
    [ -n "$pid" ] || continue
    # 명령줄에서 첫 .sh 경로를 뽑는다. `bash /경로/x.sh --flag ...` 모양이다.
    script=$(printf '%s' "$cmd" | tr ' ' '\n' | grep -m1 '\.sh$' || true)
    [ -n "$script" ] && [ -f "$script" ] || continue
    # 읽는 쪽도 같은 로케일이어야 한다. scan_toplevel 이 LC_ALL=C 로 찍은 모양을 그대로 되읽는다.
    started_epoch=$(LC_ALL=C date -j -f "%a %b %d %T %Y" "$started" +%s 2>/dev/null) || continue
    mtime=$(stat -f %m "$script" 2>/dev/null || stat -c %Y "$script" 2>/dev/null) || continue
    [ -n "$mtime" ] || continue
    if [ "$started_epoch" -lt "$mtime" ]; then
      out="${out} **낡은코드:$(basename "$script")(pid $pid)**"
    fi
  done < <(scan_toplevel "$script_name")
  printf '%s' "$out"
}

# 나 자신이 낡은 코드로 도는지. 남의 프로세스와 달리 내 기동 시각을 내가 알고 있으므로
# ps 를 다시 볼 필요가 없다.
stale_self() {
  local mtime
  mtime=$(stat -f %m "$SCRIPT_PATH" 2>/dev/null || stat -c %Y "$SCRIPT_PATH" 2>/dev/null) || return 0
  [ -n "$mtime" ] || return 0
  [ "$START_EPOCH" -lt "$mtime" ] && printf ' **낡은코드:%s(pid %s, 나 자신)**' "$(basename "$SCRIPT_PATH")" "$$"
  return 0
}

# 판 상태 한 줄 요약. **이 요약이 어떻게 나오든 깨우기는 무조건 한다.**
self_check() {
  local tl parsed disp ready load note="" comp rep
  tl=$( "$ORCA_BIN" orchestration task-list --run "$RUN_ID" --json 2>/dev/null )
  # **조회 실패를 "0장"으로 읽지 않는다.**
  # 여기서 `tasks` 라는 글자만 확인하면 `{"ok":false,...,"tasks":[]}` 를 "카드 0장"으로 읽는다.
  # 오늘 하루 잡은 부류가 정확히 그것이다 — 없다고 읽혀서 조용히 넘어가는 것.
  # 그래서 stall-reporter 와 같은 fail-closed 규칙을 쓴다: ok 가 참이 아니면 응답을 아예 안 쓴다.
  parsed=$(printf '%s' "$tl" | python3 -c '
import json,sys
try:
    root=json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
if not isinstance(root,dict) or root.get("ok") is not True:
    raise SystemExit(1)
result=root.get("result")
if not isinstance(result,dict):
    raise SystemExit(1)
tasks=result.get("tasks")
if not isinstance(tasks,list):
    raise SystemExit(1)
dispatched=idle=0
for t in tasks:
    if not isinstance(t,dict):
        raise SystemExit(1)
    s=t.get("status")
    if not isinstance(s,str) or not s:
        raise SystemExit(1)
    if s=="dispatched":
        dispatched+=1
    elif s in ("pending","ready"):
        idle+=1
print("%d %d" % (dispatched,idle))
' 2>/dev/null) || parsed=""

  load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  [ -n "$load" ] || load="?"

  # 감시 프로세스 생존. 여기서 넘기는 것은 **스크립트 파일 이름뿐**이고, "내 판인가"는
  # scan_toplevel 이 내 런타임 경로와 `--board <내 판>` 으로 가른다. 이름만으로 세면 다른 판의
  # companion 과 /tmp 아래 시험 사본까지 잡혀 **내 것이 죽어도 "살아 있음"으로 읽힌다.**
  comp=$(count_toplevel "conductor-companion.sh")
  rep=$(count_toplevel "stall-reporter.sh")
  note="${note}$(stale_code "conductor-companion.sh")"
  note="${note}$(stale_code "stall-reporter.sh")"
  note="${note}$(stale_self)"
  [ "$comp" -eq 0 ] && note="${note} **companion 죽음**"
  [ "$rep" -eq 0 ] && note="${note} **정체 신고기 죽음**"

  if [ -z "$parsed" ]; then
    printf '판정불가: 카드 장부 조회 실패 (0장으로 읽지 않는다) / 부하 %s / companion %s / 신고기 %s%s' \
      "$load" "$comp" "$rep" "$note"
    return 0
  fi
  disp=${parsed%% *}
  ready=${parsed##* }
  [ "$disp" = "0" ] && [ "$ready" != "0" ] && note="${note} **발령 0인데 대기 ${ready}장**"
  printf '발령 %s / 대기 %s / 부하 %s / companion %s / 신고기 %s%s' \
    "$disp" "$ready" "$load" "$comp" "$rep" "$note"
}

wake_once() {
  local summary text
  summary=$(self_check)
  # 심박은 깨우기 전에 적는다. 깨우기(terminal send)가 실패해도 이 프로세스가 살아 있다는
  # 사실 자체는 참이고, 신고기가 봐야 하는 것은 그 사실이다.
  heartbeat "check"
  log "WAKE $summary"
  text="[자가점검 깨우기] ${summary} — 도구로 판을 직접 확인하라: 검수 짝 / 발령 상한 / 로스터 생존 / 표본 재검. 이상 없으면 보고하지 말고 계속하라."
  if ! "$ORCA_BIN" terminal send --terminal "$SUPERVISOR" --text "$text" --json >/dev/null 2>&1; then
    log "WAKE_SEND_FAILED text"
    return 0
  fi
  # 붙여넣기와 실행을 나눠 보낸다. 감독 터미널이 긴 문장을 받는 도중 엔터가 끼면 잘린 채 실행된다.
  sleep 2
  "$ORCA_BIN" terminal send --terminal "$SUPERVISOR" --enter --json >/dev/null 2>&1 || log "WAKE_SEND_FAILED enter"
  return 0
}

log "START pid=$$ interval=${INTERVAL}s supervisor=$SUPERVISOR run=$RUN_ID runtime_dir=$RUNTIME_DIR heartbeat=$HEARTBEAT_LOG"
heartbeat "start"

if [ "$ONCE" -eq 1 ]; then
  wake_once
  exit 0
fi

while :; do
  sleep "$INTERVAL"
  wake_once
done
