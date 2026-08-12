#!/usr/bin/env python3
"""판 현황 로컬 웹 대시보드.

Why: kyle이 판 진행을 보려고 감독을 깨우면 감독 턴이 탄다 (2026-08-10 실사고).
board-status.py 는 터미널 한 번 흘끗용이고, 이 서버는 브라우저 탭에 계속 띄워두는
용도다. 카드 목록 + 중계기 일기 + 우편함(보낸이→받는이) + 결정 관문 + 터미널을
사이드바 화면 하나로 보여준다. 감독·중계기·companion 어느 것도 건드리지 않고
읽기만 한다.

우편함은 `orca orchestration inbox` 만 쓴다 — 읽음 처리(ack)가 없는 조회 명령이라
감독이 받을 편지를 가로채지 않는다. `check`(기본 모드)는 여기서 절대 쓰지 않는다.

결정 관문을 보여주는 이유: 관문이 장부에만 생기고 편지가 안 가서 판 전체가
조용히 대기한 실사고가 있다 (2026-08-05 고아 관문, docs/TODO.md).

실행:
    board-dashboard.py                  (기본 http://127.0.0.1:8787)
    board-dashboard.py --port 9000
    board-dashboard.py --host 0.0.0.0   (같은 와이파이의 폰에서도 볼 때)

표준 파이썬만 쓴다. 설치가 하나라도 필요하면 안 쓰게 된다.
"""

from __future__ import annotations

import datetime
import importlib.util
import json
import os
import re
import sqlite3
import subprocess
import sys
import textwrap
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# board-status.py 의 수집 함수를 그대로 쓴다 — 수집 로직은 한 곳(board-status.py)만 고친다.
_spec = importlib.util.spec_from_file_location(
    "board_status", Path(__file__).resolve().with_name("board-status.py")
)
assert _spec is not None and _spec.loader is not None
bs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bs)

COLLECT_MIN_INTERVAL = 8.0  # 초. 새로고침 연타가 orca 서브프로세스 폭주로 이어지지 않게.

# 마지막 수집이 만든 명패 해석기 — 옛 편지 조회(/api/mail)가 재사용한다.
LAST_MAPS: dict = {"resolve": None, "runs": {}}
RELAY_TAIL_LINES = 60
INBOX_LIMIT = 80
BOARD_PREFIX = re.compile(r"^\[판:[^\]]*\]\s*")


def strip_board_prefix(title: str) -> str:
    return BOARD_PREFIX.sub("", title or "").strip()


