#!/usr/bin/env python3
"""판 현황 로컬 웹 대시보드.

Why: kyle이 판 진행을 보려고 감독을 깨우면 감독 턴이 탄다 (2026-08-10 실사고).
board-status.py 는 터미널 한 번 흘끗용이고, 이 서버는 브라우저 탭에 계속 띄워두는
용도다. 카드 상태 + 중계기 일기 꼬리 + 우편함 + 터미널 목록을 한 화면에 보여준다.
감독·중계기·companion 어느 것도 건드리지 않고 읽기만 한다.

우편함은 `orca orchestration inbox` 만 쓴다 — 읽음 처리(ack)가 없는 조회 명령이라
감독이 받을 편지를 가로채지 않는다. `check`(기본 모드)는 여기서 절대 쓰지 않는다.

실행:
    board-dashboard.py                  (기본 http://127.0.0.1:8787)
    board-dashboard.py --port 9000
    board-dashboard.py --host 0.0.0.0   (같은 와이파이의 폰에서도 볼 때)

표준 파이썬만 쓴다. 설치가 하나라도 필요하면 안 쓰게 된다.
"""

from __future__ import annotations

import importlib.util
import json
import sys
import threading
import time
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
RELAY_TAIL_LINES = 40
INBOX_LIMIT = 60


