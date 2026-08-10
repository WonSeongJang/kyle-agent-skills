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

import importlib.util
import json
import os
import re
import sqlite3
import subprocess
import sys
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
    """판이름 -> [{pid, cmd}]. board-status 의 PID 수집에 실행 명령(위치)을 더한 판."""
    out: dict[str, list[dict]] = {}
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
        pid, _, cmd = line.strip().partition(" ")
        if pid.isdigit():
            out.setdefault(match.group(1), []).append(
                {"pid": int(pid), "cmd": cmd.strip()[:200]}
            )
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
    return out


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
