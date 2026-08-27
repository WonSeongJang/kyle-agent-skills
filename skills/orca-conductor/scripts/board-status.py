#!/usr/bin/env python3
"""판 현황 한 화면.

Why: 사람이 "판이 뭘 하고 있나"를 알려고 감독을 깨우면 감독 턴이 탄다
(2026-08-10 실사고). 이 스크립트는 감독을 건드리지 않고 읽기만 한다.

보는 순간 수집하므로 값이 낡을 수 없다. 곁눈질하려면:
    board-status.py --watch        (기본 15초, --watch 30 처럼 초를 줄 수 있다)

macOS 에는 watch(1) 이 없어서 --watch 를 스크립트 안에 넣었다. brew 설치를 요구하지
않는다 — 감시 도구가 설치 하나를 더 요구하면 안 쓰게 된다.
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

ORCA_CANDIDATES = [
    os.environ.get("ORCA_BIN", ""),
    "/Users/fw_m1/Dev/orca-kyle/dist/mac-arm64/Orca Kyle.app/Contents/Resources/bin/orca-kyle",
    "/Applications/Orca.app/Contents/Resources/bin/orca",
    "orca",
]

# 중계기 일기가 이만큼 안 갱신되면 감시가 멈춘 것으로 본다.
RELAY_WARN_SEC = 600
RELAY_DEAD_SEC = 1200
# 표준의 감독 교대 조건 (mechanics.md).
CONTEXT_WARN = 80

RESET, DIM, BOLD = "\033[0m", "\033[2m", "\033[1m"
RED, YELLOW, GREEN, CYAN = "\033[31m", "\033[33m", "\033[32m", "\033[36m"


def color(enabled: bool):
    """색을 끈 상태에서는 굵기·흐림 코드까지 전부 지운다 — 파일로 넘길 때 깨지지 않게."""
    global RESET, DIM, BOLD
    if not enabled:
        RESET = DIM = BOLD = ""

    def painted(code: str, text: str) -> str:
        return f"{code}{text}{RESET}" if enabled else text

    return painted


def find_orca() -> str | None:
    for cand in ORCA_CANDIDATES:
        if not cand:
            continue
        if cand == "orca":
            found = subprocess.run(["which", "orca"], capture_output=True, text=True)
            if found.returncode == 0:
                return found.stdout.strip()
            continue
        if Path(cand).exists():
            return cand
    return None


def run_json(orca: str, args: list[str]) -> dict | None:
    """orca 명령 하나. 실패는 None 으로 돌려주고 절대 지어내지 않는다."""
    try:
        proc = subprocess.run(
            [orca, *args, "--json"], capture_output=True, text=True, timeout=25
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def age_text(seconds: float | None) -> str:
    if seconds is None:
        return "모름"
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}초 전"
    if seconds < 3600:
        return f"{seconds // 60}분 전"
    return f"{seconds // 3600}시간 {(seconds % 3600) // 60}분 전"


def parse_context_pct(preview: str) -> int | None:
    match = re.search(r"Context (\d+)% used", preview or "")
    return int(match.group(1)) if match else None


def parse_weekly_left(preview: str) -> str | None:
    match = re.search(r"weekly (\d+)% left", preview or "")
    return f"{match.group(1)}%" if match else None


def parse_model(preview: str) -> str | None:
    """상태바의 모델 이름. 예: 'gpt-5.6-sol medium · ~/Dev/...'"""
    match = re.search(r"(gpt-[\w.\-]+|opus|fable|zai/[\w.\-]+|kimi/[\w.\[\]\-]+)", preview or "")
    return match.group(1) if match else None


def autocompacts(model: str | None) -> bool | None:
    """상주 역할에서 자동 압축을 믿어도 되는 계열인가.

    True = 믿는다(gpt 계열), False = 교대가 필요하다, None = 모델을 못 읽었다.
    근거: mechanics.md '교대 기준은 모델 계열마다 다르다' (2026-08-10 kyle 결정).
    """
    if model is None:
        return None
    return model.startswith("gpt-")


def board_name(objective: str) -> str:
    """objective 는 '판이름: 목표...' 또는 '[판:판이름] 목표...' 형식이 관례다.

    대괄호 접두를 못 풀면 이름이 '[판'으로 잘려 companion·중계기 일기 매칭(이름 기준)이
    전부 빗나간다 — 2026-08-11 실사고: omo-deep-analysis-1 이 companion=0 으로 오보됐고
    그 판 감독이 실측 대조로 신고했다.
    """
    text = (objective or "").strip()
    m = re.match(r"^\[판[::]\s*([^\]]+)\]", text)
    if m:
        return m.group(1).strip()[:34]
    head = text.split(":", 1)[0].strip()
    return head[:34] if head else "(이름 없음)"


ORCHESTRATION_DB = (
    "/Users/fw_m1/Library/Application Support/Orca Kyle/orchestration.db"
)
# 사람이 읽어야 하는 편지 종류. status 는 진행 보고라 세되 앞세우지 않는다.
LOUD_TYPES = ("escalation", "decision_gate", "question", "ask", "worker_done")


def recent_mail(run_id: str) -> list[tuple[str, str, str]] | None:
    """이 판 우편함의 최근 편지 몇 통. (종류, 제목, 시각). 못 읽으면 None.

    Why: 2026-08-10 실사고 — 사전검증이 NOT_READY 를 보냈는데 40분간 아무도 안 읽었고,
    대시보드는 '대기 1' 만 보여줘서 막힌 것과 할 일이 남은 것을 구분할 수 없었다.
    카드와 섞지 않고 우편함으로 따로 세운다 (kyle 지시).

    **'안 읽음 N통' 은 세지 않는다 (2026-08-10 kyle 지적).** `messages.read` 는 편지당
    불리언 하나여서 소비자별이 아니다. 이 판의 소비자는 감독·중계기·companion·슈퍼 넷인데,
    누구든 먼저 건드리면 꺼지므로 "감독이 안 읽었다" 를 표현할 수 없다. 그 숫자를 보여주면
    틀린 뜻을 정확한 숫자처럼 보이게 한다.

    소비자별 도달 판정은 판 mailbox-relay-1 의 B2(소비자별 커서로 통일)가 자리잡은 뒤
    그 계약을 읽어서 붙인다. 지금 DB 에는 커서 테이블이 아직 없다(실측).
    그때까지는 **사실인 것만** 보여준다 — 최근에 어떤 편지가 오갔는가.

    'alive' 하트비트는 생존 신호라 사람이 읽을 것이 아니므로 제외한다.
    """
    if not Path(ORCHESTRATION_DB).exists():
        return None
    try:
        with sqlite3.connect(f"file:{ORCHESTRATION_DB}?mode=ro", uri=True, timeout=5) as db:
            rows = db.execute(
                "select type, subject, created_at from messages where run_id=? "
                "and type<>'heartbeat' and subject<>'alive' "
                "order by sequence desc limit 3",
                (run_id,),
            ).fetchall()
    except sqlite3.Error:
        return None
    return [(row[0] or "", row[1] or "", row[2] or "") for row in rows]


def seat_warning(task: dict, terminals: dict | None) -> tuple[str, str]:
    """장부-실물 대조: 도는 카드가 가리키는 자리가 실제로 있는가.

    (색, 문구) 를 돌려주며 문제가 없으면 문구가 빈 문자열이다.
    살아 있는 것과 장부가 맞는 것은 다른 확인이다 — 2026-08-10 실사고에서
    중계기가 멀쩡히 일기를 쓰는 동안 카드는 죽은 자리를 가리키고 있었다.

    한계: 옛 자리가 아직 살아 있는데 역할만 옮겨간 경우는 못 잡는다.
    그건 roster resolve 를 판마다 더 불러야 해서, 실제로 관측되면 그때 넣는다.
    """
    if terminals is None:
        return DIM, "  (자리 확인 불가 — 터미널 목록을 못 읽음)"
    seat = task.get("assignee_handle")
    if not seat:
        return YELLOW, "  ⚠ 담당 자리가 카드에 없음"
    if seat not in terminals:
        return RED, f"  ⚠ 장부 어긋남 — 카드가 가리키는 {seat[:18]}… 자리가 없다"
    return "", ""


def collect_terminals(orca: str) -> tuple[dict[str, dict] | None, str | None]:
    data = run_json(orca, ["terminal", "list"])
    if data is None:
        return None, "terminal list 실패"
    items = data.get("result", {}).get("terminals") or data.get("terminals") or []
    if not isinstance(items, list):
        return None, "terminal list 형식이 예상과 다름"
    return {t.get("handle"): t for t in items if t.get("handle")}, None


def collect_relay_logs() -> dict[str, tuple[Path, float]]:
    """판이름 -> (일기 경로, 마지막 갱신 후 경과 초)."""
    out: dict[str, tuple[Path, float]] = {}
    now = time.time()
    for path in Path("/Users/fw_m1/Dev").glob("*/.orca/relay-logs/*.relay-log.md"):
        name = path.name[: -len(".relay-log.md")]
        try:
            out[name] = (path, now - path.stat().st_mtime)
        except OSError:
            continue
    return out


def collect_helpers() -> dict[str, list[int]]:
    """판이름 -> companion PID 목록. 자식 셸이 껴서 부풀지 않게 --board 로만 센다."""
    out: dict[str, list[int]] = {}
    try:
        proc = subprocess.run(
            ["ps", "-axo", "pid=,command="], capture_output=True, text=True, timeout=10
        )
    except (subprocess.TimeoutExpired, OSError):
        return out
    for line in proc.stdout.splitlines():
        if "conductor-companion.sh" not in line:
            continue
        match = re.search(r"--board\s+(\S+)", line)
        if not match:
            continue
        pid = line.strip().split(None, 1)[0]
        if pid.isdigit():
            out.setdefault(match.group(1), []).append(int(pid))
    return out


def system_line() -> str:
    load = "모름"
    try:
        one, five, fifteen = os.getloadavg()
        load = f"{one:.2f} / {five:.2f} / {fifteen:.2f}"
    except OSError:
        pass
    cpus = os.cpu_count() or 0
    free = "모름"
    try:
        proc = subprocess.run(["memory_pressure"], capture_output=True, text=True, timeout=10)
        match = re.search(r"free percentage:\s*(\d+)%", proc.stdout)
        if match:
            free = f"{match.group(1)}%"
    except (subprocess.TimeoutExpired, OSError):
        pass
    return f"부하 {load}  (논리 CPU {cpus})    메모리 여유 {free}"


def main() -> int:
    paint = color(sys.stdout.isatty() and "--no-color" not in sys.argv)

    orca = find_orca()
    if orca is None:
        print("orca 실행 파일을 못 찾았다. ORCA_BIN 을 지정하라.", file=sys.stderr)
        return 2

    print(f"{BOLD}판 현황{RESET}  {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(system_line())
    print()

    runs_data = run_json(orca, ["orchestration", "run-list"])
    terminals, term_err = collect_terminals(orca)
    relay_logs = collect_relay_logs()
    helpers = collect_helpers()

    if runs_data is None:
        print(paint(RED, "run-list 를 못 읽었다 — 아래 판 목록은 비어 있는 게 아니라 '모름'이다."))
        return 1
    if term_err:
        print(paint(RED, f"{term_err} — 감독 생존·Context 는 '모름'으로 둔다."))

    runs = runs_data.get("result", {}).get("runs") or []
    live, dormant = [], []
    for run in runs:
        handle = run.get("coordinator_handle")
        term = terminals.get(handle) if (terminals and handle) else None
        (live if term else dormant).append((run, term))

    if not live:
        print(paint(YELLOW, "감독 터미널이 살아 있는 판이 없다."))

    for run, term in live:
        name = board_name(run.get("objective", ""))
        preview = (term or {}).get("preview", "")
        ctx = parse_context_pct(preview)
        weekly = parse_weekly_left(preview)

        model = parse_model(preview)
        compacts = autocompacts(model)

        if ctx is None:
            ctx_text = paint(DIM, "Context 모름")
        elif ctx < CONTEXT_WARN:
            ctx_text = f"Context {ctx}%"
        elif compacts is True:
            # gpt 계열은 80% 를 넘겨도 압축에 맡긴다 — 경고가 아니라 관찰이다.
            ctx_text = paint(YELLOW, f"Context {ctx}% (압축에 맡김 · 계속 오르면 교대)")
        elif compacts is False:
            ctx_text = paint(RED, f"Context {ctx}% ⚠ 교대 필요 — {model} 은 자동 압축을 기대할 수 없다")
        else:
            ctx_text = paint(YELLOW, f"Context {ctx}% (모델을 못 읽어 교대 여부 판단 불가)")

        model_text = f"   {paint(DIM, model)}" if model else ""
        print(f"{BOLD}{name}{RESET}  {paint(DIM, run.get('id', ''))}")
        print(f"   감독   {ctx_text}{model_text}" + (f"   주간 잔여 {weekly}" if weekly else ""))

        tasks_data = run_json(
            orca, ["orchestration", "task-list", "--run", run.get("id", "")]
        )
        if tasks_data is None:
            print(f"   카드   {paint(RED, '못 읽음 (0개가 아니라 모름)')}")
        else:
            tasks = tasks_data.get("result", {}).get("tasks") or []
            buckets: dict[str, int] = {}
            for task in tasks:
                buckets[task.get("status") or "?"] = buckets.get(task.get("status") or "?", 0) + 1
            running = buckets.get("dispatched", 0)
            waiting = buckets.get("ready", 0)
            failed = buckets.get("failed", 0)
            done = buckets.get("completed", 0)
            bits = [f"도는 중 {running}", f"대기 {waiting}"]
            if failed:
                bits.append(paint(YELLOW, f"실패 {failed}"))
            bits.append(paint(DIM, f"완료 {done}"))
            print("   카드   " + "   ".join(bits))

            # 장부-실물 대조: 도는 카드가 가리키는 자리가 실제로 있는가.
            # 살아 있는 것과 장부가 맞는 것은 다른 확인이다 — 2026-08-10 실사고에서
            # 중계기가 멀쩡히 일기를 쓰는 동안 카드는 죽은 자리를 가리키고 있었다.
            # 한계: 옛 자리가 아직 살아 있는데 역할만 옮겨간 경우는 이 검사로 못 잡는다.
            # 그건 roster resolve 를 판마다 더 불러야 해서, 실제로 관측되면 그때 넣는다.
            for task in tasks:
                if task.get("status") != "dispatched":
                    continue
                label = (task.get("display_name") or task.get("title") or "")[:56]
                code, note = seat_warning(task, terminals)
                mark = paint(code, note) if note else ""
                print(f"          {paint(CYAN, '▸')} {label}{mark}")

        mail = recent_mail(run.get("id", ""))
        if mail is None:
            print(f"   우편함 {paint(DIM, '못 읽음 — 비어 있는 게 아니라 모름')}")
        elif not mail:
            print(f"   우편함 {paint(DIM, '오간 편지 없음')}")
        else:
            print(f"   우편함 {paint(DIM, '최근 편지')}")
            for kind, subject, when in mail:
                stamp = when[11:16] if len(when) >= 16 else ""
                code = RED if kind in LOUD_TYPES else ""
                tag = f"[{kind}] " if kind and kind != "status" else ""
                line = f"{tag}{subject[:58]}"
                print(f"          {paint(CYAN, '▸')} {paint(DIM, stamp)} {paint(code, line) if code else line}")

        entry = relay_logs.get(name)
        if entry is None:
            print(f"   중계기 {paint(YELLOW, '일기 없음 — 중계기를 안 세웠거나 판 이름이 다르다')}")
        else:
            _, age = entry
            text = f"일기 {age_text(age)}"
            if age > RELAY_DEAD_SEC:
                print(f"   중계기 {paint(RED, text + '  ⚠ 감시 멈춤')}")
            elif age > RELAY_WARN_SEC:
                print(f"   중계기 {paint(YELLOW, text + '  (느림)')}")
            else:
                print(f"   중계기 {paint(GREEN, text)}")

        pids = helpers.get(name, [])
        if pids:
            print(f"   깨우미 {paint(GREEN, 'companion 살아있음')} {paint(DIM, str(pids))}")
        else:
            print(f"   깨우미 {paint(RED, 'companion 없음 — 완료 편지가 와도 감독이 안 깨어난다')}")
        print()

    if dormant:
        print(paint(DIM, f"잠든 판 {len(dormant)}개 (감독 터미널 없음) — 자세히 보려면 --all"))
        if "--all" in sys.argv:
            for run, _ in dormant:
                print(paint(DIM, f"   {board_name(run.get('objective', '')):36} {run.get('id', '')}"))
    return 0


def watch_seconds() -> float | None:
    """--watch [초]. 초를 안 주면 15초."""
    if "--watch" not in sys.argv:
        return None
    idx = sys.argv.index("--watch")
    if idx + 1 < len(sys.argv):
        try:
            return max(3.0, float(sys.argv[idx + 1]))
        except ValueError:
            pass
    return 15.0


if __name__ == "__main__":
    every = watch_seconds()
    if every is None:
        sys.exit(main())
    try:
        while True:
            # 화면을 지우되 스크롤백은 남긴다 — 직전 화면을 위로 올려 볼 수 있게.
            sys.stdout.write("\033[H\033[2J")
            sys.stdout.flush()
            main()
            print(f"\n{DIM}{every:.0f}초마다 갱신 · Ctrl+C 로 종료{RESET}")
            time.sleep(every)
    except KeyboardInterrupt:
        print()
        sys.exit(0)
