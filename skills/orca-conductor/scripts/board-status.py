#!/usr/bin/env python3
"""판 현황 한 화면.

Why: 사람이 "판이 뭘 하고 있나"를 알려고 감독을 깨우면 감독 턴이 탄다
(2026-08-10 실사고). 이 스크립트는 감독을 건드리지 않고 읽기만 한다.

보는 순간 수집하므로 값이 낡을 수 없다. 곁눈질하려면:
    watch -n 15 board-status.py
"""

from __future__ import annotations

import json
import os
import re
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


def board_name(objective: str) -> str:
    """objective 는 '판이름: 목표...' 형식이 관례다. 아니면 앞부분을 쓴다."""
    head = (objective or "").split(":", 1)[0].strip()
    return head[:34] if head else "(이름 없음)"


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

        if ctx is None:
            ctx_text = paint(DIM, "Context 모름")
        elif ctx >= CONTEXT_WARN:
            ctx_text = paint(RED, f"Context {ctx}% ⚠ 교대 조건")
        else:
            ctx_text = f"Context {ctx}%"

        print(f"{BOLD}{name}{RESET}  {paint(DIM, run.get('id', ''))}")
        print(f"   감독   {ctx_text}" + (f"   주간 잔여 {weekly}" if weekly else ""))

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
            for task in tasks:
                if task.get("status") == "dispatched":
                    label = (task.get("display_name") or task.get("title") or "")[:56]
                    print(f"          {paint(CYAN, '▸')} {label}")

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


if __name__ == "__main__":
    sys.exit(main())