def relay_tail(path: Path) -> list[str]:
    """일기 파일 꼬리만 읽는다. 265KB 전체를 매번 읽지 않는다."""
    try:
        with path.open("rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 24576))
            chunk = f.read().decode("utf-8", errors="replace")
    except OSError:
        return []
    lines = chunk.splitlines()
    if len(lines) > 1:
        lines = lines[1:]  # 앞쪽 잘린 반 줄 제거
    return lines[-RELAY_TAIL_LINES:]


TASK_TEXT_MAX = 6000  # 카드 사양·결과 전문 표시 상한 (전체 payload 폭주 방지)


def long_text(value) -> str | None:
    if value is None:
        return None
    text = str(value)
    if len(text) > TASK_TEXT_MAX:
        return text[:TASK_TEXT_MAX] + f"\n… (총 {len(text)}자 — 전문은 orca orchestration dispatch-show)"
    return text


def last_preview_line(preview: str) -> str:
    for line in reversed((preview or "").splitlines()):
        if line.strip():
            return line.strip()
    return ""


def collect_companions_detail() -> dict[str, list[dict]]:
    """판이름 -> [{pid, cmd}]. **PPID=1 상주만 센다** — companion 이 주기 작업 중 fork 한
    자식(bash 재실행)도 같은 명령줄로 보여 2개로 오보된다 (2026-08-11 omo 판 감독 실측 신고).
    감시 표준("companion 은 PPID=1 인 상주 것만 센다")과 동일 기준."""
    out: dict[str, list[dict]] = {}
    try:
        proc = subprocess.run(
            ["ps", "-axo", "pid=,ppid=,command="], capture_output=True, text=True, timeout=10
        )
    except (subprocess.TimeoutExpired, OSError):
        return out
    for line in proc.stdout.splitlines():
        if "conductor-companion.sh" not in line:
            continue
        parts = line.split(None, 2)
        if len(parts) < 3 or not parts[0].isdigit() or parts[1] != "1":
            continue
        match = re.search(r"--board\s+(\S+)", parts[2])
        if not match:
            continue
        out.setdefault(match.group(1), []).append(
            {"pid": int(parts[0]), "cmd": parts[2].strip()[:200]}
        )
    return out


# 보조 감시 표면 — "무엇이 판을 지키고 있나"를 추측 없이 ps 실측으로 보여준다
# (2026-08-12 kyle: "슈퍼감독/프로젝트 감독 중심으로 어떤 보조도구들이 돌고있는지 시각화").
# 원본은 살아 있는 프로세스와 심박 파일이고, 이 표면은 그것을 렌더링만 한다.
WATCHER_SPECS = [
    # (스크립트 지문, 쉬운 이름, 한 줄 설명, super급 여부)
    ("relay-patrol.py", "중계기", "감독 화면을 5분마다 순찰해 무진행 판정 (애매할 때만 AI 호출)", False),
    ("stall-reporter.sh", "정체 신고기", "판이 비었는데 새 카드가 없는 상태·깨우기 부재를 슈퍼에게 편지로 신고", False),
    ("supervisor-waker.sh", "감독 자가 점검기", "편지가 없어도 30분마다 감독을 깨움 — 영원한 침묵 방지", False),
    ("conductor-companion.sh", "companion (배달부)", "감독 명패에 편지가 도착하면 즉시 감독을 깨움", False),
    ("diag-watch.py", "판정 감시 (슈퍼)", "대시보드 자동 판정 bad·정체를 5분마다 확인해 슈퍼감독을 깨움", True),
]


def _relay_judge_model() -> str:
    """중계기 판정 모델 — 원본은 relay-patrol.py 의 JUDGE_MODEL 상수. 복제하지 않고 읽는다."""
    try:
        src = (Path(__file__).parent / "relay-patrol.py").read_text(encoding="utf-8")
        m = re.search(r'JUDGE_MODEL\s*=\s*"([^"]+)"', src)
        return m.group(1) if m else "모름"
    except OSError:
        return "모름"


def _watcher_engine(pat: str) -> str:
    """스크립트인지 AI 인지, AI 면 어떤 모델인지 — kyle 2026-08-12 요청."""
    if pat == "relay-patrol.py":
        return f"Python 스크립트 + AI 판정: {_relay_judge_model()} (애매할 때만, command-code CLI)"
    if pat == "diag-watch.py":
        return "Python 스크립트 (AI 없음)"
    return "셸 스크립트 (AI 없음)"
# 살아 있는 판이라면 이 넷은 반드시 떠 있어야 한다 — 없으면 화면에서 "빠짐"으로 경고.
WATCHER_EXPECTED = ["relay-patrol.py", "stall-reporter.sh", "supervisor-waker.sh", "conductor-companion.sh"]


def _log_last_age(path: Path, fmts: list[tuple[str, int]]) -> float | None:
    """로그 마지막 줄의 타임스탬프 나이(초). 못 읽으면 None(모름)."""
    try:
        line = path.read_text(encoding="utf-8", errors="replace").rstrip().rsplit("\n", 1)[-1]
    except OSError:
        return None
    for fmt, ntok in fmts:
        try:
            token = " ".join(line.split()[:ntok])
            ts = datetime.datetime.strptime(token, fmt)
            return max(0.0, time.time() - ts.timestamp())
        except (ValueError, IndexError):
            continue
    return None


def collect_watchers() -> dict:
    """ps 실측으로 보조 감시 프로세스를 판별로 묶는다. companion 은 PPID=1 상주만."""
    out: dict = {"super": [], "boards": {}, "collected_at": time.strftime("%H:%M:%S")}
    try:
        proc = subprocess.run(
            ["ps", "-axo", "pid=,ppid=,etime=,command="], capture_output=True, text=True, timeout=10
        )
    except (subprocess.TimeoutExpired, OSError):
        return out
    for line in proc.stdout.splitlines():
        for pat, label, desc, is_super in WATCHER_SPECS:
            if pat not in line or "grep" in line:
                continue
            parts = line.split(None, 3)
            if len(parts) < 4 or not parts[0].isdigit():
                continue
            pid, ppid, etime, cmd = int(parts[0]), parts[1], parts[2], parts[3]
            if pat == "conductor-companion.sh" and ppid != "1":
                continue  # fork 자식 오계수 방지 — collect_companions_detail 과 같은 기준
            entry: dict = {"kind": pat, "label": label, "desc": desc, "pid": pid,
                           "ppid1": ppid == "1", "etime": etime, "fresh_age_sec": None,
                           "fresh_label": None, "engine": _watcher_engine(pat)}
            match = re.search(r"--board\s+(\S+)", cmd)
            board = match.group(1) if match else None
            relay_log = re.search(r"--relay-log\s+(\S+)", cmd)
            repo_root = re.search(r"--repo-root\s+(\S+)", cmd)
            if pat == "relay-patrol.py" and board:
                # 중계기는 --relay-log 를 받지 않고 --repo-root 에서 경로를 스스로 만든다.
                log_path = None
                if relay_log:
                    log_path = Path(relay_log.group(1))
                elif repo_root:
                    log_path = Path(repo_root.group(1)) / f".orca/relay-logs/{board}.relay-log.md"
                if log_path:
                    entry["fresh_age_sec"] = _log_last_age(log_path, [("%Y-%m-%d %H:%M:%S %z", 3)])
                    entry["fresh_label"] = "최근 순찰"
            elif pat == "supervisor-waker.sh" and relay_log:
                hb = Path(relay_log.group(1).replace(".relay-log.md", ".waker-heartbeat.log"))
                entry["fresh_age_sec"] = _log_last_age(hb, [("%Y-%m-%dT%H:%M:%S%z", 1)])
                entry["fresh_label"] = "최근 심박"
            elif pat == "stall-reporter.sh" and board:
                state = Path.home() / f".cache/rottie/stall-reporter/{board}.state"
                try:
                    entry["fresh_age_sec"] = max(0.0, time.time() - state.stat().st_mtime)
                    entry["fresh_label"] = "최근 점검"
                except OSError:
                    pass
            if is_super or not board:
                out["super"].append(entry)
            else:
                out["boards"].setdefault(board, []).append(entry)
    # 판정 감시(diag-watch)는 상주가 아니라 5분마다 잠깐 도는 주기 실행형 — ps 순간
    # 포착이 안 되면 "없음"이 아니라 실행 방식을 그대로 적는다 (모름을 모름으로).
    if not any(e["kind"] == "diag-watch.py" for e in out["super"]):
        out["super"].append({
            "kind": "diag-watch.py", "label": "판정 감시 (슈퍼)", "pid": None, "ppid1": None,
            "etime": None,
            "desc": "대시보드 자동 판정 bad·정체를 5분마다 확인해 슈퍼감독을 깨움",
            "fresh_age_sec": None, "fresh_label": None, "engine": _watcher_engine("diag-watch.py"),
            "note": "주기 실행형 — 순간 ps 부재는 정상일 수 있음 (원본: 슈퍼 세션)",
        })
    # Monitor 는 슈퍼 세션 내부(하네스 작업)라 ps 로 실측할 수 없다 — 모름을 모름으로 표기.
    out["super"].append({
        "kind": "monitor", "label": "Monitor (슈퍼)", "pid": None, "ppid1": None, "etime": None,
        "desc": "편지·부하·메모리·프록시·잠자기를 감시해 슈퍼감독 세션을 깨움",
        "fresh_age_sec": None, "fresh_label": None,
        "engine": "슈퍼감독 세션 내장 감시 (Claude) — 규칙 판정은 스크립트, 대응 판단은 슈퍼감독",
        "note": "세션 내부 가동 — ps 실측 불가 (원본: 슈퍼 세션)",
    })
    return out


def system_stats() -> dict:
    stats: dict = {"load": None, "cpus": os.cpu_count() or 0, "mem_free": None,
                   "disk_avail": None, "disk_used_pct": None}
    try:
        one, five, fifteen = os.getloadavg()
        stats["load"] = f"{one:.2f} / {five:.2f} / {fifteen:.2f}"
    except OSError:
        pass
    try:
        proc = subprocess.run(["memory_pressure"], capture_output=True, text=True, timeout=10)
        match = re.search(r"free percentage:\s*(\d+)%", proc.stdout)
        if match:
            stats["mem_free"] = f"{match.group(1)}%"
    except (subprocess.TimeoutExpired, OSError):
        pass
    try:
        proc = subprocess.run(
            ["df", "-k", "/System/Volumes/Data"], capture_output=True, text=True, timeout=10
        )
        fields = proc.stdout.strip().splitlines()[-1].split()
        if len(fields) >= 5:
            stats["disk_avail"] = f"{int(fields[3]) / 1024 / 1024:.0f}GB"
            stats["disk_used_pct"] = fields[4]
    except (subprocess.TimeoutExpired, OSError, ValueError, IndexError):
        pass
    return stats


def collect(orca: str) -> dict:
    errors: list[str] = []
    out: dict = {
        "collected_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "system": system_stats(),
        "watchers": collect_watchers(),
        "boards": [],
        "dormant": [],
        "messages": None,  # None = 못 읽음(모름). 빈 목록과 구분한다.
        "terminals": [],
        "errors": errors,
    }

    runs_data = bs.run_json(orca, ["orchestration", "run-list"])
    terminals, term_err = bs.collect_terminals(orca)
    relay_logs = bs.collect_relay_logs()
    companions = collect_companions_detail()
    inbox = bs.run_json(orca, ["orchestration", "inbox", "--limit", str(INBOX_LIMIT)])

    if term_err:
        errors.append(f"{term_err} — 감독 생존·Context 는 '모름'으로 둔다.")

    runs = []
    run_names: dict[str, str] = {}
    handle_names: dict[str, str] = {}  # 명패(handle) -> 사람이 읽는 이름
    task_roles: dict[str, str] = {}    # 카드 id -> "역할 · 카드 · 판" (worker 장부 역추적용)
    if runs_data is None:
        errors.append("run-list 를 못 읽었다 — 판 목록은 비어 있는 게 아니라 '모름'이다.")
    else:
        runs = runs_data.get("result", {}).get("runs") or []
        for run in runs:
            name = bs.board_name(run.get("objective", ""))
            run_names[run.get("id", "")] = name
            sup = "슈퍼감독" if "super" in name.lower() else f"감독 · {name}"
            # 판 앞(run:) 주소로 온 편지는 결국 그 판의 감독이 소비한다 —
            # "판 우편함" 표기는 어색하다 (2026-08-10 kyle). 기술 주소는 툴팁에 남는다.
            handle_names[f"run:{run.get('id', '')}"] = sup
            if run.get("coordinator_handle"):
                handle_names[run["coordinator_handle"]] = sup

    for run in runs:
        handle = run.get("coordinator_handle")
        term = terminals.get(handle) if (terminals and handle) else None
        name = bs.board_name(run.get("objective", ""))
        if term is None:
            # run-list 에는 열림/닫힘 상태 필드가 없다 (2026-08-10 실측). 감독 터미널이
            # 사라진 run 은 "잠든 판"이 아니라 끝난 판·일회용 시험이 섞인 지난 기록이다.
            out["dormant"].append(
                {"name": name, "run_id": run.get("id", ""), "created_at": run.get("created_at")}
            )
            continue

        preview = term.get("preview", "")
        model = bs.parse_model(preview)
        board: dict = {
            "name": name,
            "run_id": run.get("id", ""),
            "context_pct": bs.parse_context_pct(preview),
            "context_warn": bs.CONTEXT_WARN,
            "model": model,
            # True=gpt 계열(압축에 맡김), False=교대 필요, None=모델 못 읽음 (board-status.py 기준)
            "autocompacts": bs.autocompacts(model),
            "weekly_left": bs.parse_weekly_left(preview),
            "cards": None,   # 상태별 개수. None = 모름
            "tasks": None,   # 카드 전체 목록. None = 모름
            "gates": None,   # 결정 관문. None = 모름
            "relay": None,
            "companions": companions.get(name, []),
        }

        tasks_data = bs.run_json(
            orca, ["orchestration", "task-list", "--run", run.get("id", "")]
        )
        relay_handle = None
        if tasks_data is not None:
            raw_tasks = tasks_data.get("result", {}).get("tasks") or []
            buckets: dict[str, int] = {}
            tasks = []
            for task in raw_tasks:
                status = task.get("status") or "?"
                buckets[status] = buckets.get(status, 0) + 1
                title = strip_board_prefix(
                    task.get("display_name") or task.get("task_title") or ""
                )
                creator = task.get("created_by_terminal_handle")
                if creator:
                    # 카드를 만드는 것은 감독이다. 교대로 물러난 전임 감독 명패도 이걸로 풀린다.
                    # setdefault — 현직 감독 이름(coordinator_handle 매핑)을 덮지 않는다.
                    handle_names.setdefault(creator, f"감독 · {name}")
                # 역할 · 카드번호 · 판 형태로 푼다 (kyle: 역할이 보여야 한다).
                if "중계기" in title or "relay" in title.lower():
                    role = "중계기"
                elif "검수" in title:
                    role = "검수자"
                else:
                    role = "작업자"
                head = title.split()[0] if title.split() else ""
                short = head if re.fullmatch(r"[\w.\-]+", head) else title[:16]
                label = f"{role} · {short} · {name}" if role != "중계기" else f"중계기 · {name}"
                if task.get("id"):
                    task_roles[task["id"]] = label
                assignee = task.get("assignee_handle")
                if assignee:
                    # 나중 카드가 이긴다 — 같은 터미널이 카드를 갈아탄 경우 최신 역할이 이름이 된다.
                    handle_names[assignee] = label
                    if task.get("dispatch_id"):
                        # 편지 주소가 dispatch:ctx_... 로 오는 경우도 같은 역할로 풀린다.
                        handle_names[f"dispatch:{task['dispatch_id']}"] = label
                    if status == "dispatched" and role == "중계기":
                        relay_handle = assignee
                tasks.append(
                    {
                        "id": task.get("id"),
                        "title": title,
                        "status": status,
                        "assignee_handle": assignee,
                        "created_at": task.get("created_at"),
                        "completed_at": task.get("completed_at"),
                        "spec": long_text(task.get("spec")),
                        "result": long_text(task.get("result")),
                    }
                )
            board["cards"] = buckets
            board["tasks"] = tasks
        else:
            errors.append(f"{name}: task-list 를 못 읽었다 — 카드 목록은 '모름'이다.")

        gates_data = bs.run_json(
            orca, ["orchestration", "gate-list", "--run", run.get("id", "")]
        )
        if gates_data is not None:
            board["gates"] = gates_data.get("result", {}).get("gates") or []
        else:
            errors.append(f"{name}: gate-list 를 못 읽었다 — 결정 관문은 '모름'이다.")

        entry = relay_logs.get(name)
        relay_term = terminals.get(relay_handle) if (terminals and relay_handle) else None
        if entry is not None or relay_term is not None:
            relay: dict = {"workdir": None, "terminal_title": None}
            if relay_term is not None:
                relay["workdir"] = relay_term.get("worktreePath")
                relay["terminal_title"] = relay_term.get("title")
            if entry is not None:
                path, age = entry
                relay.update(
                    {
                        "age_sec": int(age),
                        "age_text": bs.age_text(age),
                        "warn_sec": bs.RELAY_WARN_SEC,
                        "dead_sec": bs.RELAY_DEAD_SEC,
                        "path": str(path),
                        "tail": relay_tail(path),
                    }
                )
            board["relay"] = relay
        out["boards"].append(board)

    # 완료된 카드는 task-list 에 담당 명패가 안 남는다 — worker 장부(worker-list)의
    # 카드↔터미널 연결로 역추적한다. setdefault 라서 현재 배정(최신 역할)이 항상 이긴다.
    workers_data = bs.run_json(orca, ["orchestration", "worker-list"])
    if workers_data is not None:
        for worker in workers_data.get("result", {}).get("workers") or []:
            label = task_roles.get(worker.get("taskId"))
            whandle = worker.get("agentTerminalHandle")
            if label and whandle:
                handle_names.setdefault(whandle, label)

    # 그래도 남는 구멍은 원장 DB의 과거 발령 기록(dispatch_contexts)으로 메꾼다.
    if LEDGER_DB.exists():
        try:
            with ledger_conn() as conn:
                rows = conn.execute(
                    "SELECT id, task_id, assignee_handle FROM dispatch_contexts"
                    " WHERE assignee_handle IS NOT NULL ORDER BY rowid"
                ).fetchall()
            past: dict[str, str] = {}
            for row in rows:
                label = task_roles.get(row["task_id"])
                if label:
                    past[row["assignee_handle"]] = label  # 나중 발령이 이긴다
                    past[f"dispatch:{row['id']}"] = label  # dispatch:ctx_... 주소도 같은 역할
            for whandle, label in past.items():
                handle_names.setdefault(whandle, label)
        except sqlite3.Error:
            pass  # 원장을 못 읽어도 이름 풀기만 조금 덜 될 뿐, 화면은 계속 살아 있어야 한다

    # 카드 담당 이름까지 다 모은 뒤에야 편지의 보낸이/받는이를 풀 수 있다.
    def resolve_handle(handle: str | None) -> str:
        if not handle:
            return "?"
        if handle in handle_names:
            return handle_names[handle]
        if terminals and handle in terminals:
            return f"터미널 · {terminals[handle].get('title') or handle[:13]}"
        if handle.startswith("term_"):
            return f"터미널(사라짐) · {handle[5:13]}"
        return handle[:24]

    LAST_MAPS["resolve"] = resolve_handle
    LAST_MAPS["runs"] = run_names

    if inbox is not None:
        msgs = inbox.get("result", {}).get("messages") or []
        out["messages"] = [
            {
                "id": m.get("id"),
                "board": run_names.get(m.get("run_id", ""), m.get("run_id", "?")),
                "run_id": m.get("run_id"),
                "type": m.get("type"),
                "priority": m.get("priority"),
                "subject": m.get("subject"),
                "body": m.get("body"),
                "read": bool(m.get("read")),
                "created_at": m.get("created_at"),
                "from_name": resolve_handle(m.get("from_handle")),
                "to_name": resolve_handle(m.get("to_handle")),
                "from_handle": m.get("from_handle"),
                "to_handle": m.get("to_handle"),
            }
            for m in msgs
        ]
    else:
        errors.append("우편함(inbox)을 못 읽었다 — 비어 있는 게 아니라 '모름'이다.")

    # 카드 목록의 담당은 터미널 이름으로 푼다 — 역할명은 카드 제목과 겹쳐서 정보가 없다.
    for board in out["boards"]:
        for task in board["tasks"] or []:
            handle = task.get("assignee_handle")
            if not handle:
                task["assignee"] = ""
            elif terminals and handle in terminals:
                task["assignee"] = terminals[handle].get("title") or handle[:13]
            else:
                task["assignee"] = f"터미널(사라짐) {handle[5:13]}"

    if terminals:
        now_ms = time.time() * 1000
        for handle, term in terminals.items():
            last = term.get("lastOutputAt")
            out["terminals"].append(
                {
                    "title": term.get("title") or "",
                    "role": handle_names.get(handle, ""),
                    "worktree": term.get("worktreePath") or "",
                    "connected": bool(term.get("connected")),
                    "age_text": bs.age_text((now_ms - last) / 1000 if last else None),
                    "preview": last_preview_line(term.get("preview", ""))[:160],
                }
            )
        out["terminals"].sort(key=lambda t: (t["role"] == "", t["title"]))
    diagnose(out)
    return out


# ── 자동 판정 ──────────────────────────────────────────────────────────────
# 판별 규칙을 서버 한 곳에 둔다 — 화면(판 페이지)과 슈퍼감독 감시가 같은 판정을
# 읽는다 (2026-08-11 kyle: "이슈를 자동으로 판정해 주면 일일이 안 물어봐도 된다").
# 문턱은 발명하지 않는다: 묵은 편지 600/1200초(중계기 일기와 동일), 중계기
# warn/dead, 무진행은 중계기 자신의 판정(no_progress_cycles, 정체 기준 2회),
# Context 는 CONTEXT_WARN. 근거 없는 숫자로 새 관문을 만들지 않는다.
DIAG_MAIL_WARN_SEC = 600
DIAG_MAIL_DEAD_SEC = 1200


def _age_sec(iso: str | None) -> float | None:
    if not iso:
        return None
    try:
        t = time.mktime(time.strptime(iso[:19].replace("T", " "), "%Y-%m-%d %H:%M:%S"))
    except ValueError:
        return None
    # 원장 시각은 UTC 다 — 로컬 시각과의 차로 나이를 구한다.
    return max(0.0, time.time() - (t - time.timezone))


def diagnose(out: dict) -> None:
    msgs = out.get("messages")
    for board in out["boards"]:
        diag: list[dict] = []
        run_id = board.get("run_id")

        if msgs is not None:
            untouched = [
                (m, _age_sec(m.get("created_at")))
                for m in msgs
                if m.get("run_id") == run_id and not m.get("read")
            ]
            stale = [(m, a) for m, a in untouched if a and a > DIAG_MAIL_WARN_SEC]
            # 받는이에 따라 뜻이 다르다: 감독 앞(run:)이 묵으면 배달 사슬(companion) 고장
            # 신호, 개별 명패 앞이 묵으면 그 수신자(중계기·작업자)의 소비 문제거나 은퇴 명패다.
            sup_stale = [(m, a) for m, a in stale if str(m.get("to_handle") or "").startswith("run:")]
            etc_stale = [(m, a) for m, a in stale if not str(m.get("to_handle") or "").startswith("run:")]
            if sup_stale:
                worst = max(a for _, a in sup_stale)
                diag.append({
                    "level": "bad" if worst > DIAG_MAIL_DEAD_SEC else "warn",
                    "text": f"감독 앞 편지 {len(sup_stale)}통을 아무도 안 집음 — 가장 오래 "
                            f"{int(worst // 60)}분. companion·감독 기상 사슬 점검",
                })
            if etc_stale:
                worst = max(a for _, a in etc_stale)
                diag.append({
                    "level": "warn",
                    "text": f"중계기·작업자 명패 앞 편지 {len(etc_stale)}통 미수령 — 가장 오래 "
                            f"{int(worst // 60)}분. 수신자 소비 루프 또는 은퇴 명패 확인",
                })

        gates = board.get("gates")
        if gates:
            pend = [g for g in gates if (g.get("status") or "pending") == "pending"]
            for g in pend:
                age = _age_sec(g.get("created_at"))
                mins = f" {int(age // 60)}분째" if age else ""
                has_letter = msgs is not None and any(
                    m.get("run_id") == run_id and m.get("type") == "decision_gate"
                    for m in msgs
                )
                txt = f"결정 관문 pending{mins}"
                if not has_letter:
                    txt += " — 동반 편지가 최근 우편함에 안 보임: 고아 관문 의심 (2026-08-05 실사고)"
                diag.append({"level": "bad", "text": txt})

        relay = board.get("relay")
        if relay and relay.get("age_sec") is not None:
            age = relay["age_sec"]
            if age > relay.get("dead_sec", bs.RELAY_DEAD_SEC):
                diag.append({"level": "bad",
                             "text": f"중계기 일기 {relay.get('age_text', '?')} 정지 — 재가동이 먼저"})
            elif age > relay.get("warn_sec", bs.RELAY_WARN_SEC):
                diag.append({"level": "warn",
                             "text": f"중계기 일기 {relay.get('age_text', '?')} 침묵 — 다음 주기 확인"})
            tail = relay.get("tail") or ""
            if isinstance(tail, list):
                tail = "\n".join(map(str, tail))
            m = re.search(r"no_progress_cycles=(\d+)", tail)
            if m and int(m.group(1)) >= 2:
                diag.append({"level": "warn",
                             "text": f"중계기 판정: 무진행 {m.group(1)}회 연속 (중계기 정체 기준 2회)"})

        # 슈퍼 판은 companion 대신 슈퍼감독 세션의 Monitor 가 깨운다 — 규칙 제외.
        if not board.get("companions") and "super" not in (board.get("name") or "").lower():
            diag.append({"level": "bad",
                         "text": "companion 0개 — 편지가 와도 감독이 안 깨어난다. 감독 pane 재기동 필요"})

        cards = board.get("cards")
        if cards is not None:
            if cards.get("failed"):
                diag.append({"level": "warn",
                             "text": f"실패 카드 {cards['failed']}장 — 분류·재발령 대기인지 확인"})
            if (cards.get("ready") or 0) > 0 and not cards.get("dispatched"):
                diag.append({"level": "warn",
                             "text": "대기 카드만 있고 도는 카드 0장 — 대기열 정체 의심 (대기열은 비우지 않는다)"})

        ctx = board.get("context_pct")
        if ctx is not None and ctx >= bs.CONTEXT_WARN:
            if board.get("autocompacts"):
                diag.append({"level": "info",
                             "text": f"감독 Context {ctx}% — gpt 계열, 자동 압축 대상. 추이만 2회 관측"})
            else:
                diag.append({"level": "warn",
                             "text": f"감독 Context {ctx}% — 교대 검토 (경계 {bs.CONTEXT_WARN}%)"})

        board["diag"] = diag


# Orca 오케스트레이션 원장 (SQLite). 읽기 전용(mode=ro)으로만 연다 — 쓰기 불가.
# 포크(Orca Kyle) DB 를 먼저 본다 — 2026-08-10 실사고: 구 orca DB 를 읽어서
# 지금 판이 아닌 옛 run 들의 원장을 현재 것처럼 보여줬다 (kyle 의 역할 표시
# 요청을 파다가 발견). 앱별로 데이터 폴더가 다르다.
LEDGER_CANDIDATES = [
    Path.home() / "Library/Application Support/Orca Kyle/orchestration.db",
    Path.home() / "Library/Application Support/orca/orchestration.db",
]
LEDGER_DB = next((p for p in LEDGER_CANDIDATES if p.exists()), LEDGER_CANDIDATES[0])
LEDGER_ROW_LIMIT = 200
LEDGER_CELL_MAX = 400

# 라우팅 보기 — 점수·가산점·쿼터를 눈으로 봐야 kyle 이 수정 판단을 할 수 있다 (2026-08-11).
# 읽기 전용이다: 정책 수정은 사람이 routing-providers.json 을 고치는 것이지 화면이 아니다.
ROUTING_FILE = Path.home() / "Dev/kyle-agent-skills/skills/orca-conductor/references/routing-providers.json"
QUOTA_FILE = Path.home() / ".cache/rottie/routing-usage.json"


def routing_view() -> dict:
    out: dict = {"file": str(ROUTING_FILE), "providers": None, "policies": [], "quota": None,
                 "quota_age_sec": None, "error": None}
    try:
        d = json.loads(ROUTING_FILE.read_text(encoding="utf-8"))
        out["providers"] = d.get("providers")
        out["policies"] = [
            {"key": k, **(v if isinstance(v, dict) else {"내용": str(v)})}
            for k, v in d.items() if k.startswith("_정책")
        ]
    except (OSError, ValueError) as e:
        out["error"] = f"라우팅 원본을 못 읽었다: {e}"
    try:
        q = json.loads(QUOTA_FILE.read_text(encoding="utf-8"))
        out["quota"] = q.get("reports")
        gen = q.get("generatedAt")
        if gen:
            out["quota_age_sec"] = max(0, time.time() - gen / 1000)
    except (OSError, ValueError):
        out["quota"] = None  # 없음이 아니라 못 읽음 — 화면에서 '모름'으로 표시
    return out


# 규칙 표면 — 사람(화면)과 에이전트(curl)가 같은 규칙 원본을 본다 (2026-08-11 kyle:
# "규칙들도 화면/curl/sh로 명확히 확인할 수 있게"). 복제하지 않는다 — 원본 파일을 렌더링만 한다.
RULE_SOURCES = [
    ("★ 공통 장비 표준 — 0절 삼표면 원칙 포함 (mechanics)",
     Path.home() / "Dev/kyle-agent-skills/skills/orca-conductor/references/mechanics.md"),
    ("임명장 필수 문구 (감독이 지키는 규칙)",
     Path.home() / "Dev/kyle-agent-skills/skills/orca-conductor/references/appointment-template.md"),
    ("라우팅 정책·상시 결정",
     Path.home() / "Dev/kyle-agent-skills/skills/orca-conductor/references/routing-providers.json"),
    ("실행기(runner)별 함정과 검증법",
     Path.home() / "Dev/kyle-agent-skills/skills/conductor/references/agent-runners.json"),
    ("orca 명령 안전 원장 — 위험 등급·검증된 시그니처 (command-safety)",
     Path.home() / "Dev/kyle-agent-skills/skills/orca-conductor/references/orca-command-safety.md"),
]


def rules_view() -> dict:
    docs = []
    for title, path in RULE_SOURCES:
        entry: dict = {"title": title, "path": str(path)}
        try:
            text = path.read_text(encoding="utf-8")
            entry["mtime"] = time.strftime("%Y-%m-%d %H:%M", time.localtime(path.stat().st_mtime))
            if path.suffix == ".json":
                d = json.loads(text)
                keep = {k: v for k, v in d.items() if k.startswith("_")}
                entry["text"] = json.dumps(keep, ensure_ascii=False, indent=1)
            else:
                entry["text"] = text
        except (OSError, ValueError) as e:
            entry["error"] = f"못 읽음: {e}"  # 없음이 아니라 모름
        docs.append(entry)
    return {"docs": docs}


def rules_txt(want: str | None = None) -> str:
    """기본은 목차만 — 필요한 문서만 ?doc=<이름 일부>로 받는다 (2026-08-11 kyle:
    "필요한 것만 받아야지" — 전문 일괄은 77KB라 에이전트 토큰 낭비)."""
    docs = rules_view()["docs"]
    if want:
        w = want.lower()
        hits = [d for d in docs if w in d["title"].lower() or w in d["path"].lower()]
        if not hits:
            names = " | ".join(d["path"].rsplit("/", 1)[-1] for d in docs)
            return f"doc='{want}' 일치 없음. 후보: {names}\n"
        out = []
        for doc in hits:
            out.append(f"## {doc['title']}")
            out.append(f"원본: {doc['path']} (수정 {doc.get('mtime', '모름')})")
            out.append("")
            out.append(doc.get("text") or doc.get("error", "모름"))
        return "\n".join(out)
    out = ["# 규칙 표면 — 목차 (전문은 /rules.txt?doc=<파일명 일부> 로 필요한 것만)", ""]
    for doc in docs:
        size = len(doc.get("text") or "")
        fname = doc["path"].rsplit("/", 1)[-1]
        out.append(f"- {doc['title']}")
        out.append(f"  doc={fname} · {size:,}자 · 수정 {doc.get('mtime', '모름')}")
    out.append("")
    out.append("예: curl -s 'http://127.0.0.1:8787/rules.txt?doc=mechanics'  (삼표면 원칙은 여기 0절)")
    return "\n".join(out)


# 스킬 원장 표면 — 원장(registry/skills-ledger.jsonl)에는 사람이 정한 사실(분류·메모)만 있고,
# 설명·링크·실물 상태는 여기서 SKILL.md 와 심볼릭 링크를 매번 실측한다 (2026-08-12 kyle:
# "나만의 스킬 리스트, 디자인부터"). 같은 뼈대의 두 번째 사례: 원장 + 화면 + curl 창구.
SKILLS_LEDGER = Path.home() / "Dev/kyle-agent-skills/registry/skills-ledger.jsonl"
SKILLS_ORIGIN = Path.home() / ".claude/skills"
SKILL_LINK_DIRS = [("codex", Path.home() / ".codex/skills"),
                   ("gjc", Path.home() / ".gjc/skills"),
                   ("kimi", Path.home() / ".agents/skills")]


def _skill_desc(skill_dir: Path) -> str:
    """SKILL.md frontmatter 의 description 을 실측으로 읽는다 (>-/> 접힘 문법 포함)."""
    md = skill_dir / "SKILL.md"
    try:
        lines = md.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return "모름 (SKILL.md 없음)"
    for i, line in enumerate(lines):
        if not line.startswith("description:"):
            continue
        val = line.split(":", 1)[1].strip()
        if val in (">", ">-", "|", "|-"):
            parts = []
            for nxt in lines[i + 1:]:
                if nxt.startswith((" ", "\t")) and nxt.strip():
                    parts.append(nxt.strip())
                elif nxt.strip():
                    break
                if len(" ".join(parts)) > 200:
                    break
            val = " ".join(parts)
        return val.strip("'\"")[:220] or "모름"
    return "모름 (description 없음)"


def skills_view() -> dict:
    ledger: dict[str, dict] = {}
    err = None
    try:
        for line in SKILLS_LEDGER.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line, strict=False)
            except ValueError:
                continue
            if "_schema" in d:
                continue
            ledger[d.get("name", "")] = d
    except OSError as e:
        err = f"원장을 못 읽었다: {e}"
    items = []
    installed = set()
    if SKILLS_ORIGIN.is_dir():
        for p in sorted(SKILLS_ORIGIN.iterdir()):
            if not p.is_dir() or p.name.startswith("."):
                continue
            installed.add(p.name)
            led = ledger.get(p.name) or {}
            links = {}
            for tool, d in SKILL_LINK_DIRS:
                lp = d / p.name
                links[tool] = ("link" if lp.is_symlink() and lp.exists()
                               else "copy" if lp.exists() else "none")
            items.append({"name": p.name, "cats": led.get("cats") or ["미분류"],
                          "note": led.get("note") or "", "curated": led.get("curated", False),
                          "desc": _skill_desc(p), "origin": str(p), "links": links,
                          "in_ledger": p.name in ledger})
    # 원장에는 있는데 실물이 사라진 스킬 — 실측 우선, 경고로 남긴다.
    ghosts = [name for name in ledger if name not in installed]
    cats: dict[str, int] = {}
    for it in items:
        for c in it["cats"]:
            cats[c] = cats.get(c, 0) + 1
    return {"ledger_file": str(SKILLS_LEDGER), "origin_dir": str(SKILLS_ORIGIN),
            "items": items, "ghosts": ghosts, "cats": cats, "error": err}