def relay_tail(path: Path) -> list[str]:
    """일기 파일 꼬리만 읽는다. 265KB 전체를 매번 읽지 않는다."""
    try:
        with path.open("rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 16384))
            chunk = f.read().decode("utf-8", errors="replace")
    except OSError:
        return []
    lines = chunk.splitlines()
    if len(lines) > 1:
        lines = lines[1:]  # 앞쪽 잘린 반 줄 제거
    return lines[-RELAY_TAIL_LINES:]


def last_preview_line(preview: str) -> str:
    for line in reversed((preview or "").splitlines()):
        if line.strip():
            return line.strip()
    return ""


def collect(orca: str) -> dict:
    errors: list[str] = []
    out: dict = {
        "collected_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "system": bs.system_line(),
        "boards": [],
        "dormant": [],
        "messages": None,  # None = 못 읽음(모름). 빈 목록과 구분한다.
        "terminals": [],
        "errors": errors,
    }

    runs_data = bs.run_json(orca, ["orchestration", "run-list"])
    terminals, term_err = bs.collect_terminals(orca)
    relay_logs = bs.collect_relay_logs()
    helpers = bs.collect_helpers()
    inbox = bs.run_json(orca, ["orchestration", "inbox", "--limit", str(INBOX_LIMIT)])

    if term_err:
        errors.append(f"{term_err} — 감독 생존·Context 는 '모름'으로 둔다.")

    run_names: dict[str, str] = {}
    runs = []
    if runs_data is None:
        errors.append("run-list 를 못 읽었다 — 판 목록은 비어 있는 게 아니라 '모름'이다.")
    else:
        runs = runs_data.get("result", {}).get("runs") or []
        for run in runs:
            run_names[run.get("id", "")] = bs.board_name(run.get("objective", ""))

    if inbox is not None:
        msgs = inbox.get("result", {}).get("messages") or []
        out["messages"] = [
            {
                "id": m.get("id"),
                "board": run_names.get(m.get("run_id", ""), m.get("run_id", "?")),
                "type": m.get("type"),
                "priority": m.get("priority"),
                "subject": m.get("subject"),
                "body": m.get("body"),
                "read": bool(m.get("read")),
                "created_at": m.get("created_at"),
            }
            for m in msgs
        ]
    else:
        errors.append("우편함(inbox)을 못 읽었다 — 비어 있는 게 아니라 '모름'이다.")

    for run in runs:
        handle = run.get("coordinator_handle")
        term = terminals.get(handle) if (terminals and handle) else None
        name = bs.board_name(run.get("objective", ""))
        if term is None:
            out["dormant"].append({"name": name, "run_id": run.get("id", "")})
            continue

        preview = term.get("preview", "")
        board: dict = {
            "name": name,
            "run_id": run.get("id", ""),
            "context_pct": bs.parse_context_pct(preview),
            "context_warn": bs.CONTEXT_WARN,
            "weekly_left": bs.parse_weekly_left(preview),
            "cards": None,
            "dispatched": [],
            "relay": None,
            "companions": helpers.get(name, []),
        }

        tasks_data = bs.run_json(
            orca, ["orchestration", "task-list", "--run", run.get("id", "")]
        )
        if tasks_data is not None:
            tasks = tasks_data.get("result", {}).get("tasks") or []
            buckets: dict[str, int] = {}
            for task in tasks:
                status = task.get("status") or "?"
                buckets[status] = buckets.get(status, 0) + 1
                if status == "dispatched":
                    board["dispatched"].append(
                        (task.get("display_name") or task.get("title") or "")[:90]
                    )
            board["cards"] = buckets

        entry = relay_logs.get(name)
        if entry is not None:
            path, age = entry
            board["relay"] = {
                "age_sec": int(age),
                "age_text": bs.age_text(age),
                "warn_sec": bs.RELAY_WARN_SEC,
                "dead_sec": bs.RELAY_DEAD_SEC,
                "path": str(path),
                "tail": relay_tail(path),
            }
        out["boards"].append(board)

    if terminals:
        now_ms = time.time() * 1000
        for term in terminals.values():
            last = term.get("lastOutputAt")
            out["terminals"].append(
                {
                    "title": term.get("title") or "",
                    "worktree": Path(term.get("worktreePath") or "").name,
                    "connected": bool(term.get("connected")),
                    "age_text": bs.age_text((now_ms - last) / 1000 if last else None),
                    "preview": last_preview_line(term.get("preview", ""))[:160],
                }
            )
        out["terminals"].sort(key=lambda t: t["title"])
    return out


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
<title>판 현황</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 16px; background: #14161a; color: #d7dae0;
         font: 14px/1.5 -apple-system, "Apple SD Gothic Neo", sans-serif; }
  h1 { font-size: 18px; margin: 0 0 4px; }
  .dim { color: #7c8290; } .warn { color: #e8b93e; } .bad { color: #e06c60; }
  .ok { color: #6fbf73; } .accent { color: #62aeef; }
  #meta { margin-bottom: 14px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(340px, 1fr));
          gap: 12px; align-items: start; }
  .card { background: #1b1e24; border: 1px solid #2a2e36; border-radius: 8px; padding: 12px 14px; }
  .card h2 { font-size: 15px; margin: 0 0 8px; }
  .row { margin: 3px 0; }
  .label { display: inline-block; width: 52px; color: #7c8290; }
  pre, .mono { font: 12px/1.45 ui-monospace, Menlo, monospace; }
  pre { background: #14161a; border: 1px solid #262a31; border-radius: 6px;
        padding: 8px; max-height: 260px; overflow: auto; white-space: pre-wrap;
        word-break: break-all; margin: 6px 0 0; }
  details > summary { cursor: pointer; color: #7c8290; }
  table { border-collapse: collapse; width: 100%; }
  td { padding: 3px 8px 3px 0; vertical-align: top; white-space: nowrap; }
  td.preview { white-space: normal; word-break: break-all; width: 100%; }
  .msg { border-top: 1px solid #262a31; padding: 6px 0; }
  .msg:first-child { border-top: none; }
  .unread { font-weight: 600; }
  .tag { display: inline-block; font-size: 11px; border: 1px solid #3a3f49;
         border-radius: 4px; padding: 0 5px; margin-right: 6px; color: #9aa1ad; }
  .wide { grid-column: 1 / -1; }
  .scroll { max-height: 320px; overflow: auto; }
</style>
</head>
<body>
<h1>판 현황 <span id="clock" class="dim"></span></h1>
<div id="meta" class="dim mono"></div>
<div id="errors"></div>
<div class="grid" id="boards"></div>
<div class="grid" style="margin-top:12px">
  <div class="card wide" id="mailbox-card"><h2>우편함 <span class="dim" id="mail-sub"></span></h2><div id="mailbox" class="scroll"></div></div>
  <div class="card wide" id="terminals-card"><h2>터미널 <span class="dim" id="term-sub"></span></h2><div id="terminals" class="scroll"></div></div>
</div>
<script>
const $ = (id) => document.getElementById(id);
function el(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
}
function ageOf(iso) {
  if (!iso) return "";
  const sec = Math.max(0, (Date.now() - Date.parse(iso)) / 1000);
  if (sec < 60) return Math.floor(sec) + "초 전";
  if (sec < 3600) return Math.floor(sec / 60) + "분 전";
  return Math.floor(sec / 3600) + "시간 " + Math.floor((sec % 3600) / 60) + "분 전";
}

function renderBoard(b) {
  const card = el("div", "card");
  const h = el("h2", null, b.name + "  ");
  h.appendChild(el("span", "dim mono", b.run_id));
  card.appendChild(h);

  const sup = el("div", "row");
  sup.appendChild(el("span", "label", "감독"));
  if (b.context_pct === null) sup.appendChild(el("span", "dim", "Context 모름"));
  else if (b.context_pct >= b.context_warn)
    sup.appendChild(el("span", "bad", "Context " + b.context_pct + "% ⚠ 교대 조건"));
  else sup.appendChild(el("span", null, "Context " + b.context_pct + "%"));
  if (b.weekly_left) sup.appendChild(el("span", "dim", "  주간 잔여 " + b.weekly_left));
  card.appendChild(sup);

  const cards = el("div", "row");
  cards.appendChild(el("span", "label", "카드"));
  if (b.cards === null) cards.appendChild(el("span", "bad", "못 읽음 (0개가 아니라 모름)"));
  else {
    const c = b.cards;
    let text = "도는 중 " + (c.dispatched || 0) + "   대기 " + (c.ready || 0);
    cards.appendChild(el("span", null, text));
    if (c.failed) cards.appendChild(el("span", "warn", "   실패 " + c.failed));
    cards.appendChild(el("span", "dim", "   완료 " + (c.completed || 0)));
  }
  card.appendChild(cards);
  for (const name of b.dispatched)
    card.appendChild(el("div", "row accent", "   ▸ " + name));

  const relay = el("div", "row");
  relay.appendChild(el("span", "label", "중계기"));
  if (!b.relay) relay.appendChild(el("span", "warn", "일기 없음 — 중계기를 안 세웠거나 판 이름이 다르다"));
  else {
    const cls = b.relay.age_sec > b.relay.dead_sec ? "bad"
              : b.relay.age_sec > b.relay.warn_sec ? "warn" : "ok";
    const suffix = b.relay.age_sec > b.relay.dead_sec ? "  ⚠ 감시 멈춤"
                 : b.relay.age_sec > b.relay.warn_sec ? "  (느림)" : "";
    relay.appendChild(el("span", cls, "일기 " + b.relay.age_text + suffix));
  }
  card.appendChild(relay);

  const comp = el("div", "row");
  comp.appendChild(el("span", "label", "깨우미"));
  if (b.companions.length)
    comp.appendChild(el("span", "ok", "companion 살아있음 " + JSON.stringify(b.companions)));
  else comp.appendChild(el("span", "bad", "companion 없음 — 완료 편지가 와도 감독이 안 깨어난다"));
  card.appendChild(comp);

  if (b.relay && b.relay.tail.length) {
    const det = el("details");
    det.appendChild(el("summary", null, "중계기 일기 꼬리 (" + b.relay.tail.length + "줄)"));
    det.appendChild(el("pre", null, b.relay.tail.join("\\n")));
    card.appendChild(det);
  }
  return card;
}

function renderMailbox(msgs) {
  const box = $("mailbox");
  box.replaceChildren();
  if (msgs === null) {
    $("mail-sub").textContent = "";
    box.appendChild(el("div", "bad", "우편함을 못 읽었다 — 비어 있는 게 아니라 모름"));
    return;
  }
  const unread = msgs.filter((m) => !m.read).length;
  $("mail-sub").textContent = "최근 " + msgs.length + "통 · 안 읽음 " + unread;
  for (const m of msgs) {
    const row = el("div", "msg" + (m.read ? "" : " unread"));
    const head = el("div");
    head.appendChild(el("span", "tag", m.board));
    head.appendChild(el("span", "tag", m.type + (m.priority === "high" ? " · high" : "")));
    head.appendChild(el("span", "dim", ageOf(m.created_at) + "  "));
    head.appendChild(el("span", m.read ? "dim" : null, m.subject || "(제목 없음)"));
    row.appendChild(head);
    if (m.body) {
      const det = el("details");
      det.appendChild(el("summary", null, "내용"));
      det.appendChild(el("pre", null, m.body));
      row.appendChild(det);
    }
    box.appendChild(row);
  }
}

function renderTerminals(terms) {
  const box = $("terminals");
  box.replaceChildren();
  $("term-sub").textContent = terms.length + "개";
  const table = el("table", "mono");
  for (const t of terms) {
    const tr = el("tr");
    tr.appendChild(el("td", t.connected ? null : "dim", t.title));
    tr.appendChild(el("td", "dim", t.age_text));
    tr.appendChild(el("td", "dim preview", t.preview));
    table.appendChild(tr);
  }
  box.appendChild(table);
}

async function refresh() {
  let d;
  try {
    d = await (await fetch("/api/status")).json();
  } catch (e) {
    $("meta").textContent = "서버 응답 없음 — board-dashboard.py 가 꺼졌는지 확인";
    $("meta").className = "bad mono";
    return;
  }
  $("meta").className = "dim mono";
  $("clock").textContent = d.collected_at + " 수집";
  $("meta").textContent = d.system;
  const errs = $("errors");
  errs.replaceChildren();
  for (const e of d.errors) errs.appendChild(el("div", "bad row", "⚠ " + e));

  const boards = $("boards");
  boards.replaceChildren();
  if (!d.boards.length) boards.appendChild(el("div", "warn", "감독 터미널이 살아 있는 판이 없다."));
  for (const b of d.boards) boards.appendChild(renderBoard(b));
  if (d.dormant.length)
    boards.appendChild(el("div", "dim", "잠든 판 " + d.dormant.length + "개 (감독 터미널 없음)"));

  renderMailbox(d.messages);
  renderTerminals(d.terminals);
}

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
    print(f"판 현황 대시보드: http://{shown}:{port}  (Ctrl+C 로 종료)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
