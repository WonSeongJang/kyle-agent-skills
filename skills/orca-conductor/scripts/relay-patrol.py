#!/usr/bin/env python3
"""헤드리스 중계기 순찰 — 셸이 숫자를 세고, 애매할 때만 모델을 부른다.

Why: 지금 중계기는 Orca 터미널에 상주하는 luna 에이전트이고, LLM 이 상주 턴을 못 버티므로
kicker 가 5분마다 찔러 깨운다. 그런데 일기 545줄을 세어 보니 순찰 124번 중 실제로 뭔가를
보낸 것은 escalation 2 · wake 2 뿐이었다 (2026-08-10 실측). 122번은 헛걸음이다.

순찰 원문은 전부 숫자 비교다 — cursor 증감, 도구 실행 줄 수, Context%. 모델이 필요한 곳은
한 군데뿐이다: 새로 보이는 줄이 **진짜 새 작업인지, 아니면 다시 그려진 화면·인용된 프롬프트인지**.

그래서 셸이 판정하고, 애매할 때만 DeepSeek 을 1회 부른다.
**애매하면 무조건 부른다 (2026-08-10 kyle 결정)** — 잘못 조용해지느니 몇 번 더 부르는 게 낫다.

사용:
    relay-patrol.py --project <p> --board <b> --run <run_id> [--once] [--interval 300]

--once 없이 실행하면 --interval 초마다 반복한다. 띄우고 잊는다 — 종료를 기다리지 않는다.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ORCA_BUNDLE = "/Users/fw_m1/Dev/orca-kyle/dist/mac-arm64/Orca Kyle.app/Contents/Resources/bin/orca-kyle"
JUDGE_MODEL = "deepseek/deepseek-v4-flash"

# 진행 증거로 인정하는 도구 실행 줄 (mechanics.md 장기 카드 정체 판정)
TOOL_MARKERS = ("• Ran", "• Explored", "• Edited", "• Read", "• Search")
# 프록시 계열 오류 — 중계기가 직접 복구한다 (mechanics.md 중계기 절 프록시 자가 복구)
PROXY_ERRORS = ("stream disconnected", "127.0.0.1:10100", "426 Upgrade Required")
# 연속 무진행 몇 회에서 정체로 보는가 (5분 간격 2회 = 약 10분)
STALL_CYCLES = 2
# 판 수명 동안 계속 dispatched 로 남는 상주 역할 카드의 이름.
# 이 카드들은 "지금 누가 일하고 있다"가 아니라 "이 장치가 살아 있다"를 뜻하므로
# 일반 작업 수에 세지 않는다 (2026-08-12 실측: 일반 0장인데 RELAY-MONITOR 한 장
# 때문에 도는 카드=1 로 세어 조용한 감독을 연속 정체 5회로 오판했다).
RESIDENT_CARD_TITLES = ("RELAY-MONITOR",)
# 번들이 tasks.status 에 실제로 허용하는 값 전부. 추정이 아니라 실측이다 —
# 운영 DB `orchestration.db` 의 tasks 테이블 CHECK 제약과 같다 (2026-08-12 확인):
#   CHECK(status IN ('pending','ready','dispatched','completed','failed','blocked'))
# 이 목록 밖 값이 오면 응답을 이해하지 못한 것이므로 0 이 아니라 '모름'으로 닫는다.
KNOWN_TASK_STATUSES = frozenset(
    {"pending", "ready", "dispatched", "completed", "failed", "blocked"}
)
# 중계기 자신의 명부 역할. 정체 상신의 발신 자리로 쓴다.
RELAY_ROLE = "relay"


def now_stamp() -> str:
    """mechanics.md 가 고정한 형식. 자정 전환 뒤 시·분이 빠지는 사고가 있었다."""
    return datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S %z")


def orca(args: list[str]) -> dict | None:
    """번들 CLI 한 번. 실패는 None 이며 절대 지어내지 않는다."""
    try:
        proc = subprocess.run(
            [ORCA_BUNDLE, *args, "--json"], capture_output=True, text=True, timeout=30
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def resolve_role(project: str, board: str, run: str, role: str) -> dict | None:
    """role 이 먼저다. handle 은 행동 직전에 다시 찾는 임시 라우팅 값이다.

    응답 필드는 camelCase 다 (`currentHandle`, `lastSeenHandle`) — 2026-08-10 실측.
    명부가 `model` 과 `agentState` 도 들고 있으므로 화면에서 긁지 않는다.
    """
    data = orca(
        [
            "roster", "resolve",
            "--project", project, "--board", board,
            "--role", role, "--run", run,
        ]
    )
    if not data or not data.get("ok"):
        return None
    member = data.get("result", {}).get("member") or {}
    if not member.get("live"):
        return None
    handle = member.get("currentHandle") or member.get("lastSeenHandle")
    if not handle:
        return None
    return {
        "handle": handle,
        "model": member.get("model"),
        "agent_state": member.get("agentState"),
    }


def ask_judge(snippet: str) -> tuple[str, str]:
    """애매한 화면 조각 하나를 DeepSeek 에게 묻는다. (판정, 원문) 을 돌려준다.

    판정은 '진행' / '정체' / '모름' 중 하나다. 못 부르면 '모름'이며,
    모름은 조용으로 취급하지 않는다 — 호출 실패가 정상으로 보이면 감시가 없는 것만 못하다.
    """
    prompt = (
        "너는 터미널 화면 조각을 보고 에이전트가 실제로 일하고 있는지 판정한다.\n"
        "'진행' 또는 '정체' 또는 '모름' 중 한 단어로만 답하라. 설명하지 마라.\n\n"
        "진행 = 새로운 도구 실행이나 새 출력이 실제로 생기고 있다.\n"
        "정체 = 보이는 것이 다시 그려진 화면, 인용된 프롬프트, 옛 스크롤백, "
        "스피너 잔상뿐이고 새 작업이 없다.\n"
        "모름 = 조각만으로는 가를 수 없다.\n\n"
        f"--- 화면 조각 ---\n{snippet}\n--- 끝 ---"
    )
    try:
        proc = subprocess.run(
            ["command-code", "-p", prompt, "--model", JUDGE_MODEL, "--yolo", "--no-session"],
            capture_output=True, text=True, timeout=90,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        return "모름", f"judge_call_failed:{type(exc).__name__}"
    text = (proc.stdout or "").strip()
    for verdict in ("진행", "정체"):
        if verdict in text:
            return verdict, text[-80:]
    return "모름", text[-80:] or f"exit={proc.returncode}"


def load_state(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, ensure_ascii=False, indent=2))


def append_log(path: Path, line: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as handle:
        handle.write(line.rstrip() + "\n")


def parse_context_pct(text: str) -> int | None:
    import re

    matches = re.findall(r"Context (\d+)% used", text or "")
    return int(matches[-1]) if matches else None


def count_tool_lines(lines: list[str]) -> int:
    return sum(1 for line in lines if any(marker in line for marker in TOOL_MARKERS))


def is_resident_card(task: dict) -> bool:
    """판이 끝날 때까지 dispatched 로 남는 상주 역할 카드인가.

    이름 경계까지 본다. 그냥 앞머리 일치로 두면 `RELAY-MONITORING — 일반 기능 카드`
    같은 남남인 제목까지 상주로 빠져 일반 작업이 0장으로 보인다. 그러면 진짜 정체가
    통째로 유휴로 덮인다 — 2026-08-12 독립 검수가 이 경계로 상신 0통을 재현했다.
    그래서 제목이 이름과 정확히 같거나, 이름 뒤에 하이픈이 붙은 경우만 상주로 본다.

    제목으로만 가른다. assignee handle 은 순찰마다 바뀔 수 있는 임시 라우팅 값이라
    상주 여부의 근거로 쓰면 handle 이 재발급되는 순간 판정이 뒤집힌다.
    """
    title = str(task.get("task_title") or "").strip()
    return any(
        title == name or title.startswith(f"{name}-") for name in RESIDENT_CARD_TITLES
    )


def count_dispatched(run: str) -> tuple[int, int] | None:
    """(일반 작업 카드 수, 상주 카드 수). 못 읽으면 None 이며 0 으로 뭉개지 않는다.

    상주 카드는 "일하는 사람"이 아니라 "살아 있는 장치"다. 둘을 한 숫자로 합치면
    일반 작업이 0장인 조용한 감독이 정체로 보인다 — 2026-08-12 오탐이 정확히 그것이다.
    그래서 합치지 않고 둘 다 돌려주고, 일기에도 둘 다 적는다.

    응답 모양은 믿지 않고 껍질부터 하나씩 확인한다 — result 객체, tasks 목록, 각 행이
    객체인지, status 가 번들이 실제로 쓰는 값인지. 하나라도 어긋나면 그 자리에서 None
    이다. 검사 없이 `task.get(...)` 을 부르면 `tasks=[None, 정상카드]` 하나에 순찰
    주기가 예외로 끊기고, 모르는 status 는 조용히 (0, 0) 이 되어 거짓 유휴가 된다.
    둘 다 정체를 숨기는 쪽으로 틀리므로 모름으로 닫는 것이 유일하게 안전한 기본값이다.
    """
    data = orca(["orchestration", "task-list", "--run", run])
    if not data or not data.get("ok"):
        return None
    result = data.get("result")
    if not isinstance(result, dict):
        return None
    tasks = result.get("tasks")
    # 성공 응답은 항상 tasks 배열을 준다(빈 판이면 빈 배열). 목록이 아니면 모르는 모양이다.
    if not isinstance(tasks, list):
        return None
    active = 0
    resident = 0
    for task in tasks:
        if not isinstance(task, dict):
            return None
        status = task.get("status")
        # 자료형부터 본다. `in frozenset` 은 해시할 수 없는 값에서 비교 자체가
        # TypeError 라, status=[] · {} · ["dispatched"] 하나에 순찰 주기가 통째로
        # 예외로 끊긴다 — 정체 횟수도 안 쌓이고 상신도 0통이 된다 (2026-08-12 재검수 실측).
        # 모르는 자료형은 모르는 값과 똑같이 '모름'으로 닫는다.
        if not isinstance(status, str) or status not in KNOWN_TASK_STATUSES:
            return None
        if status != "dispatched":
            continue
        if is_resident_card(task):
            resident += 1
        else:
            active += 1
    return active, resident


def error_code(result: dict | None) -> str:
    """실패 원문에서 코드만 뽑는다. 원인 없는 '실패'는 다음 사람이 못 고친다."""
    if result is None:
        return "cli_no_output"
    return str((result.get("error") or {}).get("code") or "unknown")


def recover_proxy(tail_text: str) -> str | None:
    """프록시 계열 오류면 중계기가 직접 살린다. 감독에게는 보고하지 않는다(복구 성공 시)."""
    if not any(err in tail_text for err in PROXY_ERRORS):
        return None
    try:
        proc = subprocess.run(["ocx", "ensure"], capture_output=True, text=True, timeout=120)
    except (subprocess.TimeoutExpired, OSError):
        return "proxy_recover_failed"
    return "proxy_recovered" if proc.returncode == 0 else "proxy_recover_failed"


def patrol(project: str, board: str, run: str, log_path: Path, state_path: Path) -> None:
    state = load_state(state_path)
    stamp = now_stamp()

    member = resolve_role(project, board, run, "project-supervisor")
    if member is None:
        append_log(
            log_path,
            f"{stamp} | patrol | ROSTER_FAIL_CLOSED role=project-supervisor "
            f"— 감독 자리를 못 찾았다(0개가 아니라 모름). 추측하지 않고 닫는다 | 조치 없음",
        )
        return
    handle = member["handle"]

    last_cursor = int(state.get("cursor", 0))
    read = orca(["terminal", "read", "--terminal", handle, "--cursor", str(last_cursor), "--limit", "60"])
    if read is None:
        append_log(log_path, f"{stamp} | patrol | READ_FAIL {handle} — 화면을 못 읽었다(모름) | 조치 없음")
        return

    term = read.get("result", {}).get("terminal") or {}
    tail = term.get("tail") or []
    lines = [str(item) for item in tail]
    tail_text = "\n".join(lines)
    latest = int(term.get("latestCursor", last_cursor))
    returned = int(term.get("returnedLineCount", len(lines)))
    ctx = parse_context_pct(tail_text)
    prev_ctx = state.get("context_pct")
    tool_lines = count_tool_lines(lines)

    # --- 판정: 셸이 확실한 것만 확정하고, 나머지는 전부 모델에게 넘긴다 ---
    judge_note = ""
    if returned == 0 and latest == last_cursor:
        verdict = "정체"          # 아무것도 안 변했다 — 확실하다
        basis = "새 출력 0, 커서 불변"
    elif prev_ctx is not None and ctx is not None and ctx > prev_ctx:
        verdict = "진행"          # Context 가 늘었다 — 확실하다
        basis = f"Context {prev_ctx}%→{ctx}%"
    else:
        # 새 줄이 보이는데 진짜인지 다시 그려진 것인지 셸은 모른다.
        # kyle 결정(2026-08-10): 애매하면 무조건 모델을 부른다.
        verdict, judge_note = ask_judge(tail_text[-3000:])
        basis = f"애매(새 줄 {returned}, 도구 줄 {tool_lines}) → 모델 판정"

    # --- 유휴와 정체를 가른다 (2026-08-10 오탐 실측) ---
    # 도는 일반 작업이 0개면 감독이 조용한 것은 정상이다. 옛 luna 중계기는 이 구분이 없어
    # 정당한 유휴를 "no_progress_cycles=16" 으로 쌓아 거짓 정체를 신고했다.
    # 2026-08-12: 상주 카드(RELAY-MONITOR)를 같이 세어 같은 오탐이 다시 났다.
    # 못 읽었으면(None) 0 으로 뭉개지 않고 정체 판정을 그대로 둔다 — fail-closed.
    counts = count_dispatched(run)
    active, resident = counts if counts is not None else (None, 0)
    if verdict == "정체" and active == 0:
        verdict, basis = (
            "유휴",
            f"{basis} — 다만 도는 일반 카드 0개(상주 {resident}장 제외)라 조용한 것이 정상이다",
        )

    # --- 연속 무진행 세기 ---
    cycles = int(state.get("no_progress_cycles", 0))
    if verdict in ("진행", "유휴"):
        cycles = 0
        state.pop("stall_escalation_id", None)
    else:
        # '모름'도 진행으로 세지 않는다 — 모름을 정상으로 뭉개지 않기 위해서다.
        cycles += 1

    # --- 프록시 자가 복구 ---
    proxy_action = recover_proxy(tail_text)

    # --- 정체 보고: 같은 정체에 대해 딱 한 번 ---
    #
    # 발신 자리(--from)를 반드시 붙인다. 이 순찰기는 launchd 가 띄운 PPID=1 데몬이라
    # ORCA_TERMINAL_HANDLE 도, 붙어 있는 터미널도 없다. --from 없이 부르면 번들 CLI 가
    # 발신자를 정하지 못해 `no_active_sender_terminal` 로 거절하고, 우편은 한 통도
    # 나가지 않는다 — 2026-08-12 정체 상신 8회 연속 실패의 원인이 정확히 이것이다.
    # 발신 자리는 중계기 자신의 명부 역할에서 행동 직전에 다시 찾는다.
    action = proxy_action or "없음"
    if cycles >= STALL_CYCLES and not state.get("stall_escalation_id"):
        relay = resolve_role(project, board, run, RELAY_ROLE)
        if relay is None:
            # 발신 자리를 모르면 보내지 않는다. 성공으로 적지 않으므로 다음 순찰에 다시 온다.
            action = f"escalation 보류 — 발신 자리(role={RELAY_ROLE})를 못 찾았다. 다음 순찰에 재시도"
        else:
            sent = orca(
                [
                    "orchestration", "send",
                    "--from", relay["handle"],
                    "--to", f"run:{run}",
                    "--type", "escalation",
                    "--subject", f"supervisor_stall:{handle}",
                    "--body",
                    f"감독 화면에 연속 {cycles}회 진행 증거가 없다. 판정 근거: {basis}. "
                    f"모델 판정: {verdict}{(' / ' + judge_note) if judge_note else ''}. "
                    f"cursor={latest}, Context={ctx}%. 이 정체에 대해 한 번만 보고한다.",
                ]
            )
            if sent and sent.get("ok"):
                msg_id = (sent.get("result", {}).get("message") or {}).get("id", "sent")
                state["stall_escalation_id"] = msg_id
                action = f"escalation 1회({msg_id})"
            else:
                # 실패는 성공으로 적지 않는다. stall_escalation_id 를 남기지 않으므로
                # 같은 정체가 이어지면 다음 순찰이 그대로 다시 시도한다.
                action = f"escalation 발송 실패({error_code(sent)}) — 다음 순찰에 재시도"

    state.update(
        {
            "cursor": latest,
            "context_pct": ctx if ctx is not None else prev_ctx,
            "no_progress_cycles": cycles,
            "last_patrol": stamp,
        }
    )
    save_state(state_path, state)

    append_log(
        log_path,
        f"{stamp} | patrol | supervisor {handle} ({member.get('model')}, "
        f"agentState={member.get('agent_state')}) cursor {last_cursor}→{latest}, "
        f"새 출력 {returned}줄, 도구 실행 줄 {tool_lines}, "
        f"Context {prev_ctx}%→{ctx if ctx is not None else '변화없음'}, "
        f"도는 일반 카드 {active if active is not None else '모름'}(상주 {resident}장 제외) "
        f"| 판정={verdict} ({basis}){(' | 모델원문=' + judge_note) if judge_note else ''} "
        f"| 연속무진행={cycles} | 조치={action}",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="헤드리스 중계기 순찰")
    parser.add_argument("--project", required=True)
    parser.add_argument("--board", required=True)
    parser.add_argument("--run", required=True)
    parser.add_argument("--repo-root", required=True, help="일기를 남길 레포 본체 경로")
    parser.add_argument("--interval", type=int, default=300)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    root = Path(args.repo_root)
    log_path = root / ".orca" / "relay-logs" / f"{args.board}.relay-log.md"
    state_path = root / ".orca" / "relay-logs" / f"{args.board}.relay-state.json"

    if args.once:
        patrol(args.project, args.board, args.run, log_path, state_path)
        return 0

    append_log(log_path, f"{now_stamp()} | start | 헤드리스 순찰 시작 (주기 {args.interval}초) | 조치 없음")
    while True:
        try:
            patrol(args.project, args.board, args.run, log_path, state_path)
        except Exception as exc:  # 순찰 한 번이 죽어도 감시가 멈추면 안 된다
            append_log(log_path, f"{now_stamp()} | patrol | PATROL_ERROR {type(exc).__name__}: {exc} | 조치 없음")
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