def skills_txt(cat: str | None = None) -> str:
    d = skills_view()
    items = d["items"]
    if cat:
        items = [i for i in items if any(cat.lower() in c.lower() for c in i["cats"])]
    lines = [f"스킬 원장 ({len(items)}개" + (f", 분류={cat}" if cat else "") + ")",
             f"원장: {d['ledger_file']} / 실물: {d['origin_dir']}",
             "분류별: " + " ".join(f"{k}={v}" for k, v in sorted(d["cats"].items(), key=lambda x: -x[1])),
             "필요한 분류만: curl '/skills.txt?cat=design'", ""]
    for it in items:
        link = " ".join(f"{t}:{s}" for t, s in it["links"].items())
        lines.append(f"- {it['name']} [{','.join(it['cats'])}] ({link})")
        lines.append(f"  {it['desc']}")
        if it["note"]:
            lines.append(f"  메모: {it['note']}")
    if d["ghosts"]:
        lines.append("")
        lines.append("⚠ 원장에는 있는데 실물 없음: " + ", ".join(d["ghosts"]))
    return "\n".join(lines) + "\n"


# 성적 표면 — card_outcome 원장(.orca/routing-events/*.jsonl)을 실행기×모델×노력으로
# 집계해 보여준다 (2026-08-12 kyle: "성적 탭"). 원본은 jsonl 원장, 여기는 렌더링만.
OUTCOME_GLOB = str(Path.home() / "Dev/*/.orca/routing-events/*.jsonl")


def outcomes_view() -> dict:
    import glob as _glob
    rows: list[dict] = []
    files = 0
    for path in _glob.glob(OUTCOME_GLOB):
        files += 1
        try:
            text = Path(path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in text.splitlines():
            line = line.strip()
            if not line or '"card_outcome"' not in line:
                continue
            try:
                d = json.loads(line, strict=False)
            except ValueError:
                continue
            if d.get("eventType") != "card_outcome":
                continue
            p = d.get("payload") or {}
            rows.append({
                "at": (d.get("occurredAt") or "")[:16].replace("T", " "),
                "board": d.get("board"), "task": d.get("taskId"),
                "role": p.get("role"), "runner": p.get("runner"),
                "provider": p.get("provider"), "model": p.get("model"),
                "effort": p.get("effort"),
                "verdict": p.get("verdict") or p.get("status"),
                "rounds": p.get("review_rounds"),
                "work_min": p.get("duration_work_min") or p.get("work_minutes"),
            })
    # 모델×역할×노력 집계 — 모름(null)은 "모름" 그룹으로 정직하게 남긴다.
    groups: dict = {}
    for r in rows:
        key = (str(r["model"] or "모름"), str(r["role"] or "모름"), str(r["effort"] or "모름"))
        g = groups.setdefault(key, {"n": 0, "pass": 0, "fail": 0, "verdict_unknown": 0,
                                    "rounds": [], "work": [], "last": ""})
        g["n"] += 1
        v = str(r["verdict"] or "")
        if "PASS" in v.upper():
            g["pass"] += 1
        elif "FAIL" in v.upper():
            g["fail"] += 1
        else:
            g["verdict_unknown"] += 1
        if isinstance(r["rounds"], (int, float)):
            g["rounds"].append(r["rounds"])
        if isinstance(r["work_min"], (int, float)):
            g["work"].append(r["work_min"])
        if r["at"] > g["last"]:
            g["last"] = r["at"]
    table = []
    for (model, role, effort), g in groups.items():
        judged = g["pass"] + g["fail"]
        table.append({
            "model": model, "role": role, "effort": effort, "n": g["n"],
            "pass": g["pass"], "fail": g["fail"], "verdict_unknown": g["verdict_unknown"],
            "pass_rate": round(g["pass"] / judged * 100) if judged else None,
            "avg_rounds": round(sum(g["rounds"]) / len(g["rounds"]), 1) if g["rounds"] else None,
            "avg_work_min": round(sum(g["work"]) / len(g["work"]), 1) if g["work"] else None,
            "last": g["last"],
        })
    table.sort(key=lambda t: -t["n"])
    recent = sorted(rows, key=lambda r: r["at"], reverse=True)[:40]
    return {"glob": OUTCOME_GLOB, "files": files, "total": len(rows),
            "table": table, "recent": recent}


# 쿼터 추이 표면 — 이력 원본은 quota-collection-1 판이 만드는 스냅샷 JSONL 이다.
# 카드(task_2189d6499cce)가 아직 진행 전이라, 후보 경로를 보고 없으면 현재값만 보여준다.
# 이력 파일이 생기면 아래 후보에 실경로를 등록한다 (추측 금지 — 없으면 없다고 말한다).
QUOTA_HISTORY_CANDIDATES = [
    Path.home() / ".cache/rottie/routing-usage-history.jsonl",
    Path.home() / "Dev/conductor-core/.orca/quota-history.jsonl",
]


def quota_history_view() -> dict:
    out: dict = {"history_file": None, "series": {}, "current": None, "note": None}
    try:
        q = json.loads(QUOTA_FILE.read_text(encoding="utf-8"))
        out["current"] = {"generatedAt": q.get("generatedAt"), "reports": q.get("reports")}
    except (OSError, ValueError):
        pass
    hist = next((p for p in QUOTA_HISTORY_CANDIDATES if p.exists()), None)
    if hist is None:
        out["note"] = ("이력 파일이 아직 없다 — quota-collection-1 판이 스냅샷 수집 카드"
                       "(task_2189d6499cce)를 진행 중이다. 파일이 생기면 여기 추이가 그려진다.")
        return out
    out["history_file"] = str(hist)
    series: dict = {}
    try:
        for line in hist.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line, strict=False)
            except ValueError:
                continue
            ts = d.get("collectedAt") or d.get("generatedAt") or d.get("ts")
            for rep in d.get("reports") or []:
                prov = rep.get("provider") or "모름"
                quota = rep.get("quota") or {}
                for key in ("weeklyPercent", "fiveHourPercent"):
                    if isinstance(quota.get(key), (int, float)):
                        series.setdefault(f"{prov}.{key}", []).append(
                            {"t": ts, "v": quota[key]})
    except OSError as e:
        out["note"] = f"이력 파일을 못 읽었다: {e}"
    out["series"] = series
    return out


def outcomes_txt() -> str:
    """에이전트 창구 — 집계 요약만 평문으로. 원본 원장은 .orca/routing-events/*.jsonl"""
    d = outcomes_view()
    lines = [f"성적 집계 (card_outcome {d['total']}건, 원본 {d['glob']})", "",
             "모델 | 역할 | 노력 | 카드수 | 통과 | 실패 | 판정모름 | 통과율% | 평균라운드 | 평균작업분"]
    for t in d["table"]:
        lines.append(" | ".join(str(t[k]) if t[k] is not None else "모름"
                                for k in ("model", "role", "effort", "n", "pass", "fail",
                                          "verdict_unknown", "pass_rate", "avg_rounds", "avg_work_min")))
    return "\n".join(lines) + "\n"


# kyle 메모함 — 대시보드의 유일한 쓰기 경로. 판 카드를 직접 만들지 않는 이유:
# 카드는 감독이 단일 작성자다. 여기 쌓인 메모는 슈퍼감독이 읽고 알맞은 저장소
# TODO 나 판 지시로 분배한다 (2026-08-11 kyle 요청).
MEMO_FILE = Path.home() / "Dev/kyle-agent-skills/docs/kyle-inbox.md"
MEMO_MAX_LEN = 2000
MEMO_HEADER = (
    "# kyle 메모함 (대시보드 수기)\n\n"
    "대시보드 메모함 탭에서 쌓인다. 슈퍼감독이 주기적으로 읽고 저장소 TODO/판 지시로 분배한다.\n"
    "분배가 끝난 줄은 지우지 말고 `- [분배됨 → 어디]` 를 뒤에 붙인다.\n\n"
)
_memo_lock = threading.Lock()


def memo_list() -> dict:
    if not MEMO_FILE.exists():
        return {"file": str(MEMO_FILE), "items": []}
    items = [
        line[2:]
        for line in MEMO_FILE.read_text(encoding="utf-8").splitlines()
        if line.startswith("- ")
    ]
    return {"file": str(MEMO_FILE), "items": items}


def memo_add(text: str) -> dict:
    text = " ".join(text.split())  # 한 메모 = 한 줄
    if not text:
        return {"error": "빈 메모"}
    if len(text) > MEMO_MAX_LEN:
        return {"error": f"메모가 너무 길다 ({len(text)}자 > {MEMO_MAX_LEN})"}
    stamp = time.strftime("%Y-%m-%d %H:%M")
    with _memo_lock:
        header = "" if MEMO_FILE.exists() else MEMO_HEADER
        with MEMO_FILE.open("a", encoding="utf-8") as f:
            f.write(f"{header}- {stamp} | {text}\n")
    return memo_list()


def ledger_conn() -> sqlite3.Connection:
    uri = f"file:{urllib.parse.quote(str(LEDGER_DB))}?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=2.0)
    conn.row_factory = sqlite3.Row
    return conn


def ledger_tables() -> dict:
    if not LEDGER_DB.exists():
        return {"error": f"원장 파일이 없다: {LEDGER_DB}"}
    try:
        with ledger_conn() as conn:
            names = [
                r["name"]
                for r in conn.execute(
                    "SELECT name FROM sqlite_master"
                    " WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
                )
            ]
            tables = []
            for name in names:
                try:
                    count = conn.execute(f'SELECT COUNT(*) AS c FROM "{name}"').fetchone()["c"]
                except sqlite3.Error:
                    count = None
                tables.append({"name": name, "rows": count})
            return {"db": str(LEDGER_DB), "tables": tables}
    except sqlite3.Error as exc:
        return {"error": f"원장을 못 읽었다: {exc}"}


def cell_text(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, bytes):
        return f"<{len(value)} bytes>"
    text = str(value)
    if len(text) > LEDGER_CELL_MAX:
        return text[:LEDGER_CELL_MAX] + f" …(총 {len(text)}자)"
    return text


def ledger_rows(name: str, limit: int, offset: int) -> dict:
    info = ledger_tables()
    if "error" in info:
        return info
    if name not in [t["name"] for t in info["tables"]]:
        return {"error": f"없는 테이블: {name}"}
    limit = max(1, min(limit, 500))
    try:
        with ledger_conn() as conn:
            try:
                cur = conn.execute(
                    f'SELECT * FROM "{name}" ORDER BY rowid DESC LIMIT ? OFFSET ?',
                    (limit, offset),
                )
            except sqlite3.OperationalError:
                # WITHOUT ROWID 테이블 대비 — 순서 없이라도 보여준다.
                cur = conn.execute(f'SELECT * FROM "{name}" LIMIT ? OFFSET ?', (limit, offset))
            columns = [c[0] for c in cur.description]
            rows = [[cell_text(v) for v in row] for row in cur.fetchall()]
            total = next(t["rows"] for t in info["tables"] if t["name"] == name)
            return {"table": name, "columns": columns, "rows": rows,
                    "offset": offset, "limit": limit, "total": total}
    except sqlite3.Error as exc:
        return {"error": f"원장을 못 읽었다: {exc}"}


def mail_history(limit: int) -> dict:
    """원장 DB에서 옛 편지까지 읽는다 — CLI inbox 는 최근 80통 상한이라 옛날 것을 못 본다.

    이름 풀이는 마지막 상태 수집(collect)이 만든 해석기를 재사용한다. 읽기 전용."""
    if not LEDGER_DB.exists():
        return {"error": f"원장 파일이 없다: {LEDGER_DB}"}
    resolve = LAST_MAPS.get("resolve")
    run_names = LAST_MAPS.get("runs") or {}
    limit = max(1, min(limit, 2000))
    try:
        with ledger_conn() as conn:
            rows = conn.execute(
                "SELECT id, run_id, from_handle, to_handle, subject, body, type,"
                " priority, read, created_at FROM messages ORDER BY rowid DESC LIMIT ?",
                (limit,),
            ).fetchall()
    except sqlite3.Error as exc:
        return {"error": f"원장을 못 읽었다: {exc}"}
    messages = []
    for row in rows:
        created = row["created_at"] or ""
        if created and "T" not in created:
            created = created.replace(" ", "T") + "Z"  # DB는 UTC를 공백 형식으로 저장한다
        messages.append(
            {
                "id": row["id"],
                "board": run_names.get(row["run_id"], row["run_id"] or "?"),
                "run_id": row["run_id"],
                "type": row["type"],
                "priority": row["priority"],
                "subject": row["subject"],
                "body": long_text(row["body"]),
                "read": bool(row["read"]),
                "created_at": created,
                "from_name": resolve(row["from_handle"]) if resolve else (row["from_handle"] or "?"),
                "to_name": resolve(row["to_handle"]) if resolve else (row["to_handle"] or "?"),
                "from_handle": row["from_handle"],
                "to_handle": row["to_handle"],
            }
        )
    return {"messages": messages, "limit": limit}


def status_text(data: dict) -> str:
    """웹과 같은 수집·판정 결과를 80칸 평문으로 보여준다."""
    lines = [
        f"판 현황 {data.get('collected_at', '모름')}",
        f"살아 있는 판 {len(data.get('boards') or [])}개",
        "",
    ]

    def add(label: str, value: str) -> None:
        lines.extend(
            textwrap.wrap(
                f"{label}: {value}",
                width=80,
                subsequent_indent="  ",
                break_long_words=True,
                break_on_hyphens=False,
            )
            or [f"{label}:"]
        )

    for board in data.get("boards") or []:
        add("판", str(board.get("name") or "(이름 없음)"))
        add("run", str(board.get("run_id") or "모름"))

        diag = board.get("diag") or []
        if diag:
            for item in diag:
                add(f"diag {item.get('level') or '?'}", str(item.get("text") or ""))
        else:
            add("diag", "없음")

        cards = board.get("cards")
        if cards is None:
            add("카드 개수", "모름")
        else:
            total = sum(value for value in cards.values() if isinstance(value, int))
            counts = " ".join(f"{key}={value}" for key, value in sorted(cards.items()))
            add("카드 개수", f"전체={total} {counts}".rstrip())

        relay = board.get("relay")
        if relay is None:
            relay_age = "없음"
        else:
            relay_age = str(relay.get("age_text") or "모름")
        add("중계기 나이", relay_age)
        add("companion 수", str(len(board.get("companions") or [])))

        gates = board.get("gates")
        if gates is None:
            pending = "모름"
        else:
            pending = str(
                sum(1 for gate in gates if (gate.get("status") or "pending") == "pending")
            )
        add("pending 관문", pending)
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def _fresh_text(entry: dict) -> str:
    if entry.get("note"):
        return str(entry["note"])
    age = entry.get("fresh_age_sec")
    if entry.get("fresh_label") is None:
        return ""
    if age is None:
        return f"{entry['fresh_label']} 모름"
    if age < 90:
        return f"{entry['fresh_label']} {int(age)}초 전"
    return f"{entry['fresh_label']} {int(age / 60)}분 전"


def watchers_txt(data: dict) -> str:
    """에이전트 창구 — 화면과 같은 수집 결과를 평문으로."""
    w = data.get("watchers") or {}
    live_boards = [b.get("name") for b in data.get("boards") or []]
    lines = [f"보조 감시 현황 {data.get('collected_at', '모름')}", ""]
    lines.append("슈퍼감독")
    for e in w.get("super") or []:
        pid = f"PID {e['pid']} 가동 {e['etime']}" if e.get("pid") else ""
        lines.append(f"- {e['label']}: {e['desc']}")
        detail = " · ".join(x for x in [e.get("engine") or "", pid, _fresh_text(e)] if x)
        if detail:
            lines.append(f"  {detail}")
    for board, entries in sorted((w.get("boards") or {}).items()):
        lines.append("")
        lines.append(f"판: {board}" + ("" if board in live_boards else " (감독 터미널 없음)"))
        seen = {e["kind"] for e in entries}
        for e in entries:
            detail = " · ".join(x for x in
                                [e.get("engine") or "", f"PID {e['pid']} 가동 {e['etime']}",
                                 _fresh_text(e)] if x)
            lines.append(f"- {e['label']}: {detail}")
        missing = [label for pat, label, _, sup in WATCHER_SPECS
                   if not sup and pat in WATCHER_EXPECTED and pat not in seen]
        if missing and board in live_boards:
            lines.append(f"- 빠짐 ⚠: {', '.join(missing)}")
    # 살아 있는 판인데 보조가 하나도 안 잡힌 경우 (슈퍼 판은 Monitor 가 지키므로 제외)
    for name in live_boards:
        if name and name not in (w.get("boards") or {}) and "super" not in name.lower():
            lines.append("")
            lines.append(f"판: {name}")
            lines.append("- 빠짐 ⚠: 보조 감시가 하나도 안 떠 있다")
    return "\n".join(lines).rstrip() + "\n"


class Cache:
    def __init__(self, orca: str):
        self.orca = orca
        self.lock = threading.Lock()
        self.data: dict | None = None
        self.at = 0.0

    def get(self) -> dict:
        with self.lock:
            if self.data is None or time.time() - self.at > COLLECT_MIN_INTERVAL:
                self.data = collect(self.orca)
                self.at = time.time()
            return self.data


PAGE = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>판 관제</title>
<style>
  :root {
    color-scheme: dark;
    --bg: #0d0e10; --side: #121316; --card: #17181c; --card2: #1d1e23;
    --line: #26272c; --text: #d9dce2; --dim: #82879199; --dim2: #828791;
    --ok: #58b768; --warn: #e0b13e; --bad: #e06c60; --accent: #6aabee;
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text);
         font: 14px/1.55 -apple-system, "Apple SD Gothic Neo", sans-serif; }
  a { color: inherit; text-decoration: none; }

  #layout { display: flex; min-height: 100vh; }
  #side { width: 218px; flex: none; background: var(--side); border-right: 1px solid var(--line);
          padding: 14px 10px; position: sticky; top: 0; height: 100vh; overflow-y: auto; }
  #side h1 { font-size: 16px; margin: 4px 8px 14px; }
  #side h1 small { color: var(--dim2); font-weight: 400; font-size: 11px; display: block; }
  .navsec { color: var(--dim2); font-size: 11px; margin: 14px 8px 4px; }
  .nav { display: block; padding: 7px 10px; border-radius: 8px; margin: 2px 0;
         color: var(--dim2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .nav:hover { background: var(--card); color: var(--text); }
  .nav.active { background: var(--card2); color: var(--text); }
  .badge { float: right; font-size: 11px; color: var(--dim2); background: var(--card2);
           border-radius: 8px; padding: 0 7px; margin-left: 6px; }
  .badge.hot { background: #4a2a27; color: #eda49c; }
  .badge.live { background: #23392a; color: #9ed3a6; }

  #main { flex: 1; min-width: 0; padding: 22px 26px; }
  #main h2 { font-size: 19px; margin: 0 0 2px; }
  .sub { color: var(--dim2); margin-bottom: 16px; font-size: 13px; }
  .mono { font: 12px/1.5 ui-monospace, Menlo, monospace; }

  .tiles { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 16px; }
  .tile { background: var(--card); border: 1px solid var(--line); border-radius: 12px;
          padding: 10px 16px; min-width: 118px; }
  .tile .k { color: var(--dim2); font-size: 12px; }
  .tile .v { font-size: 19px; font-weight: 600; margin-top: 2px; }
  .tile .v small { font-size: 12px; font-weight: 400; color: var(--dim2); }

  .card { background: var(--card); border: 1px solid var(--line); border-radius: 12px;
          padding: 14px 16px; margin-bottom: 12px; }
  .card h3 { font-size: 14px; margin: 0 0 10px; }
  .card h3 .mono { color: var(--dim2); font-weight: 400; }
  .grid2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(330px, 1fr)); gap: 12px; }

  .ok { color: var(--ok); } .warn { color: var(--warn); } .bad { color: var(--bad); }
  .dim { color: var(--dim2); } .accent { color: var(--accent); }
  .row { margin: 3px 0; }
  .label { display: inline-block; min-width: 52px; color: var(--dim2); }

  table { border-collapse: collapse; width: 100%; }
  th { text-align: left; color: var(--dim2); font-weight: 400; font-size: 12px;
       padding: 2px 10px 6px 0; border-bottom: 1px solid var(--line); }
  td { padding: 5px 10px 5px 0; border-bottom: 1px solid var(--line);
       vertical-align: top; white-space: nowrap; }
  tr:last-child td { border-bottom: none; }
  td.grow { white-space: normal; word-break: break-word; width: 100%; }
  .dot { display: inline-block; width: 8px; height: 8px; border-radius: 4px; margin-right: 7px; }

  pre { font: 12px/1.5 ui-monospace, Menlo, monospace; background: var(--bg);
        border: 1px solid var(--line); border-radius: 8px; padding: 10px;
        max-height: 320px; overflow: auto; white-space: pre-wrap; word-break: break-all; margin: 8px 0 0; }
  details > summary { cursor: pointer; color: var(--dim2); font-size: 13px; }
  .tag { display: inline-block; font-size: 11px; border: 1px solid var(--line); background: var(--card2);
         border-radius: 6px; padding: 0 6px; margin-right: 6px; color: var(--dim2); }
  .tag.who { color: var(--text); }
  .msg { border-top: 1px solid var(--line); padding: 9px 0; }
  .msg:first-child { border-top: none; }
  .msg-top { display: flex; gap: 8px; align-items: baseline; }
  .msg-top .subject { flex: 1; min-width: 0; color: var(--text); font-weight: 500;
                      overflow-wrap: break-word; }
  .msg-age { white-space: nowrap; font-size: 12px; }
  .msg-sub { font-size: 12px; color: var(--dim2); margin-top: 2px; }
  .msg-sub .to { color: var(--text); font-weight: 500; }
  .chip { display: inline-block; font-size: 11px; border: 1px solid var(--line); background: var(--card2);
          border-radius: 4px; padding: 0 6px; color: var(--dim2); white-space: nowrap; }
  .chip.t-done  { color: #8fca97; border-color: #2f4a35; }
  .chip.t-alert { color: #e8837a; border-color: #5a2f2b; }
  .chip.t-gate  { color: #e0b13e; border-color: #584a1e; }
  .chip.t-ask   { color: #6aabee; border-color: #2b4258; }
  input.search { background: var(--card); border: 1px solid var(--line); border-radius: 6px;
                 color: var(--text); padding: 2px 10px; font: inherit; font-size: 13px;
                 width: 240px; margin-left: 8px; }
  .scroll { max-height: 60vh; overflow: auto; }
  @media (max-width: 760px) {
    #layout { display: block; }
    #side { width: auto; height: auto; position: static; }
  }
</style>
</head>
<body>
<div id="layout">
  <nav id="side"></nav>
  <main id="main"></main>
</div>
<script>
let DATA = null;
let mailFilter = "all";       // 우편함 필터: all | untouched
let hideRelayMail = true;     // 중계기 일상 편지 숨김 (kyle: 평소엔 우편이 아니라 로그 확인용)
let mailLimit = 80;           // 80 = 실시간 수집분(CLI 상한). 그 이상은 원장 DB에서 읽는다.
let mailQuery = "";           // 우편함 검색어 (제목·보낸이·받는이·판·본문)
const openKeys = new Set();   // 새로고침해도 펼친 항목을 유지한다

const $ = (id) => document.getElementById(id);
function el(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined && text !== null) n.textContent = text;
  return n;
}
function ageOf(iso) {
  if (!iso) return "";
  let t = Date.parse(iso.includes("T") ? iso : iso.replace(" ", "T") + "Z");
  if (isNaN(t)) return iso;
  const sec = Math.max(0, (Date.now() - t) / 1000);
  if (sec < 60) return Math.floor(sec) + "초 전";
  if (sec < 3600) return Math.floor(sec / 60) + "분 전";
  if (sec < 86400) return Math.floor(sec / 3600) + "시간 " + Math.floor((sec % 3600) / 60) + "분 전";
  return Math.floor(sec / 86400) + "일 전";
}
function ageSecOf(iso) {
  if (!iso) return null;
  const t = Date.parse(iso.includes("T") ? iso : iso.replace(" ", "T") + "Z");
  return isNaN(t) ? null : Math.max(0, (Date.now() - t) / 1000);
}
// read=0 의 정직한 뜻은 "아무도(감독·중계기·companion·슈퍼) 안 읽음"이다. 소비자별 구분은
// 못 하지만(1d527a5), 오래 아무도 안 집은 편지는 배달 사슬 고장의 신호다 — NOT_READY 편지가
// 40분 방치된 실사고 (2026-08-10, kyle 결정으로 이 뜻으로 되살림). 문턱은 새 숫자를 만들지
// 않고 중계기 일기와 같은 600/1200초를 재사용한다.
const MAIL_WARN_SEC = 600, MAIL_DEAD_SEC = 1200;
function untouchedSec(m) { return m.read ? null : ageSecOf(m.created_at); }

// 중계기의 일상 통신(순찰 status·감시 갱신·relay_* 답장)은 로그 확인용이지 우편이 아니다.
// 단 escalation·decision_gate 는 중계기 발신이라도 경보라서 절대 숨기지 않는다.
function isRelayRoutine(m) {
  if (m.type === "escalation" || m.type === "decision_gate") return false;
  const names = (m.from_name || "") + " " + (m.to_name || "");
  return names.includes("중계기") || /^(re: ?)?relay_/i.test(m.subject || "");
}
// 로그 편지 = 중계기 일상 통신 + 생존신호(heartbeat). 발신자는 달라도(중계기 vs 작업자)
// "사람이 평소 읽을 우편이 아니라 기록"이라는 점이 같아 한 토글로 묶는다 (2026-08-10 kyle).
function isLogMail(m) {
  return m.type === "heartbeat" || isRelayRoutine(m);
}

function det(key, summaryText, contentNode) {
  const d = el("details");
  d.dataset.key = key;
  if (openKeys.has(key)) d.open = true;
  d.addEventListener("toggle", () => { d.open ? openKeys.add(key) : openKeys.delete(key); });
  d.appendChild(el("summary", null, summaryText));
  d.appendChild(contentNode);
  return d;
}

const STATUS = {
  dispatched: { ko: "도는 중", color: "var(--accent)", order: 0 },
  ready:      { ko: "대기",   color: "var(--warn)",   order: 1 },
  failed:     { ko: "실패",   color: "var(--bad)",    order: 2 },
  blocked:    { ko: "막힘",   color: "var(--bad)",    order: 3 },
  completed:  { ko: "완료",   color: "var(--ok)",     order: 9 },
  cancelled:  { ko: "취소",   color: "var(--dim2)",   order: 8 },
};
const stInfo = (s) => STATUS[s] || { ko: s, color: "var(--dim2)", order: 5 };

function route() {
  const h = location.hash.replace(/^#/, "");
  if (h.startsWith("board/")) return { page: "board", id: h.slice(6) };
  if (h.startsWith("ledger/")) return { page: "ledger", id: decodeURIComponent(h.slice(7)) };
  if (h.startsWith("skills/")) return { page: "skills", id: decodeURIComponent(h.slice(7)) };
  return { page: h || "overview" };
}

function boardWarns(b) {
  const w = [];
  if (DATA.messages !== null &&
      DATA.messages.some((m) => m.run_id === b.run_id && (untouchedSec(m) || 0) > MAIL_DEAD_SEC))
    w.push("묵은 편지");
  if (b.gates && b.gates.some((g) => (g.status || "pending") === "pending")) w.push("관문");
  if (b.relay && b.relay.age_sec !== undefined && b.relay.age_sec > b.relay.dead_sec) w.push("중계기");
  if (!b.companions.length) w.push("깨우미");
  if (b.cards && b.cards.failed) w.push("실패 " + b.cards.failed);
  return w;
}

function renderSide() {
  const side = $("side");
  side.replaceChildren();
  const h = el("h1", null, "판 관제");
  h.appendChild(el("small", null, DATA ? DATA.collected_at + " 수집" : "…"));
  side.appendChild(h);
  const r = route();
  const item = (hash, label, badge, badgeCls) => {
    const a = el("a", "nav", label);
    a.href = "#" + hash;
    const current = r.page === "board" ? "board/" + r.id : r.page;  // 원장 표 화면도 "원장" 메뉴를 켠다
    if (current === hash) a.classList.add("active");
    if (badge !== undefined && badge !== null) {
      const b = el("span", "badge" + (badgeCls ? " " + badgeCls : ""), String(badge));
      a.prepend(b);
    }
    side.appendChild(a);
  };
  if (!DATA) { item("overview", "개요"); return; }
  item("overview", "개요");
  item("mail", "우편함", DATA.messages === null ? "?" : DATA.messages.length);
  item("terms", "터미널", DATA.terminals.length);
  item("ledger", "원장 (DB)");
  item("routing", "라우팅");
  item("scores", "성적");
  item("skills", "스킬");
  item("watchers", "보조 감시", watcherCount());
  item("rules", "규칙");
  item("memo", "메모함", MEMOS ? MEMOS.items.length : undefined);
  side.appendChild(el("div", "navsec", "살아있는 판"));
  for (const b of DATA.boards) {
    const warns = boardWarns(b);
    item("board/" + b.run_id, b.name, warns.length ? "⚠" : (b.cards ? (b.cards.dispatched || 0) + "▸" : "?"),
         warns.length ? "hot" : "live");
  }
  side.appendChild(el("div", "navsec", ""));
  item("dormant", "지난 기록", DATA.dormant.length);
}

function tile(k, v, small) {
  const t = el("div", "tile");
  t.appendChild(el("div", "k", k));
  const val = el("div", "v", v === null || v === undefined ? "모름" : String(v));
  if (small) val.appendChild(el("small", null, " " + small));
  t.appendChild(val);
  return t;
}

function pageOverview(main) {
  main.appendChild(el("h2", null, "개요"));
  main.appendChild(el("div", "sub", "판·카드·편지·관문·기계 상태를 감독을 깨우지 않고 읽는다. 15초마다 갱신."));
  const s = DATA.system;
  const tiles = el("div", "tiles");
  const running = DATA.boards.reduce((n, b) => n + ((b.cards && b.cards.dispatched) || 0), 0);
  const failed = DATA.boards.reduce((n, b) => n + ((b.cards && b.cards.failed) || 0), 0);
  const gates = DATA.boards.reduce((n, b) => n + ((b.gates || []).filter((g) => (g.status || "pending") === "pending").length), 0);
  const lastMail = DATA.messages === null ? null
    : (DATA.messages.length ? ageOf(DATA.messages[0].created_at) : "없음");
  tiles.appendChild(tile("살아있는 판", DATA.boards.length, "/ 지난 기록 " + DATA.dormant.length));
  tiles.appendChild(tile("도는 카드", running, failed ? "실패 " + failed : ""));
  tiles.appendChild(tile("대기 관문", gates));
  tiles.appendChild(tile("마지막 편지", lastMail));
  const stale = DATA.messages === null ? null
    : DATA.messages.filter((m) => (untouchedSec(m) || 0) > MAIL_WARN_SEC).length;
  tiles.appendChild(tile("묵은 편지", stale, "10분+ 아무도 안 읽음"));
  tiles.appendChild(tile("부하", s.load, "CPU " + s.cpus));
  tiles.appendChild(tile("메모리 여유", s.mem_free));
  tiles.appendChild(tile("디스크 여유", s.disk_avail, s.disk_used_pct ? "사용 " + s.disk_used_pct : ""));
  main.appendChild(tiles);

  const grid = el("div", "grid2");
  for (const b of DATA.boards) grid.appendChild(boardSummaryCard(b));
  if (!DATA.boards.length) grid.appendChild(el("div", "warn", "감독 터미널이 살아 있는 판이 없다."));
  main.appendChild(grid);
}

function ctxNode(b) {
  if (b.context_pct === null) return el("span", "dim", "Context 모름");
  if (b.context_pct >= b.context_warn) {
    // 교대 기준은 모델 계열마다 다르다 (2026-08-10 kyle 결정, mechanics.md / board-status.py 와 동일 기준).
    if (b.autocompacts === true)
      return el("span", "warn", "Context " + b.context_pct + "% (압축에 맡김 · 계속 오르면 교대)");
    if (b.autocompacts === false)
      return el("span", "bad", "Context " + b.context_pct + "% ⚠ 교대 필요 — " + b.model + " 은 자동 압축을 기대할 수 없다");
    return el("span", "warn", "Context " + b.context_pct + "% (모델을 못 읽어 교대 여부 판단 불가)");
  }
  return el("span", null, "Context " + b.context_pct + "%");
}

function boardSummaryCard(b) {
  const card = el("div", "card");
  const h = el("h3");
  const link = el("a", "accent", b.name);
  link.href = "#board/" + b.run_id;
  h.appendChild(link);
  h.appendChild(el("span", "mono", "  " + b.run_id));
  card.appendChild(h);

  const sup = el("div", "row"); sup.appendChild(el("span", "label", "감독"));
  sup.appendChild(ctxNode(b));
  if (b.weekly_left) sup.appendChild(el("span", "dim", "  주간 잔여 " + b.weekly_left));
  card.appendChild(sup);

  const cards = el("div", "row"); cards.appendChild(el("span", "label", "카드"));
  if (b.cards === null) cards.appendChild(el("span", "bad", "못 읽음 (0개가 아니라 모름)"));
  else {
    cards.appendChild(el("span", null, "도는 중 " + (b.cards.dispatched || 0) + "   대기 " + (b.cards.ready || 0)));
    if (b.cards.failed) cards.appendChild(el("span", "warn", "   실패 " + b.cards.failed));
    cards.appendChild(el("span", "dim", "   완료 " + (b.cards.completed || 0)));
  }
  card.appendChild(cards);
  for (const t of (b.tasks || []).filter((t) => t.status === "dispatched"))
    card.appendChild(el("div", "row accent", "   ▸ " + t.title));

  const mail = el("div", "row");
  mail.appendChild(el("span", "label", "편지"));
  let mine = [];
  if (DATA.messages === null) mail.appendChild(el("span", "bad", "모름 — 우편함을 못 읽었다"));
  else {
    // 로그 편지(중계기 통신·생존신호)는 판 요약에서도 제외 — 경보·관문은 isLogMail 이 남긴다.
    mine = DATA.messages.filter((m) => m.run_id === b.run_id && !isLogMail(m));
    mail.appendChild(el("span", "dim", mine.length ? "최근 3통" : "없음"));
  }
  card.appendChild(mail);
  for (const m of mine.slice(0, 3)) {
    const urgent = m.type === "escalation" || m.type === "decision_gate";
    const stale = (untouchedSec(m) || 0) > MAIL_WARN_SEC;
    card.appendChild(el("div", "row " + (stale || urgent ? "warn" : "dim"),
      "   ▸ " + ageOf(m.created_at) + " · " + msgType(m.type).ko + " · " + (m.subject || "(제목 없음)")
      + (stale ? " · 아무도 안 읽음 ⚠" : "")));
  }

  const gates = (b.gates || []).filter((g) => (g.status || "pending") === "pending");
  if (gates.length) {
    const g = el("div", "row"); g.appendChild(el("span", "label", "관문"));
    g.appendChild(el("span", "bad", "대기 중 " + gates.length + "개 — 아무도 안 보면 판이 조용히 멈춘다"));
    card.appendChild(g);
  }

  const relay = el("div", "row"); relay.appendChild(el("span", "label", "중계기"));
  relay.appendChild(relayStateNode(b.relay));
  card.appendChild(relay);

  const comp = el("div", "row"); comp.appendChild(el("span", "label", "깨우미"));
  comp.appendChild(companionsNode(b.companions, false));
  card.appendChild(comp);
  return card;
}

function relayStateNode(r) {
  if (!r || r.age_sec === undefined)
    return el("span", "warn", "일기 없음 — 중계기를 안 세웠거나 판 이름이 다르다");
  const cls = r.age_sec > r.dead_sec ? "bad" : r.age_sec > r.warn_sec ? "warn" : "ok";
  const suffix = r.age_sec > r.dead_sec ? "  ⚠ 감시 멈춤" : r.age_sec > r.warn_sec ? "  (느림)" : "";
  return el("span", cls, "일기 " + r.age_text + suffix);
}

function companionsNode(comps, withCmd) {
  if (!comps.length) return el("span", "bad", "없음 — 완료 편지가 와도 감독이 안 깨어난다");
  const span = el("span", "ok", "살아있음  " + comps.map((c) => "PID " + c.pid).join(", "));
  return span;
}

function pageBoard(main, runId) {
  const b = DATA.boards.find((x) => x.run_id === runId);
  if (!b) {
    const d = DATA.dormant.find((x) => x.run_id === runId);
    main.appendChild(el("h2", null, d ? d.name : "판 없음"));
    main.appendChild(el("div", "sub", d ? "감독 터미널이 사라진 지난 기록이다." : runId));
    return;
  }
  main.appendChild(el("h2", null, b.name));
  main.appendChild(el("div", "sub mono", b.run_id));

  const tiles = el("div", "tiles");
  const ctxNote = b.context_pct === null || b.context_pct < b.context_warn ? ""
    : b.autocompacts === true ? "압축에 맡김 · 계속 오르면 교대"
    : b.autocompacts === false ? "⚠ 교대 필요 (" + b.model + ")"
    : "모델을 못 읽어 판단 불가";
  tiles.appendChild(tile("Context", b.context_pct === null ? null : b.context_pct + "%", ctxNote));
  tiles.appendChild(tile("주간 잔여", b.weekly_left));
  const myMail = DATA.messages === null ? null : DATA.messages.filter((m) => m.run_id === b.run_id);
  tiles.appendChild(tile("마지막 편지", myMail === null ? null : (myMail.length ? ageOf(myMail[0].created_at) : "없음")));
  if (b.cards) {
    tiles.appendChild(tile("도는 중", b.cards.dispatched || 0));
    tiles.appendChild(tile("대기", b.cards.ready || 0));
    tiles.appendChild(tile("실패", b.cards.failed || 0));
    tiles.appendChild(tile("완료", b.cards.completed || 0));
  }
  main.appendChild(tiles);

  // 자동 판정 — 서버가 낸 판정을 그대로 보여준다 (규칙 원본은 서버 diagnose()).
  if (b.diag && b.diag.length) {
    const dcard = el("div", "card");
    dcard.appendChild(el("h3", null, "자동 판정"));
    for (const d of b.diag) {
      const cls = d.level === "bad" ? "bad" : d.level === "warn" ? "warn" : "dim";
      dcard.appendChild(el("div", "row " + cls,
        (d.level === "bad" ? "● " : d.level === "warn" ? "▲ " : "· ") + d.text));
    }
    main.appendChild(dcard);
  } else if (b.diag) {
    const ok = el("div", "card");
    ok.appendChild(el("div", "dim", "자동 판정: 걸리는 항목 없음"));
    main.appendChild(ok);
  }

  const gates = b.gates || [];
  const pending = gates.filter((g) => (g.status || "pending") === "pending");
  if (b.gates === null || gates.length) {
    const card = el("div", "card");
    card.appendChild(el("h3", null, "결정 관문"));
    if (b.gates === null) card.appendChild(el("div", "bad", "못 읽음 — 0개가 아니라 모름"));
    for (const g of gates) {
      const row = el("div", "row" + ((g.status || "pending") === "pending" ? " bad" : " dim"));
      row.textContent = (g.status || "pending") + " · " + (g.title || g.question || g.reason || g.id || "");
      card.appendChild(row);
    }
    if (pending.length)
      card.appendChild(el("div", "dim", "대기 관문은 편지가 함께 안 가면 아무도 모른다 (2026-08-05 고아 관문 실사고)."));
    main.appendChild(card);
  }

  // 카드 목록
  const cardsCard = el("div", "card");
  cardsCard.appendChild(el("h3", null, "카드 목록"));
  if (b.tasks === null) cardsCard.appendChild(el("div", "bad", "못 읽음 — 0개가 아니라 모름"));
  else {
    const active = b.tasks.filter((t) => stInfo(t.status).order < 8)
                          .sort((x, y) => stInfo(x.status).order - stInfo(y.status).order);
    const doneList = b.tasks.filter((t) => stInfo(t.status).order >= 8);
    cardsCard.appendChild(taskTable(active));
    if (doneList.length) {
      const wrap = el("div", "scroll");
      wrap.appendChild(taskTable(doneList.slice().reverse()));
      cardsCard.appendChild(det("done-" + b.run_id, "끝난 카드 " + doneList.length + "개", wrap));
    }
  }
  main.appendChild(cardsCard);

  // 중계기
  const relayCard = el("div", "card");
  relayCard.appendChild(el("h3", null, "중계기"));
  const st = el("div", "row"); st.appendChild(el("span", "label", "상태"));
  st.appendChild(relayStateNode(b.relay)); relayCard.appendChild(st);
  if (b.relay) {
    if (b.relay.workdir) {
      const w = el("div", "row"); w.appendChild(el("span", "label", "위치"));
      w.appendChild(el("span", "mono", b.relay.workdir
        + (b.relay.terminal_title ? "  (터미널 " + b.relay.terminal_title + ")" : "")));
      relayCard.appendChild(w);
    }
    if (b.relay.path) {
      const p = el("div", "row"); p.appendChild(el("span", "label", "일기"));
      p.appendChild(el("span", "mono dim", b.relay.path));
      relayCard.appendChild(p);
      relayCard.appendChild(det("tail-" + b.run_id, "일기 꼬리 " + b.relay.tail.length + "줄",
                                el("pre", null, b.relay.tail.join("\\n"))));
    }
  }
  main.appendChild(relayCard);

  // 깨우미
  const compCard = el("div", "card");
  compCard.appendChild(el("h3", null, "깨우미 (companion)"));
  const cst = el("div", "row"); cst.appendChild(el("span", "label", "상태"));
  cst.appendChild(companionsNode(b.companions, true)); compCard.appendChild(cst);
  for (const c of b.companions) {
    const r = el("div", "row"); r.appendChild(el("span", "label", "명령"));
    r.appendChild(el("span", "mono dim", "PID " + c.pid + " · " + c.cmd));
    compCard.appendChild(r);
  }
  main.appendChild(compCard);

  // 이 판의 편지
  const mailCard = el("div", "card");
  const allMine = DATA.messages === null ? null : DATA.messages.filter((m) => m.run_id === b.run_id);
  const mine = allMine === null ? null
    : (hideRelayMail ? allMine.filter((m) => !isLogMail(m)) : allMine);
  const hiddenCnt = allMine === null ? 0 : allMine.length - mine.length;
  const h3 = el("h3", null, "이 판의 편지 ");
  if (hiddenCnt) h3.appendChild(el("span", "dim", "(로그 편지 " + hiddenCnt + "통 숨김 — 우편함에서 전환)"));
  mailCard.appendChild(h3);
  mailCard.appendChild(mailList(mine, "board-" + b.run_id, false));
  main.appendChild(mailCard);
}

function taskTable(tasks) {
  const table = el("table");
  const head = el("tr");
  for (const t of ["상태", "카드", "담당", "시각"]) head.appendChild(el("th", null, t));
  table.appendChild(head);
  for (const t of tasks) {
    const info = stInfo(t.status);
    const tr = el("tr");
    const td1 = el("td");
    const dot = el("span", "dot"); dot.style.background = info.color;
    td1.appendChild(dot); td1.appendChild(document.createTextNode(info.ko));
    tr.appendChild(td1);
    const tdTitle = el("td", "grow", t.title);
    if (t.spec || t.result) {
      let text = t.spec || "";
      if (t.result) text += (text ? "\\n\\n── 결과 ──\\n" : "") + t.result;
      tdTitle.appendChild(det("spec-" + t.id, "내용", el("pre", null, text)));
    }
    tr.appendChild(tdTitle);
    const who = el("td", "dim", t.status === "completed" ? "" : t.assignee || "");
    tr.appendChild(who);
    tr.appendChild(el("td", "dim", ageOf(t.completed_at || t.created_at)));
    table.appendChild(tr);
  }
  return table;
}

const MSG_TYPES = {
  worker_done:   { ko: "완료", cls: "t-done" },
  escalation:    { ko: "경보", cls: "t-alert" },
  decision_gate: { ko: "관문", cls: "t-gate" },
  ask:           { ko: "질문", cls: "t-ask" },
  reply:         { ko: "답장", cls: "t-ask" },
  status:        { ko: "상태", cls: "" },
  heartbeat:     { ko: "생존", cls: "" },
};
const msgType = (t) => MSG_TYPES[t] || { ko: t, cls: "" };
// 역할 이름 끝의 " · 판이름"은 판 칩과 중복이라 떼고 보여준다.
function roleShort(name, board) {
  const suffix = " · " + board;
  return name && name.endsWith(suffix) ? name.slice(0, name.length - suffix.length) : name;
}

function mailList(msgs, keyPrefix, showBoard) {
  const box = el("div");
  if (msgs === null) { box.appendChild(el("div", "bad", "우편함을 못 읽었다 — 비어 있는 게 아니라 모름")); return box; }
  if (!msgs.length) { box.appendChild(el("div", "dim", "편지 없음")); return box; }
  for (const m of msgs) {
    const row = el("div", "msg");
    const info = msgType(m.type);
    const top = el("div", "msg-top");
    top.appendChild(el("span", "chip " + info.cls,
      info.ko + (m.priority === "high" && m.type !== "escalation" ? "·급함" : "")));
    if (showBoard) top.appendChild(el("span", "chip", "판 · " + m.board));
    top.appendChild(el("span", "subject" + (m.type === "escalation" ? " warn" : ""), m.subject || "(제목 없음)"));
    top.appendChild(el("span", "msg-age dim", ageOf(m.created_at)));
    row.appendChild(top);
    // 보낸사람 → 받는사람 순서로 통일 (kyle) — 강조는 여전히 받는사람에게.
    const sub = el("div", "msg-sub");
    const from = el("span", null, roleShort(m.from_name, m.board)); from.title = m.from_handle || "";
    const to = el("span", "to", roleShort(m.to_name, m.board)); to.title = m.to_handle || "";
    sub.appendChild(from); sub.appendChild(document.createTextNode(" → ")); sub.appendChild(to);
    const u = untouchedSec(m);
    if (u !== null)
      sub.appendChild(el("span", u > MAIL_DEAD_SEC ? "bad" : u > MAIL_WARN_SEC ? "warn" : "dim",
        "  · 아무도 안 읽음" + (u > MAIL_WARN_SEC ? " " + Math.floor(u / 60) + "분째 ⚠" : "")));
    row.appendChild(sub);
    if (m.body) row.appendChild(det(keyPrefix + "-" + m.id, "내용", el("pre", null, m.body)));
    box.appendChild(row);
  }
  return box;
}

async function pageMail(main) {
  main.appendChild(el("h2", null, "우편함"));
  main.appendChild(el("div", "sub",
    "줄마다: [편지 종류 칩] [판 · 어느 판 칩] 제목 … 시각 / 보낸사람 → 받는사람(밝은 글씨)."
    + " '아무도 안 읽음' = 감독·중계기·companion·슈퍼 넷 중 누구도 아직 안 집은 편지."
    + " 읽음 처리 없이 보기만 한다 (감독 편지를 안 가로챔)."));
  let source = DATA.messages;
  if (mailLimit > 80) {
    // 실시간 수집분(80통) 너머는 원장 DB에서 읽는다 — 3,700통 전체까지 거슬러 갈 수 있다.
    try {
      const d = await (await fetch("/api/mail?limit=" + mailLimit)).json();
      source = d.error ? null : (d.messages || null);
    } catch (e) { source = null; }
  }
  const q = mailQuery.trim();
  const searched = source === null ? null : (q ? source.filter((m) =>
    [m.subject, m.from_name, m.to_name, m.board, m.body].some((v) => (v || "").includes(q))) : source);
  const bar = el("div", "row");
  const logCnt = searched === null ? 0 : searched.filter(isLogMail).length;
  const base = searched === null ? null
    : (hideRelayMail ? searched.filter((m) => !isLogMail(m)) : searched);
  const total = base === null ? "?" : base.length;
  const untouchedCnt = base === null ? "?" : base.filter((m) => !m.read).length;
  const mkBtn = (active, label, onclick) => {
    const a = el("a", "tag" + (active ? " who" : ""), label);
    a.href = "javascript:void(0)";
    a.onclick = onclick;
    return a;
  };
  bar.appendChild(mkBtn(mailFilter === "all", "전체 " + total, () => { mailFilter = "all"; render(); }));
  bar.appendChild(mkBtn(mailFilter === "untouched", "아무도 안 읽음 " + untouchedCnt,
    () => { mailFilter = "untouched"; render(); }));
  const logBtn = mkBtn(!hideRelayMail, (hideRelayMail ? "로그 편지 숨김 " : "로그 편지 표시 ") + logCnt,
    () => { hideRelayMail = !hideRelayMail; render(); });
  logBtn.title = "로그 편지 = 중계기 일상 통신(순찰·감시 갱신) + 작업자 생존신호(heartbeat). 경보·관문은 절대 안 숨김.";
  bar.appendChild(logBtn);
  bar.appendChild(mkBtn(mailLimit > 80,
    mailLimit > 80 ? "원장에서 " + mailLimit + "통 · 더 옛날까지" : "옛날 편지 더 보기",
    () => { mailLimit = Math.min(mailLimit === 80 ? 400 : mailLimit * 2, 2000); render(); }));
  if (mailLimit > 80)
    bar.appendChild(mkBtn(false, "최근 80통으로", () => { mailLimit = 80; render(); }));
  const search = el("input", "search");
  search.type = "search";
  search.placeholder = "검색 후 Enter (예: 슈퍼감독)";
  search.value = mailQuery;
  search.onchange = () => { mailQuery = search.value; render(); };
  bar.appendChild(search);
  main.appendChild(bar);
  if (q && base !== null)
    main.appendChild(el("div", "row dim", "검색 '" + q + "' — " + base.length + "통"));
  const shown = base === null ? null
    : (mailFilter === "untouched" ? base.filter((m) => !m.read) : base);
  const card = el("div", "card");
  card.appendChild(mailList(shown, "all", true));
  main.appendChild(card);
}

function pageTerms(main) {
  main.appendChild(el("h2", null, "터미널"));
  main.appendChild(el("div", "sub", DATA.terminals.length + "개 · 역할은 카드 담당 기준으로 푼 이름이다."));
  const card = el("div", "card");
  const table = el("table");
  const head = el("tr");
  for (const t of ["터미널", "역할", "마지막 출력", "미리보기"]) head.appendChild(el("th", null, t));
  table.appendChild(head);
  for (const t of DATA.terminals) {
    const tr = el("tr");
    const td = el("td", t.connected ? null : "dim", t.title); td.title = t.worktree;
    tr.appendChild(td);
    tr.appendChild(el("td", "dim", t.role));
    tr.appendChild(el("td", "dim", t.age_text));
    tr.appendChild(el("td", "grow dim mono", t.preview));
    table.appendChild(tr);
  }
  card.appendChild(table);
  main.appendChild(card);
}

async function pageLedger(main, tableName) {
  main.appendChild(el("h2", null, "원장 (DB)"));
  const sub = el("div", "sub", "Orca 오케스트레이션 SQLite 원본을 읽기 전용으로 본다. 쓰기 없음.");
  main.appendChild(sub);
  const holder = el("div");
  main.appendChild(holder);
  if (!tableName) {
    const d = await (await fetch("/api/ledger/tables")).json();
    if (d.error) { holder.appendChild(el("div", "bad", d.error)); return; }
    sub.textContent = d.db + " · 읽기 전용";
    const card = el("div", "card");
    const table = el("table");
    const head = el("tr");
    for (const t of ["테이블", "행 수"]) head.appendChild(el("th", null, t));
    table.appendChild(head);
    for (const t of d.tables) {
      const tr = el("tr");
      const td = el("td", "grow");
      const a = el("a", "accent", t.name);
      a.href = "#ledger/" + encodeURIComponent(t.name);
      td.appendChild(a); tr.appendChild(td);
      tr.appendChild(el("td", "dim", t.rows === null ? "모름" : String(t.rows)));
      table.appendChild(tr);
    }
    card.appendChild(table);
    holder.appendChild(card);
    return;
  }
  const d = await (await fetch("/api/ledger/table?name=" + encodeURIComponent(tableName))).json();
  if (d.error) { holder.appendChild(el("div", "bad", d.error)); return; }
  sub.textContent = tableName + " · 전체 " + d.total + "행 중 최신 " + d.rows.length + "행 · 읽기 전용";
  const back = el("a", "accent", "← 테이블 목록");
  back.href = "#ledger";
  holder.appendChild(back);
  const card = el("div", "card");
  const wrap = el("div");
  wrap.style.overflowX = "auto";
  const table = el("table", "mono");
  const head = el("tr");
  for (const c of d.columns) head.appendChild(el("th", null, c));
  table.appendChild(head);
  for (const row of d.rows) {
    const tr = el("tr");
    for (const v of row) {
      const td = el("td", v === null ? "dim" : null, v === null ? "NULL" : v);
      td.style.maxWidth = "420px"; td.style.overflow = "hidden"; td.style.textOverflow = "ellipsis";
      td.title = v === null ? "" : v;
      tr.appendChild(td);
    }
    table.appendChild(tr);
  }
  wrap.appendChild(table);
  card.appendChild(wrap);
  holder.appendChild(card);
}

// 보조 감시 — 슈퍼감독/판 감독을 누가 지키고 있는지 ps 실측 그대로 (2026-08-12 kyle 요청).
function watcherCount() {
  const w = DATA && DATA.watchers;
  if (!w) return undefined;
  let n = (w.super || []).filter((e) => e.pid).length;
  for (const es of Object.values(w.boards || {})) n += es.length;
  return n;
}

function freshText(e) {
  if (e.note) return e.note;
  if (!e.fresh_label) return "";
  if (e.fresh_age_sec === null || e.fresh_age_sec === undefined) return e.fresh_label + " 모름";
  const s = Math.round(e.fresh_age_sec);
  return e.fresh_label + " " + (s < 90 ? s + "초 전" : Math.round(s / 60) + "분 전");
}

function watcherRow(e) {
  const tr = el("tr");
  const name = el("td", null, e.label);
  name.style.whiteSpace = "nowrap";   // 이름이 긴 설명에 밀려 한 글자씩 세로로 쪼개지는 것 방지
  tr.appendChild(name);
  const descTd = el("td", "dim", e.desc);
  if (e.engine) {
    const eng = el("div", null, e.engine);
    eng.style.fontSize = "11px";
    eng.style.marginTop = "3px";
    // AI 를 부르는 보조만 눈에 띄게 — 나머지는 토큰 소비 0 인 스크립트다.
    eng.style.color = e.engine.includes("AI 판정") ? "#c9a86a" : "var(--dim2)";
    descTd.appendChild(eng);
  }
  tr.appendChild(descTd);
  const pid = el("td", e.pid ? "mono" : "dim", e.pid ? String(e.pid) : "—");
  pid.style.whiteSpace = "nowrap";
  tr.appendChild(pid);
  const up = el("td", "dim mono", e.etime || "—");
  up.style.whiteSpace = "nowrap";
  tr.appendChild(up);
  const fresh = freshText(e);
  const stale = e.fresh_age_sec !== null && e.fresh_age_sec !== undefined && e.fresh_age_sec > 2700;
  const freshTd = el("td", stale ? "warn" : "dim", fresh);
  // 표 자동 배치는 max-width 를 무시한다 — width 힌트를 줘야 긴 안내문이 칸 안에서 접힌다.
  freshTd.style.width = fresh.length > 40 ? "320px" : "130px";
  tr.appendChild(freshTd);
  return tr;
}

function watcherTable(entries) {
  const table = el("table");
  const head = el("tr");
  for (const t of ["이름", "하는 일", "PID", "가동", "최근 활동"]) {
    const th = el("th", null, t);
    th.style.whiteSpace = "nowrap";
    head.appendChild(th);
  }
  table.appendChild(head);
  for (const e of entries) table.appendChild(watcherRow(e));
  return table;
}

// 성적 탭 — card_outcome 원장 집계 + 쿼터 추이 (2026-08-12 kyle 요청). 원본은
// .orca/routing-events/*.jsonl 원장과 쿼터 이력 파일이고, 여기는 렌더링만 한다.
let SCORES = null, QHIST = null;

function barCell(pct, color) {
  // 순수 CSS 가로 막대 — 표 안에서 비율을 눈으로 비교한다.
  const wrap = el("div");
  wrap.style.display = "flex"; wrap.style.alignItems = "center"; wrap.style.gap = "6px";
  const bar = el("div");
  bar.style.height = "8px"; bar.style.borderRadius = "4px";
  bar.style.width = Math.max(2, Math.round(pct)) + "px"; // 1% = 1px, 최대 100px
  bar.style.background = color;
  wrap.appendChild(bar);
  wrap.appendChild(el("span", "dim", pct + "%"));
  return wrap;
}

function quotaChart(series) {
  // 순수 SVG 꺾은선 — provider 별 주간 사용률 추이.
  const keys = Object.keys(series).filter((k) => series[k].length > 1);
  const W = 640, H = 220, PAD = 34;
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 " + W + " " + H);
  svg.style.width = "100%"; svg.style.maxWidth = W + "px";
  const colors = { anthropic: "#c9764a", openai: "#6aa9c9", kimi: "#8b7ff0", zai: "#7fc98b" };
  const mk = (tag, attrs) => {
    const n = document.createElementNS("http://www.w3.org/2000/svg", tag);
    for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
    return n;
  };
  // 눈금: 0/50/100%
  for (const pct of [0, 50, 100]) {
    const y = H - PAD - (H - 2 * PAD) * pct / 100;
    svg.appendChild(mk("line", { x1: PAD, y1: y, x2: W - 8, y2: y,
      stroke: "#2a2b30", "stroke-width": 1 }));
    const t = mk("text", { x: 4, y: y + 4, fill: "#8a8b90", "font-size": 11 });
    t.textContent = pct + "%"; svg.appendChild(t);
  }
  const allT = keys.flatMap((k) => series[k].map((p) => p.t)).filter(Boolean).sort();
  const t0 = allT[0], t1 = allT[allT.length - 1];
  const span = (new Date(t1) - new Date(t0)) || 1;
  let li = 0;
  for (const k of keys) {
    const prov = k.split(".")[0];
    const color = colors[prov] || "#aaa";
    const pts = series[k].filter((p) => p.t).map((p) => {
      const x = PAD + (W - PAD - 12) * ((new Date(p.t) - new Date(t0)) / span);
      const y = H - PAD - (H - 2 * PAD) * Math.min(100, Math.max(0, p.v)) / 100;
      return x.toFixed(1) + "," + y.toFixed(1);
    });
    svg.appendChild(mk("polyline", { points: pts.join(" "), fill: "none",
      stroke: color, "stroke-width": k.includes("weekly") ? 2 : 1,
      "stroke-dasharray": k.includes("fiveHour") ? "4 3" : "" }));
    const lg = mk("text", { x: PAD + 4 + li * 150, y: 14, fill: color, "font-size": 11 });
    lg.textContent = k.replace(".weeklyPercent", " 주간").replace(".fiveHourPercent", " 5시간(점선)");
    svg.appendChild(lg); li += 1;
  }
  return svg;
}

async function pageScores(main) {
  if (SCORES === null) {
    try {
      [SCORES, QHIST] = await Promise.all([
        (await fetch("/api/outcomes")).json(), (await fetch("/api/quota-history")).json()]);
    } catch (e) { SCORES = { error: String(e), table: [], recent: [] }; QHIST = {}; }
    render();
    return;
  }
  const head = el("div", "card");
  head.appendChild(el("h2", null, "성적 — 실행기×모델×노력"));
  head.appendChild(el("div", "dim row", "card_outcome " + (SCORES.total || 0)
    + "건 집계. 원본 원장: .orca/routing-events/*.jsonl · 에이전트 창구: curl /outcomes.txt"
    + " · '모름'은 표준 도입 전 기록 — 지우지 않고 모름으로 둔다"));
  if (SCORES.error) head.appendChild(el("div", "bad row", "⚠ " + SCORES.error));
  const table = el("table");
  const hd = el("tr");
  for (const t of ["모델", "역할", "노력", "카드", "통과율 (판정된 것 중)", "평균 라운드", "평균 작업분", "판정모름", "마지막"])
    hd.appendChild(el("th", null, t));
  table.appendChild(hd);
  for (const t of SCORES.table || []) {
    const tr = el("tr");
    const model = el("td", t.model === "모름" ? "dim" : null, t.model);
    model.style.whiteSpace = "nowrap";
    tr.appendChild(model);
    tr.appendChild(el("td", "dim", t.role));
    tr.appendChild(el("td", "dim", t.effort));
    tr.appendChild(el("td", "mono", String(t.n)));
    const rateTd = el("td");
    if (t.pass_rate === null) rateTd.appendChild(el("span", "dim", "판정 없음"));
    else rateTd.appendChild(barCell(t.pass_rate, t.pass_rate >= 70 ? "#7fc98b" : (t.pass_rate >= 40 ? "#c9a86a" : "#c96a6a")));
    tr.appendChild(rateTd);
    tr.appendChild(el("td", "dim mono", t.avg_rounds === null ? "모름" : String(t.avg_rounds)));
    tr.appendChild(el("td", "dim mono", t.avg_work_min === null ? "모름" : String(t.avg_work_min)));
    tr.appendChild(el("td", "dim mono", String(t.verdict_unknown)));
    const last = el("td", "dim", t.last || "");
    last.style.whiteSpace = "nowrap";
    tr.appendChild(last);
    table.appendChild(tr);
  }
  head.appendChild(table);
  main.appendChild(head);

  const qcard = el("div", "card");
  qcard.appendChild(el("h3", null, "쿼터 사용량 추이"));
  const q = QHIST || {};
  if (q.history_file && Object.keys(q.series || {}).length) {
    qcard.appendChild(el("div", "dim row", "원본: " + q.history_file));
    qcard.appendChild(quotaChart(q.series));
  } else {
    if (q.note) qcard.appendChild(el("div", "dim row", q.note));
    const reps = (q.current || {}).reports || [];
    if (!reps.length) qcard.appendChild(el("div", "dim row",
      "현재값 원본(~/.cache/rottie/routing-usage.json)의 reports 가 비어 있다 — Rottie 수집기가 아직 보고 전이거나 방금 재생성됐다."));
    const tiles = el("div", "tiles");
    for (const r of reps) {
      const parts = [];
      if (r.quota && r.quota.weeklyPercent !== undefined) parts.push("주간 " + r.quota.weeklyPercent + "%");
      if (r.quota && r.quota.fiveHourPercent !== undefined) parts.push("5시간 " + r.quota.fiveHourPercent + "%");
      tiles.appendChild(tile(r.provider, parts.join(" · ") || "모름", "현재값 (사용량)"));
    }
    qcard.appendChild(tiles);
  }
  main.appendChild(qcard);

  const rc = el("div", "card");
  rc.appendChild(el("h3", null, "최근 정산 40건"));
  const rt = el("table");
  const rh = el("tr");
  for (const t of ["때", "판", "역할", "모델", "노력", "판정", "작업분"]) rh.appendChild(el("th", null, t));
  rt.appendChild(rh);
  for (const r of SCORES.recent || []) {
    const tr = el("tr");
    const at = el("td", "dim", r.at); at.style.whiteSpace = "nowrap"; tr.appendChild(at);
    tr.appendChild(el("td", "dim", r.board || ""));
    tr.appendChild(el("td", "dim", r.role || "모름"));
    tr.appendChild(el("td", r.model ? null : "dim", r.model || "모름"));
    tr.appendChild(el("td", "dim", r.effort || "모름"));
    const v = String(r.verdict || "모름");
    tr.appendChild(el("td", v.toUpperCase().includes("PASS") ? "ok" : (v.toUpperCase().includes("FAIL") ? "bad" : "dim"), v));
    tr.appendChild(el("td", "dim mono", r.work_min === null || r.work_min === undefined ? "모름" : String(r.work_min)));
    rt.appendChild(tr);
  }
  rc.appendChild(rt);
  main.appendChild(rc);
}

// 스킬 원장 탭 — 원장(분류·메모)과 실측(SKILL.md 설명·심볼릭 링크)을 합쳐 보여준다.
let SKILLS = null;
async function pageSkills(main, cat) {
  if (SKILLS === null) {
    try { SKILLS = await (await fetch("/api/skills")).json(); }
    catch (e) { SKILLS = { error: String(e), items: [], cats: {}, ghosts: [] }; }
    render();
    return;
  }
  const head = el("div", "card");
  head.appendChild(el("h2", null, "스킬 원장"));
  head.appendChild(el("div", "dim row",
    "원장(분류·메모): " + (SKILLS.ledger_file || "") + " · 실물: " + (SKILLS.origin_dir || "")
    + " · 에이전트 창구: curl '/skills.txt?cat=design' · 링크는 매번 실측"));
  if (SKILLS.error) head.appendChild(el("div", "bad row", "⚠ " + SKILLS.error));
  // 분류 칩 — 클릭으로 필터. design 을 맨 앞에.
  const chips = el("div", "row");
  const catNames = Object.keys(SKILLS.cats || {}).sort((a, b) =>
    (a === "design" ? -1 : b === "design" ? 1 : SKILLS.cats[b] - SKILLS.cats[a]));
  const chip = (label, hash, active, count) => {
    const a = el("a", "tag" + (active ? " who" : ""), label + (count !== undefined ? " " + count : ""));
    a.href = "#" + hash;
    a.style.marginRight = "6px";
    chips.appendChild(a);
  };
  chip("전체", "skills", !cat, (SKILLS.items || []).length);
  for (const c of catNames) chip(c, "skills/" + encodeURIComponent(c), cat === c, SKILLS.cats[c]);
  head.appendChild(chips);
  main.appendChild(head);

  const items = (SKILLS.items || []).filter((it) => !cat || it.cats.includes(cat));
  const card = el("div", "card");
  card.appendChild(el("h3", null, (cat || "전체") + " — " + items.length + "개"));
  const table = el("table");
  const hd = el("tr");
  for (const t of ["이름", "분류", "설명 (SKILL.md 실측)", "링크 (codex·gjc·kimi)"])
    hd.appendChild(el("th", null, t));
  table.appendChild(hd);
  for (const it of items) {
    const tr = el("tr");
    const name = el("td", null, it.name);
    name.style.whiteSpace = "nowrap"; name.style.fontWeight = "600";
    tr.appendChild(name);
    const catsTd = el("td", "dim", it.cats.join(", "));
    catsTd.style.whiteSpace = "nowrap";
    if (it.cats.includes("미분류")) catsTd.className = "warn";
    tr.appendChild(catsTd);
    const full = it.desc + (it.note ? "  ·  메모: " + it.note : "");
    // 전역 CSS 가 td 를 줄바꿈 금지로 둔다 — grow 클래스로 접고, 너무 길면 잘라 툴팁으로.
    const desc = el("td", "dim grow", full.length > 220 ? full.slice(0, 220) + "…" : full);
    desc.title = full;
    tr.appendChild(desc);
    const linkTd = el("td");
    linkTd.style.whiteSpace = "nowrap";
    for (const [tool, st] of Object.entries(it.links || {})) {
      const mark = st === "link" ? "✓" : st === "copy" ? "≠" : "—";
      const cls = st === "link" ? "ok" : st === "copy" ? "warn" : "dim";
      const s = el("span", cls, mark + tool + " ");
      s.title = st === "link" ? "심볼릭 링크 정상" : st === "copy" ? "링크가 아니라 별도 실물 — 갈라질 수 있음" : "없음";
      linkTd.appendChild(s);
    }
    tr.appendChild(linkTd);
    table.appendChild(tr);
  }
  card.appendChild(table);
  if ((SKILLS.ghosts || []).length)
    card.appendChild(el("div", "warn row", "⚠ 원장에는 있는데 실물 없음: " + SKILLS.ghosts.join(", ")));
  card.appendChild(el("div", "dim row",
    "분류·메모 수정은 화면이 아니라 원장 파일에서 (한 스킬 = 한 줄). ✓=링크 정상, ≠=복사본(갈라질 위험), —=없음"));
  main.appendChild(card);
}

// 깨움 사슬 구조도 — "누가 누구를 지키나"를 층으로 그린다. 실측 데이터(판·감독 모델)를
// 그대로 꽂으므로 그림도 복제가 아니라 렌더링이다.
function wakeDiagram() {
  const card = el("div", "card");
  card.appendChild(el("h3", null, "깨움 사슬 구조도"));
  card.appendChild(el("div", "dim row", "화살표 방향 = 깨우거나 보고하는 방향. 노란 이름만 AI를 부르고, 나머지는 토큰 소비 0인 스크립트다."));
  const col = el("div");
  col.style.display = "flex"; col.style.flexDirection = "column";
  col.style.alignItems = "center"; col.style.padding = "8px 0";

  const box = (title, subLines, accent) => {
    const b = el("div");
    b.style.border = "1px solid " + (accent || "#3a3b40");
    b.style.borderRadius = "10px"; b.style.padding = "10px 18px";
    b.style.textAlign = "center"; b.style.background = "var(--card2)";
    b.style.minWidth = "320px"; b.style.maxWidth = "620px";
    const t = el("div", null, title); t.style.fontWeight = "600";
    b.appendChild(t);
    for (const s of subLines || []) {
      const d = el("div", "dim", s.text || s); d.style.fontSize = "12px"; d.style.marginTop = "3px";
      if (s.ai) d.style.color = "#c9a86a";
      b.appendChild(d);
    }
    return b;
  };
  const arrow = (label) => {
    const a = el("div", "dim");
    a.style.textAlign = "center"; a.style.padding = "3px 0"; a.style.fontSize = "12px";
    a.style.lineHeight = "1.5";
    a.textContent = label;
    return a;
  };

  col.appendChild(box("kyle", ["대시보드로 보고, 결정 관문·푸시 알림만 받는다"]));
  col.appendChild(arrow("▲ 결정·사고·완료만 보고"));
  col.appendChild(box("슈퍼감독 — Claude 세션 (판 사이·전체 자원·판 침묵 담당)", [
    "지켜주는 것: Monitor(세션 내장) · 판정 감시 diag-watch(5분, 스크립트)"]));
  col.appendChild(arrow("▲ 정체 신고기 편지 · 완료 보고 ─── ▼ 지시 편지 + 터미널 깨우기"));
  const boards = DATA.boards.filter((b) => !(b.name || "").toLowerCase().includes("super"));
  const boardLines = boards.length
    ? boards.map((b) => ({ text: b.name + " — 감독 " + (b.model || "모델 모름"), ai: false }))
    : ["살아 있는 판 없음"];
  col.appendChild(box("판 감독 (판마다 1명, 카드·발령·검수의 단일 작성자)", boardLines, "#5a6b8c"));
  col.appendChild(arrow("▲ 깨워주는 보조 4종 (판마다): companion=편지 즉시 · 자가 점검기=30분마다 · "
    + "중계기=5분 순찰 · 정체 신고기=슈퍼에 신고"));
  col.appendChild(box("보조 감시 4종", [
    "companion · 자가 점검기 · 정체 신고기 — 전부 셸 스크립트 (AI 없음)",
    { text: "중계기 — Python + 애매할 때만 AI 판정 (deepseek-v4-flash, 건당 $0.003)", ai: true }]));
  col.appendChild(arrow("▼ 감독이 발령·검수"));
  col.appendChild(box("작업자·검수자 (카드 단위 수명)", [
    "모델은 카드마다 라우터가 고른다 — 현재 편성·점수는 라우팅 탭(원본 routing-providers.json) 참고"]));
  card.appendChild(col);
  return card;
}

function pageWatchers(main) {
  main.appendChild(el("h2", null, "보조 감시"));
  main.appendChild(el("div", "sub",
    "슈퍼감독과 판 감독을 지키는 보조 프로세스들 — ps 실측 그대로, 추측 없음. "
    + "에이전트 창구: curl 127.0.0.1:8787/watchers.txt"));
  const w = DATA.watchers;
  if (!w) { main.appendChild(el("div", "bad", "수집 안 됨 — 서버가 옛 코드로 돌고 있을 수 있다.")); return; }
  main.appendChild(wakeDiagram());
  const superCard = el("div", "card");
  superCard.appendChild(el("h3", null, "슈퍼감독 층"));
  superCard.appendChild(el("div", "dim row", "판 전체·자원·슈퍼 우편함을 지킨다. 아래 판 보조들이 놓친 것을 여기서 잡는다."));
  superCard.appendChild(watcherTable(w.super || []));
  main.appendChild(superCard);
  const liveNames = DATA.boards.map((b) => b.name);
  const boards = Object.keys(w.boards || {});
  for (const name of boards) {
    const entries = w.boards[name];
    const card = el("div", "card");
    const h = el("h3", null, "판: " + name);
    card.appendChild(h);
    if (!liveNames.includes(name)) card.appendChild(el("div", "warn row", "⚠ 이 판의 감독 터미널이 안 보이는데 보조가 돌고 있다 — 잔재인지 확인 필요"));
    card.appendChild(watcherTable(entries));
    const seen = entries.map((e) => e.kind);
    const expectedLabels = { "relay-patrol.py": "중계기", "stall-reporter.sh": "정체 신고기",
      "supervisor-waker.sh": "감독 자가 점검기", "conductor-companion.sh": "companion (배달부)" };
    const missing = Object.keys(expectedLabels).filter((k) => !seen.includes(k)).map((k) => expectedLabels[k]);
    if (missing.length && liveNames.includes(name))
      card.appendChild(el("div", "bad row", "⚠ 빠짐: " + missing.join(", ") + " — 살아 있는 판에는 넷 다 있어야 한다"));
    main.appendChild(card);
  }
  for (const name of liveNames) {
    // 슈퍼 판은 판 보조 대신 슈퍼감독 세션의 Monitor 가 지킨다 — diagnose() 와 같은 기준.
    if (name && !boards.includes(name) && !name.toLowerCase().includes("super")) {
      const card = el("div", "card");
      card.appendChild(el("h3", null, "판: " + name));
      card.appendChild(el("div", "bad row", "⚠ 보조 감시가 하나도 안 떠 있다 — 이 판은 침묵해도 아무도 모른다"));
      main.appendChild(card);
    }
  }
}

function pageDormant(main) {
  main.appendChild(el("h2", null, "지난 기록"));
  main.appendChild(el("div", "sub", "감독 터미널이 사라진 실행 기록(run) " + DATA.dormant.length
    + "개 — 끝난 판, 일회용 시험, 레거시가 섞여 있다. 장부에 판을 닫는 표시가 없어 기록이 계속 남는다."));
  const card = el("div", "card");
  const table = el("table");
  const head = el("tr");
  for (const t of ["이름", "실행 기록(run)", "만든 때"]) head.appendChild(el("th", null, t));
  table.appendChild(head);
  for (const d of DATA.dormant) {
    const tr = el("tr");
    tr.appendChild(el("td", "grow", d.name));
    tr.appendChild(el("td", "dim mono", d.run_id));
    tr.appendChild(el("td", "dim", ageOf(d.created_at)));
    table.appendChild(tr);
  }
  card.appendChild(table);
  main.appendChild(card);
}

// 메모함 — 대시보드의 유일한 쓰기 경로. 판 카드를 직접 만들지 않는다(카드는 감독이
// 단일 작성자). 쌓인 메모는 슈퍼감독이 읽고 저장소 TODO/판 지시로 분배한다.
let MEMOS = null;
async function loadMemos() {
  try { MEMOS = await (await fetch("/api/memo")).json(); } catch (e) { MEMOS = { items: [], error: String(e) }; }
}
async function pageMemo(main) {
  if (MEMOS === null) { await loadMemos(); renderSide(); }
  const form = el("div", "card");
  form.appendChild(el("h2", null, "메모함"));
  form.appendChild(el("div", "dim row",
    "생각날 때 적어두면 슈퍼감독이 읽고 저장소 TODO나 판 지시로 분배한다. 원본: " + (MEMOS.file || "")));
  const bar = el("div", "row");
  const input = el("input", "search");
  input.placeholder = "메모 입력 후 Enter (예: 우편함에 발신시각 추가)";
  input.style.flex = "1";
  const submit = async () => {
    const text = input.value.trim();
    if (!text) return;
    input.disabled = true;
    try {
      const res = await fetch("/api/memo", { method: "POST",
        headers: { "Content-Type": "application/json" }, body: JSON.stringify({ text }) });
      const d = await res.json();
      if (d.error) { alert(d.error); } else { MEMOS = d; input.value = ""; }
    } catch (e) { alert("저장 실패: " + e); }
    input.disabled = false;
    render();
    setTimeout(() => { const i = document.querySelector("input.search"); if (i) i.focus(); }, 0);
  };
  input.addEventListener("keydown", (e) => { if (e.key === "Enter") submit(); });
  bar.appendChild(input);
  const btn = el("a", "tag who", "추가");
  btn.href = "javascript:void(0)";
  btn.onclick = submit;
  bar.appendChild(btn);
  form.appendChild(bar);
  main.appendChild(form);
  const card = el("div", "card");
  if (MEMOS.error) card.appendChild(el("div", "bad row", "⚠ " + MEMOS.error));
  if (!MEMOS.items.length) card.appendChild(el("div", "dim", "아직 메모가 없다."));
  const table = el("table");
  for (const line of [...MEMOS.items].reverse()) {
    const m = line.match(/^(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}) \\| (.*)$/);
    const tr = el("tr");
    tr.appendChild(el("td", "dim", m ? m[1] : ""));
    tr.appendChild(el("td", "grow", m ? m[2] : line));
    table.appendChild(tr);
  }
  card.appendChild(table);
  main.appendChild(card);
}

// 라우팅 보기 — 읽기 전용. 정책 수정은 routing-providers.json 파일이지 화면이 아니다.
let ROUTING = null;
async function pageRouting(main) {
  if (ROUTING === null) {
    try { ROUTING = await (await fetch("/api/routing")).json(); }
    catch (e) { ROUTING = { error: String(e) }; }
    render();
    return;
  }
  const head = el("div", "card");
  head.appendChild(el("h2", null, "라우팅 편성표"));
  head.appendChild(el("div", "dim row",
    "점수는 모델×역할×노력 묶음 단위. 수정은 화면이 아니라 원본 파일에서: " + (ROUTING.file || "")));
  if (ROUTING.error) head.appendChild(el("div", "bad row", "⚠ " + ROUTING.error));
  for (const p of ROUTING.policies || []) {
    const box = el("div", "row");
    box.appendChild(el("span", "tag who", p.key.replace("_", "") + (p["확정"] ? " · " + p["확정"] : "")));
    const ul = el("div");
    for (const [k, v] of Object.entries(p)) {
      if (k === "key" || k === "확정") continue;
      ul.appendChild(el("div", null, "· " + (k === "내용" ? "" : k + ": ") + String(v)));
    }
    box.appendChild(ul);
    head.appendChild(box);
  }
  main.appendChild(head);

  const quotaByKey = {};
  for (const q of ROUTING.quota || []) quotaByKey[q.provider] = q.quota || {};
  const qAge = ROUTING.quota_age_sec;

  for (const prov of ROUTING.providers || []) {
    const card = el("div", "card");
    const h = el("h3", null, prov.id + "  ·  주간 예약선 " + (prov.weeklyReservePercent ?? "?") + "%");
    card.appendChild(h);
    const q = quotaByKey[prov.quotaKey || prov.id];
    if (q) {
      const bits = [];
      if (q.fiveHourPercent !== undefined) bits.push("5시간 " + q.fiveHourPercent + "%");
      if (q.weeklyPercent !== undefined) bits.push("주간 " + q.weeklyPercent + "%");
      card.appendChild(el("div", "dim row", "쿼터: " + (bits.join(" · ") || "값 없음")
        + (qAge !== null && qAge !== undefined ? "  (수집 " + Math.round(qAge / 60) + "분 전)" : "  (수집 시각 모름)")));
    } else {
      card.appendChild(el("div", "dim row", "쿼터: 모름 (수집 안 됨)"));
    }
    const table = el("table");
    const hd = el("tr");
    for (const c of ["모델", "역할", "노력", "점수", "상태", "가산점(taskClassPrior)"])
      hd.appendChild(el("th", "dim", c));
    table.appendChild(hd);
    for (const m of prov.models || []) {
      const tr = el("tr");
      const off = m.enabled === false;
      tr.appendChild(el("td", "mono" + (off ? " dim" : ""), m.id || ""));
      tr.appendChild(el("td", off ? "dim" : "", m.role || ""));
      tr.appendChild(el("td", off ? "dim" : "", m.effort || ""));
      const qcell = el("td", off ? "dim" : "ok", String(m.quality ?? "?"));
      tr.appendChild(qcell);
      let st = off ? "꺼짐" : "";
      if (m.experimental) st += (st ? " · " : "") + "실험 " + (m.experimentSharePercent ?? "?") + "%";
      if (m.lastResortOnly) st += (st ? " · " : "") + "최후수단";
      tr.appendChild(el("td", off ? "bad" : "warn", st));
      const pri = m.taskClassPrior || {};
      const ptxt = Object.entries(pri).map(([k, v]) => k + (v >= 0 ? "+" : "") + v).join("  ");
      tr.appendChild(el("td", "dim", ptxt || "—"));
      table.appendChild(tr);
    }
    const wrap = el("div", "scroll");
    wrap.appendChild(table);
    card.appendChild(wrap);
    main.appendChild(card);
  }
}

// 규칙 표면 — 원본 파일 렌더링. 에이전트는 curl /rules.txt 로 같은 것을 본다.
let RULES = null;
async function pageRules(main) {
  if (RULES === null) {
    try { RULES = await (await fetch("/api/rules")).json(); }
    catch (e) { RULES = { docs: [], error: String(e) }; }
    render();
    return;
  }
  const head = el("div", "card");
  head.appendChild(el("h2", null, "규칙 표면"));
  head.appendChild(el("div", "dim row",
    "사람은 이 화면, 에이전트는 curl -s http://127.0.0.1:8787/rules.txt — 같은 원본이다. 수정은 원본 파일에서만."));
  main.appendChild(head);
  for (const doc of RULES.docs || []) {
    const card = el("div", "card");
    card.appendChild(el("h3", null, doc.title));
    card.appendChild(el("div", "dim row", doc.path + "  (수정 " + (doc.mtime || "모름") + ")"));
    if (doc.error) { card.appendChild(el("div", "bad row", "⚠ " + doc.error)); main.appendChild(card); continue; }
    const pre = el("pre");
    pre.style.whiteSpace = "pre-wrap";
    pre.style.fontSize = "12px";
    pre.textContent = doc.text || "";
    const wrap = el("div", "scroll");
    wrap.style.maxHeight = "60vh";
    wrap.style.overflowY = "auto";
    wrap.appendChild(pre);
    card.appendChild(det("rule-" + doc.title, "펼쳐 보기", wrap));
    main.appendChild(card);
  }
}

function render() {
  renderSide();
  const main = $("main");
  const scrollY = window.scrollY;
  main.replaceChildren();
  if (!DATA) { main.appendChild(el("div", "dim", "불러오는 중…")); return; }
  for (const e of DATA.errors) main.appendChild(el("div", "bad row", "⚠ " + e));
  const r = route();
  if (r.page === "board") pageBoard(main, r.id);
  else if (r.page === "mail") pageMail(main);
  else if (r.page === "terms") pageTerms(main);
  else if (r.page === "ledger") pageLedger(main, r.id);
  else if (r.page === "dormant") pageDormant(main);
  else if (r.page === "memo") pageMemo(main);
  else if (r.page === "routing") pageRouting(main);
  else if (r.page === "scores") pageScores(main);
  else if (r.page === "skills") pageSkills(main, r.id);
  else if (r.page === "watchers") pageWatchers(main);
  else if (r.page === "rules") pageRules(main);
  else pageOverview(main);
  window.scrollTo(0, scrollY);
}

async function refresh() {
  try {
    DATA = await (await fetch("/api/status")).json();
  } catch (e) {
    const main = $("main");
    main.replaceChildren(el("div", "bad", "서버 응답 없음 — board-dashboard.py 가 꺼졌는지 확인"));
    return;
  }
  // 검색창에 입력 중이면 화면을 갈아엎지 않는다 — 타이핑이 날아간다 (2026-08-10 실측).
  if (document.activeElement && document.activeElement.tagName === "INPUT") return;
  render();
}

window.addEventListener("hashchange", () => { window.scrollTo(0, 0); render(); });
refresh();
setInterval(() => { if (!document.hidden) refresh(); }, 15000);
document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
</script>
</body>
</html>
"""


def make_handler(cache: Cache):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def _send(self, code: int, ctype: str, body: bytes):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/" or self.path.startswith("/index"):
                self._send(200, "text/html; charset=utf-8", PAGE.encode())
            elif self.path == "/status.txt":
                self._send(
                    200,
                    "text/plain; charset=utf-8",
                    status_text(cache.get()).encode(),
                )
            elif self.path.startswith("/skills.txt"):
                query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                cat = (query.get("cat") or [None])[0]
                self._send(200, "text/plain; charset=utf-8", skills_txt(cat).encode())
            elif self.path.startswith("/api/skills"):
                body = json.dumps(skills_view(), ensure_ascii=False).encode()
                self._send(200, "application/json; charset=utf-8", body)
            elif self.path == "/outcomes.txt":
                self._send(200, "text/plain; charset=utf-8", outcomes_txt().encode())
            elif self.path.startswith("/api/outcomes"):
                body = json.dumps(outcomes_view(), ensure_ascii=False).encode()
                self._send(200, "application/json; charset=utf-8", body)
            elif self.path.startswith("/api/quota-history"):
                body = json.dumps(quota_history_view(), ensure_ascii=False).encode()
                self._send(200, "application/json; charset=utf-8", body)
            elif self.path == "/watchers.txt":
                self._send(
                    200,
                    "text/plain; charset=utf-8",
                    watchers_txt(cache.get()).encode(),
                )
            elif self.path.startswith("/api/status"):
                body = json.dumps(cache.get(), ensure_ascii=False).encode()
                self._send(200, "application/json; charset=utf-8", body)
            elif self.path.startswith("/api/mail"):
                cache.get()  # 명패 해석기를 최신으로 만들어 둔다
                query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                try:
                    limit = int((query.get("limit") or ["400"])[0])
                except ValueError:
                    limit = 400
                body = json.dumps(mail_history(limit), ensure_ascii=False).encode()
                self._send(200, "application/json; charset=utf-8", body)
            elif self.path.startswith("/api/ledger/tables"):
                body = json.dumps(ledger_tables(), ensure_ascii=False).encode()
                self._send(200, "application/json; charset=utf-8", body)
            elif self.path.startswith("/api/ledger/table"):
                query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                name = (query.get("name") or [""])[0]
                try:
                    limit = int((query.get("limit") or [str(LEDGER_ROW_LIMIT)])[0])
                    offset = max(0, int((query.get("offset") or ["0"])[0]))
                except ValueError:
                    limit, offset = LEDGER_ROW_LIMIT, 0
                body = json.dumps(ledger_rows(name, limit, offset), ensure_ascii=False).encode()
                self._send(200, "application/json; charset=utf-8", body)
            elif self.path.startswith("/api/memo"):
                body = json.dumps(memo_list(), ensure_ascii=False).encode()
                self._send(200, "application/json; charset=utf-8", body)
            elif self.path.startswith("/api/routing"):
                body = json.dumps(routing_view(), ensure_ascii=False).encode()
                self._send(200, "application/json; charset=utf-8", body)
            elif self.path.startswith("/api/rules"):
                body = json.dumps(rules_view(), ensure_ascii=False).encode()
                self._send(200, "application/json; charset=utf-8", body)
            elif self.path.startswith("/rules.txt"):
                query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                want = (query.get("doc") or [None])[0]
                self._send(200, "text/plain; charset=utf-8", rules_txt(want).encode())
            else:
                self._send(404, "text/plain; charset=utf-8", b"not found")

        def do_POST(self):
            if self.path.startswith("/api/memo"):
                try:
                    length = int(self.headers.get("Content-Length") or 0)
                    payload = json.loads(self.rfile.read(length).decode("utf-8"))
                    result = memo_add(str(payload.get("text", "")))
                except (ValueError, UnicodeDecodeError) as e:
                    result = {"error": f"요청을 못 읽었다: {e}"}
                code = 400 if "error" in result else 200
                self._send(code, "application/json; charset=utf-8",
                           json.dumps(result, ensure_ascii=False).encode())
            else:
                self._send(404, "text/plain; charset=utf-8", b"not found")

    return Handler


def arg_value(flag: str, default: str) -> str:
    if flag in sys.argv:
        idx = sys.argv.index(flag)
        if idx + 1 < len(sys.argv):
            return sys.argv[idx + 1]
    return default


def main() -> int:
    orca = bs.find_orca()
    if orca is None:
        print("orca 실행 파일을 못 찾았다. ORCA_BIN 을 지정하라.", file=sys.stderr)
        return 2
    host = arg_value("--host", "127.0.0.1")
    port = int(arg_value("--port", "8787"))
    server = ThreadingHTTPServer((host, port), make_handler(Cache(orca)))
    shown = "localhost" if host == "127.0.0.1" else host
    print(f"판 관제 대시보드: http://{shown}:{port}  (Ctrl+C 로 종료)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
