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
import re
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
# worker dispatch 가 "정체(stale)"로 보는 한계 (초). coordinator.ts:75
# HUNG_THRESHOLD_MS = 10*60*1000 의 사본이다 — "10분 = 심박 5분 × 2, 심박 1회 누락이
# 정체로 보이는 최소 시간" (2026-08-12 소스 주석 실측). 감독 화면 주기가 아니라 worker
# dispatch 의 권위 심박 시각으로 잰다 — 감독이 worker_done 을 기다리며 조용히 자는
# 것을 정체로 오판한 사건(msg_b07782b049cf)이 바로 화면 주기 판정이었다.
DISPATCH_STALE_SEC = 10 * 60
# 판 수명 동안 계속 dispatched 로 남는 상주 역할 카드의 이름.
# 이 카드들은 "지금 누가 일하고 있다"가 아니라 "이 장치가 살아 있다"를 뜻하므로
# 일반 작업 수에 세지 않는다 (2026-08-12 실측: 일반 0장인데 RELAY-MONITOR 한 장
# 때문에 도는 카드=1 로 세어 조용한 감독을 연속 정체 5회로 오판했다).
RESIDENT_CARD_TITLES = ("RELAY-MONITOR",)
# 카드 제목 앞에 붙는 판 식별자. 표준 계약이다 — SKILL.md:154 "spec은 항상
# `[판:<판이름>]` 접두사로 시작", mechanics.md 판 식별자 절. 장부가 런타임 전역 공유라
# 다중 세션 지휘에서 카드를 가르려고 붙인다. 상주 카드도 같은 계약을 따르므로 상주
# 판정 전에 이 접두사 **한 개**만 떼고 본다 (2026-08-12 실측: 살아 있는 카드는
# `RELAY-MONITOR-mailbox-relay-1`(접두사 없음)이지만 같은 판의 일반 카드는 전부
# `[판:mailbox-relay-1] …` 형태라, 표준대로 지은 새 판의 상주 카드
# `[판:quota-collection-1] RELAY-MONITOR-quota-collection-1` 은 상주로 안 빠지고
# 일반 카드로 세어졌다 — 그 카드의 dispatch 는 판 내내 심박 없는 dispatched 라
# 그대로 stale 로 분류돼, 조용한 감독을 오판하고 자기 감시 카드로 거짓 정체 상신까지
# 나간다). 두 개 이상 겹친 접두사는 떼지 않는다 — 넓히면 일반 카드를 숨긴다.
BOARD_PREFIX_RE = re.compile(r"^\[판:[^\]]*\]\s*")
# 번들이 tasks.status 에 실제로 허용하는 값 전부. 추정이 아니라 실측이다 —
# 운영 DB `orchestration.db` 의 tasks 테이블 CHECK 제약과 같다 (2026-08-12 확인):
#   CHECK(status IN ('pending','ready','dispatched','completed','failed','blocked'))
# 이 목록 밖 값이 오면 응답을 이해하지 못한 것이므로 0 이 아니라 '모름'으로 닫는다.
KNOWN_TASK_STATUSES = frozenset(
    {"pending", "ready", "dispatched", "completed", "failed", "blocked"}
)
# 번들이 dispatch_contexts.status 에 실제로 허용하는 값 (dispatch-show 의 result.dispatch.status).
# 운영 DB DispatchStatus union 과 같다 (2026-08-12 소스 src/main/runtime/orchestration/types.ts:21 실측).
# 이 목록 밖 값이 오면 응답을 이해하지 못한 것이므로 '모름'으로 닫는다.
KNOWN_DISPATCH_STATUSES = frozenset(
    {"pending", "dispatched", "completed", "failed", "circuit_broken"}
)
# worker_done 대기가 끝난 종료 상태 (중요 3: done 은 이 3개만). pending 은 여기 없다 —
# pending 을 완료로 꾸미면 거짓 정상 대기가 된다 (검수 중요 4).
DONE_DISPATCH_STATUSES = frozenset({"completed", "failed", "circuit_broken"})
# 권위 식별자 형식 (companion record_worker_done_ledger / 소스 getDispatchContext 실측).
# 위조 ID·불일치 보고를 여기서 거른다 (목표 5).
DISPATCH_ID_RE = re.compile(r"^ctx_[0-9a-f]{8,}$")
TASK_ID_RE = re.compile(r"^task_[0-9a-f]{8,}$")
# 중계기 자신의 명부 역할. 정체 상신의 발신 자리로 쓴다.
RELAY_ROLE = "relay"


def now_stamp() -> str:
    """mechanics.md 가 고정한 형식. 자정 전환 뒤 시·분이 빠지는 사고가 있었다."""
    return datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S %z")


def orca(args: list[str]) -> dict | None:
    """번들 CLI 한 번. 파싱된 응답을 그대로 돌려주며 절대 지어내지 않는다.

    성공(`ok=true`)뿐 아니라 **구조화 실패 응답(`ok=false` + `error.code`)도 그대로 준다.**
    번들은 실패를 항상 종료코드 1 + stdout JSON 으로 낸다 (2026-08-12 실측:
    `orchestration send --to run:<없는 run>` → exit 1, stdout `{"ok":false,
    "error":{"code":"run_not_found"}}`). 예전에는 여기서 `returncode != 0` 을 먼저 보고
    None 으로 닫아 그 error.code 를 통째로 버렸다 — 그래서 정체 상신이 무슨 이유로
    거절됐는지(run_not_found·no_active_sender_terminal·dispatch_run_mismatch…)를
    영수증에 적을 방법이 없었고, error_code() 는 늘 'cli_no_output' 만 냈다.

    None 은 "응답 자체가 없다"만 뜻한다: 호출 불가·시한 초과·빈 stdout·JSON 아님·
    JSON 이지만 객체가 아님. 성공 판정은 부르는 쪽이 `data.get("ok")` 로 직접 한다 —
    이 함수가 돌려준다는 사실만으로 성공이 아니다.
    """
    try:
        proc = subprocess.run(
            [ORCA_BUNDLE, *args, "--json"], capture_output=True, text=True, timeout=30
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    if not proc.stdout.strip():
        return None
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


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
    """화면에서 Context 사용률을 긁는다 — 호스트 명부에 의존하지 않는 폴백까지.

    Orca 명부는 codex TUI 만 채워주고 omo 는 'Pi' 로 오인식해 model·context 가
    비어 온다 (2026-08-12 실측). 화면 텍스트는 어느 호스트·러너든 주는 공통 표면이라
    여기서 긁는 것이 탈호스트 방향이다 (TODO15 어댑터 경계 감사와 같은 결).
    """
    matches = re.findall(r"Context (\d+)% used", text or "")
    if matches:
        return int(matches[-1])
    # omo 상태줄: "167K/272K (61.4%)" — 사용률 퍼센트를 그대로 쓴다.
    omo = re.findall(r"\d+(?:\.\d+)?K/\d+(?:\.\d+)?K \((\d+(?:\.\d+)?)%\)", text or "")
    if omo:
        return int(round(float(omo[-1])))
    return None


def parse_model_from_screen(text: str) -> str | None:
    """omo 상태줄 '(openai-codex) gpt-5.6-sol:medium' 형식에서 모델을 긁는 폴백."""
    matches = re.findall(r"\(([\w-]+)\)\s+([\w.\-/]+:(?:low|medium|high|xhigh|max))", text or "")
    return matches[-1][1] if matches else None


def _now_utc() -> datetime:
    """현재 UTC 시각. 시험이 고정 시계로 바꿀 수 있게 한 곳에서 뽑는다."""
    return datetime.now(timezone.utc)


def parse_iso(value: object) -> datetime | None:
    """ISO-8601 시각 문자열을 aware datetime 으로. 못 파싱하면 None (모름).

    끝이 'Z' 여도 받는다(Python 3.14 fromisoformat 은 'Z' 를 받지만 구 실행환경도
    안전하게 'Z' → '+00:00' 로 바꾼다). 시간대가 없으면 UTC 로 본다.
    """
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def count_tool_lines(lines: list[str]) -> int:
    return sum(1 for line in lines if any(marker in line for marker in TOOL_MARKERS))


def is_resident_card(task: dict) -> bool:
    """판이 끝날 때까지 dispatched 로 남는 상주 역할 카드인가.

    이름 경계까지 본다. 그냥 앞머리 일치로 두면 `RELAY-MONITORING — 일반 기능 카드`
    같은 남남인 제목까지 상주로 빠져 일반 작업이 0장으로 보인다. 그러면 진짜 정체가
    통째로 유휴로 덮인다 — 2026-08-12 독립 검수가 이 경계로 상신 0통을 재현했다.
    그래서 제목이 이름과 정확히 같거나, 이름 뒤에 하이픈이 붙은 경우만 상주로 본다.

    비교 전에 표준 판 식별자 접두사(`[판:<판이름>] `) 한 개만 뗀다 (BOARD_PREFIX_RE).
    접두사는 카드 제목 계약이지 이름의 일부가 아닌데, 떼지 않으면 표준대로 지은
    `[판:quota-collection-1] RELAY-MONITOR-quota-collection-1` 이 상주에서 빠지지 않고
    일반 작업 1장 + stale dispatch 로 잡혀 거짓 정체를 만든다 (2026-08-12 재현).
    접두사를 뗀 뒤에도 경계 규칙은 그대로라 `[판:x] RELAY-MONITORING — 일반 카드` 는
    여전히 일반 작업이다.

    제목으로만 가른다. assignee handle 은 순찰마다 바뀔 수 있는 임시 라우팅 값이라
    상주 여부의 근거로 쓰면 handle 이 재발급되는 순간 판정이 뒤집힌다.
    """
    title = str(task.get("task_title") or "").strip()
    title = BOARD_PREFIX_RE.sub("", title, count=1).strip()
    return any(
        title == name or title.startswith(f"{name}-") for name in RESIDENT_CARD_TITLES
    )


def _parse_task_list(run: str) -> dict | None:
    """task-list 를 파싱해 활성 카드 목록과 상주 카드 수를 돌려준다.

    못 읽거나 모양이 어긋나면 None 이며 0 으로 뭉개지 않는다. count_dispatched 와
    dispatch 건강도 판정이 같은 파싱을 공유한다 — 둘이 따로 읽으면 한쪽만 고쳐져 어긋난다.

    상주 카드(RELAY-MONITOR)는 "일하는 사람"이 아니라 "살아 있는 장치"다. 활성
    카드 수에서 빼고 따로 센다 — 같은 숫자로 합치면 일반 작업이 0장인 조용한 감독이
    정체로 보인다 (2026-08-12 오탐).

    권위 교차검증 (F-RELAY-STRUCTURED-STALL-2 중요 1·3): task-list 의 result.runId 가
    요청 run 과 정확히 같을 때만 쓴다. 다르면 외국 판의 카드를 현재 판의 정체로 보고하는
    권위 결합 오류가 난다 (검수 중요 3 실측). 활성 카드마다 taskId·dispatch_id·
    assignee_handle 을 보존해 dispatch-show 와 교차검증에 쓴다. 공개 CLI 계약(2026-08-13
    소스 src/cli/handlers/orchestration.ts:827-840, rpc/methods/orchestration.ts:1474-1484
    실측): dispatched 카드는 assignee_handle·dispatch_id 를 함께 준다. 둘 중 하나라도
    비어있거나 문자열이 아니면 그 응답을 이해하지 못한 것이므로 None 으로 닫는다.

    응답 모양은 믿지 않고 껍질부터 하나씩 확인한다. 검사 없이 task.get(...) 을 부르면
    tasks=[None, 정상카드] 하나에 순찰 주기가 예외로 끊기고, 모르는 status 는 조용히
    (0, 0) 이 되어 거짓 유휴가 된다. 둘 다 정체를 숨기는 쪽으로 틀리므로 모름으로 닫는
    것이 유일하게 안전한 기본값이다.
    """
    data = orca(["orchestration", "task-list", "--run", run])
    if not data or not data.get("ok"):
        return None
    result = data.get("result")
    if not isinstance(result, dict):
        return None
    # result.runId 는 번들이 해석한 실제 run 이다. 요청 run 과 다르면 외국 판이다.
    resp_run = result.get("runId")
    if not isinstance(resp_run, str) or resp_run != run:
        return None
    tasks = result.get("tasks")
    # 성공 응답은 항상 tasks 배열을 준다(빈 판이면 빈 배열). 목록이 아니면 모르는 모양이다.
    if not isinstance(tasks, list):
        return None
    active: list[dict] = []
    resident = 0
    for task in tasks:
        if not isinstance(task, dict):
            return None
        status = task.get("status")
        # 자료형부터 본다. `in frozenset` 은 해시할 수 없는 값에서 비교 자체가
        # TypeError 라, status=[] · {} · ["dispatched"] 하나에 순찰 주기가 통째로
        # 예외로 끊긴다 — 정체 횟수도 안 쌓이고 상신도 0통이 된다 (재검수 실측).
        # 모르는 자료형은 모르는 값과 똑같이 '모름'으로 닫는다.
        if not isinstance(status, str) or status not in KNOWN_TASK_STATUSES:
            return None
        if status != "dispatched":
            continue
        if is_resident_card(task):
            resident += 1
            continue
        tid = task.get("id")
        dispatch_id = task.get("dispatch_id")
        assignee = task.get("assignee_handle")
        # 활성(dispatched) 카드는 권위 3값이 모두 비어있지 않은 문자열이어야 한다.
        # 하나라도 누락·빈값·비문자열이면 응답을 이해하지 못한 것이므로 None 으로 닫는다.
        # tid 는 권위 형식(TASK_ID_RE)까지 본다 (F-RELAY-STRUCTURED-STALL-3): 위조 ID 가
        # task-list 와 dispatch-show 양쪽에 같으면 둘이 일치한다는 이유만으로 보고가 나가던
        # 구멍을 닫는다. dispatch_id 는 classify_dispatch 의 DISPATCH_ID_RE 가 잡는다.
        if not (isinstance(tid, str) and tid and TASK_ID_RE.fullmatch(tid)):
            return None
        if not (isinstance(dispatch_id, str) and dispatch_id):
            return None
        if not (isinstance(assignee, str) and assignee):
            return None
        active.append({"task_id": tid, "dispatch_id": dispatch_id, "assignee_handle": assignee})
    return {"active": active, "resident": resident}


def count_dispatched(run: str) -> tuple[int, int] | None:
    """(일반 작업 카드 수, 상주 카드 수). 못 읽으면 None 이며 0 으로 뭉개지 않는다.

    _parse_task_list 의 얇은 포장이다 — 같은 파싱을 dispatch 건강도 판정과 공유한다.
    """
    parsed = _parse_task_list(run)
    if parsed is None:
        return None
    return len(parsed["active"]), parsed["resident"]


def classify_dispatch(
    task_id: str,
    now_dt: datetime,
    *,
    expected_dispatch_id: str | None = None,
    expected_assignee: str | None = None,
    expected_run: str | None = None,
) -> dict | None:
    """한 활성 카드의 dispatch 를 dispatch-show 로 healthy/stale/done 으로 가른다.

    시그니처는 (task_id, now_dt) positional + expected_* keyword-only 다. expected_*
    를 주지 않은 직접 호출(경계 단위 시험)은 교차검증 없이 형식·task_id·stale 경계만
    검사한다. patrol() 은 _parse_task_list 의 card 와 요청 run 을 expected_* 로 넘겨
    4필드 교차검증을 켠다 (F-RELAY-STRUCTURED-STALL-2 중요 1·2·3).

    권위 교차검증 (expected_* 제공 시): dispatch-show 의 id/task_id/run_id/assignee_handle
    을 expected_dispatch_id/expected_run/task_id/expected_assignee 와 모두 비교한다.
    하나라도 누락·빈값·불일치면 None (모름) 이며 보고 0 이다. 외국 dispatch 를 현재 판의
    정체로 보고하거나 서로 다른 작업자를 결합하는 권위 오결합을 여기서 막는다.

    상태 분류 (중요 3·4): dispatched 만 healthy/stale. done 은 completed/failed/
    circuit_broken 만. pending 은 모름으로 닫는다.

    assignee_pane_key 는 비교하지 않는다. 공개 task-list 계약(orchestration.ts:827-840)은
    assignee_handle 은 주지만 pane 은 주지 않으므로 교차검증할 기댓값이 없다. handle 은
    run 안에서 작업자 터미널을 유일하게 식별하므로 권위 비교에 충분하다.

    stale 경계 (중요 5): coordinator.ts getStaleDispatches 의 권위 SQL
    `julianday(dispatched_at) < threshold` 를 따른다 — 정확히 10분은 stale 가 아니고
    10분 초과만 stale 다. 따라서 `>= threshold` 로 비교한다 (X1 변형 `>` 거부).

    반환: {"state": "healthy"|"stale"|"done", "dispatch_id": str, "status": str}.
    못 읽거나 교차검증이 어긋나면 None (모름) — 정상·정체 어느 쪽으로도 추측하지 않는다.
    """
    data = orca(["orchestration", "dispatch-show", "--task", task_id])
    if not data or not data.get("ok"):
        return None
    result = data.get("result")
    if not isinstance(result, dict):
        return None
    dispatch = result.get("dispatch")
    # dispatch 가 null 이면 발령 기록이 없다 — 정상 추측 금지, 모름.
    if not isinstance(dispatch, dict):
        return None
    did = dispatch.get("id")
    dtid = dispatch.get("task_id")
    drun = dispatch.get("run_id")
    dassn = dispatch.get("assignee_handle")
    # 형식·task_id 일치는 항상 검사 (직접 호출·patrol 공통).
    # F-RELAY-STRUCTURED-STALL-3: TASK_ID_RE 로 권위 형식을 본다. dtid 와 task_id 가
    # 서로 같기만 하고 형식이 위조면 자기 일치 보고가 나가므로 둘 각각 fullmatch 한다.
    if not (isinstance(did, str) and did and DISPATCH_ID_RE.fullmatch(did)):
        return None
    if not (isinstance(dtid, str) and dtid and TASK_ID_RE.fullmatch(dtid)):
        return None
    if not (isinstance(task_id, str) and task_id and TASK_ID_RE.fullmatch(task_id)):
        return None
    if dtid != task_id:
        return None
    # 권위 교차검증: patrol 이 expected_* 를 넘긴 경우에만 켠다 (4필드 모두).
    if expected_dispatch_id is not None:
        if did != expected_dispatch_id:
            return None
    if expected_run is not None:
        if not (isinstance(drun, str) and drun and drun == expected_run):
            return None
    if expected_assignee is not None:
        if not (isinstance(dassn, str) and dassn and dassn == expected_assignee):
            return None
    status = dispatch.get("status")
    if not isinstance(status, str) or status not in KNOWN_DISPATCH_STATUSES:
        return None
    # 상태 분류: dispatched 만 건강/정체. done 은 종료 3상태만. pending 은 모름.
    if status not in ("dispatched",):
        if status in DONE_DISPATCH_STATUSES:
            return {"state": "done", "dispatch_id": did, "status": status}
        # pending 등 알 수 없는 상태 — 정상으로 꾸미지 않고 모름으로 닫는다.
        return None
    # 정체 판정: coordinator getStaleDispatches 와 같은 세 조건.
    raw_dispatched = dispatch.get("dispatched_at")
    raw_heartbeat = dispatch.get("last_heartbeat_at")
    # dispatched_at 이 null/불파싱이면 권위 판정을 못 한다 — 모름.
    dispatched_at = parse_iso(raw_dispatched)
    if dispatched_at is None:
        return None
    # heartbeat: null 은 "심박 없음"(정상 상태). 비-문자열/불파싱 문자열은 malformed → 모름.
    if raw_heartbeat is None:
        heartbeat_at = None
    elif isinstance(raw_heartbeat, str):
        heartbeat_at = parse_iso(raw_heartbeat)
        if heartbeat_at is None:
            return None
    else:
        return None
    threshold = now_dt.timestamp() - DISPATCH_STALE_SEC
    # 정확히 임계(10분)는 stale 가 아니다 — `>=` 비교 (X1 변형 `>` 거부, 중요 5).
    if dispatched_at.timestamp() >= threshold:
        # 첫 심박 유예: 발령 직후엔 심박이 아직 없어도 정체가 아니다.
        return {"state": "healthy", "dispatch_id": did, "status": status}
    if heartbeat_at is not None and heartbeat_at.timestamp() >= threshold:
        return {"state": "healthy", "dispatch_id": did, "status": status}
    return {"state": "stale", "dispatch_id": did, "status": status}
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
    # orca() 는 구조화 실패 응답(ok=false)도 그대로 준다. 성공 판정을 여기서 직접 해야
    # 한다 — 안 하면 실패 응답의 빈 result 가 "새 출력 0 · 커서 불변"으로 읽혀 못 읽은
    # 화면이 확정 정체로 둔갑한다. 못 읽음은 정체가 아니라 모름이다.
    if read is None or not read.get("ok"):
        append_log(
            log_path,
            f"{stamp} | patrol | READ_FAIL {handle}({error_code(read)}) — 화면을 못 읽었다(모름) | 조치 없음",
        )
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

    # --- 활성 카드와 dispatch 건강도 (목표 1·3·4, 사건 msg_b07782b049cf) ---
    #
    # 감독 화면 무출력만으로 정체로 보면 오탐이다 — 감독은 worker_done 을 기다리며
    # 조용히 자는 것이 정상이다 (mechanics.md "감독의 대기 방식: 발령 뒤에는 턴을 끝내고
    # 잔다"). 그래서 활성 카드가 있다면 각 dispatch 의 상태·심박을 직접 보고, 어느
    # worker 가 진짜 멈췄는지를 권위 식별자(taskId+dispatchId)로 가린다. 활성 카드가
    # 없으면(상주만 또는 빈 판) 조용한 감독은 유휴다.
    parsed = _parse_task_list(run)
    if parsed is None:
        active_cards: list[dict] | None = None
        resident = 0
    else:
        active_cards = parsed["active"]
        resident = parsed["resident"]

    now_dt = _now_utc()
    healthy = stale = done = unknown = 0
    # 교차검증을 통과한 stale 만 (card, dispatch_id) 로 모은다. card 에 권위 4값이 모두
    # 들어 있어 보고 결합이 외국 dispatch 와 섞이지 않는다.
    stale_targets: list[tuple[dict, str]] = []
    if active_cards is not None:
        for card in active_cards:
            cls = classify_dispatch(
                card["task_id"], now_dt,
                expected_dispatch_id=card["dispatch_id"],
                expected_assignee=card["assignee_handle"],
                expected_run=run,
            )
            if cls is None:
                unknown += 1
            elif cls["state"] == "healthy":
                healthy += 1
            elif cls["state"] == "done":
                done += 1
            else:  # stale
                stale += 1
                stale_targets.append((card, cls["dispatch_id"]))

    # --- 감독 화면 정체를 dispatch 건강도로 다시 가른다 ---
    #
    # 활성 worker 가 건강하거나 이미 끝났으면 감독이 조용한 것은 worker_done 대기(정상)다.
    # dispatch 가 stale 이면 그 worker 가 진짜 멈춘 것이므로 정체로 둔다. dispatch 상태를
    # 못 읽었으면(모름) 정상·정체 어느 쪽으로도 추측하지 않는다 (목표 4·6: 거짓 정상 0).
    if verdict == "정체":
        if active_cards is None:
            verdict, basis = "모름", f"{basis} — 카드 목록을 못 읽어 정상·정체 추측 불가"
        elif len(active_cards) == 0:
            verdict, basis = (
                "유휴",
                f"{basis} — 도는 일반 카드 0개(상주 {resident}장 제외)라 조용함이 정상이다",
            )
        elif stale > 0:
            verdict, basis = "정체", f"{basis} — worker dispatch 정체(stale {stale})"
        elif healthy > 0 or done > 0:
            verdict, basis = (
                "정상 대기",
                f"{basis} — 활성 worker 심박 정상(건강 {healthy}·완료 {done})이라 "
                f"감독 조용함은 worker_done 대기다",
            )
        else:
            verdict, basis = "모름", f"{basis} — dispatch 상태를 못 읽어 추측 불가(모름 {unknown})"

    # --- 감독 화면 연속 무진행(진단용 카운터) ---
    cycles = int(state.get("no_progress_cycles", 0))
    if verdict in ("진행", "유휴", "정상 대기"):
        cycles = 0
    else:
        # '모름'도 진행으로 세지 않는다 — 모름을 정상으로 뭉개지 않기 위해서다.
        cycles += 1

    # --- 프록시 자가 복구 ---
    proxy_action = recover_proxy(tail_text)

    # --- 정체 보고: 권위 taskId+dispatchId 를 가진 stale dispatch 에 대해 각각 1회 ---
    #
    # 감독 화면 주기가 아니라 worker dispatch 의 권위 심박 시각이 보고의 방아쇠다.
    # 그래야 건강한 worker 를 기다리는 조용한 감독이 정체로 오판되지 않는다 (목표 1).
    # 보고는 --task-id/--dispatch-id 구조화 필드에 실어 식별자 없는 MALFORMED_LIFECYCLE_REPORT
    # 격리를 막는다 (목표 2). 같은 stale dispatch 에 대해 딱 한 번이고, dispatch 가
    # stale 를 벗어나면 기록을 지워 다음 정체 때 다시 보고한다 (목표 5).
    #
    # 발신 자리(--from)를 반드시 붙인다 — 이 순찰기는 launchd PPID=1 데몬이라 붙은
    # 터미널이 없어 --from 없으면 no_active_sender_terminal 로 거절된다 (2026-08-12 실측).
    escalations = dict(state.get("dispatch_escalations") or {})
    stale_dispatch_ids = {did for _, did in stale_targets}
    action = proxy_action or "없음"
    sent_notes: list[str] = []
    if stale_targets:
        relay = resolve_role(project, board, run, RELAY_ROLE)
        for card, dispatch_id in stale_targets:
            task_id = card["task_id"]
            if dispatch_id in escalations:
                continue  # 이 stale dispatch 는 이미 보고했다.
            if relay is None:
                # 발신 자리를 모르면 보내지 않는다. 성공으로 적지 않으므로 다음 순찰에 다시 온다.
                sent_notes.append(
                    f"escalation 보류 task={task_id} dispatch={dispatch_id} — 발신 자리(role={RELAY_ROLE})를 못 찾았다. 다음 순찰에 재시도"
                )
                continue
            sent = orca(
                [
                    "orchestration", "send",
                    "--from", relay["handle"],
                    "--to", f"run:{run}",
                    "--type", "escalation",
                    "--task-id", task_id,
                    "--dispatch-id", dispatch_id,
                    "--subject", f"worker_dispatch_stale:{dispatch_id}",
                    "--body",
                    f"활성 worker dispatch 가 정체다. taskId={task_id} dispatchId={dispatch_id}. "
                    f"감독 화면 판정: {basis}. 모델 판정: {verdict}"
                    f"{(' / ' + judge_note) if judge_note else ''}. "
                    f"cursor={latest}, Context={ctx}%. 같은 dispatch 에 대해 한 번만 보고한다.",
                ]
            )
            if sent and sent.get("ok"):
                msg_id = (sent.get("result", {}).get("message") or {}).get("id", "sent")
                escalations[dispatch_id] = msg_id
                sent_notes.append(f"escalation 1회({msg_id}) task={task_id} dispatch={dispatch_id}")
            else:
                # 실패는 성공으로 적지 않는다 — dispatch_id 를 기록에 남기지 않으므로
                # 같은 정체가 이어지면 다음 순찰이 그대로 다시 시도한다.
                sent_notes.append(
                    f"escalation 발송 실패({error_code(sent)}) task={task_id} dispatch={dispatch_id} — 다음 순찰에 재시도"
                )
    # 목표 5: stale 를 벗어난 dispatch(건강·완료·모름·사라짐)의 보고 기록을 지운다.
    for did in list(escalations):
        if did not in stale_dispatch_ids:
            del escalations[did]
    state["dispatch_escalations"] = escalations
    if sent_notes:
        action = sent_notes[-1] if len(sent_notes) == 1 else f"{len(sent_notes)}건: " + "; ".join(sent_notes)

    active_count = len(active_cards) if active_cards is not None else None
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
        f"{stamp} | patrol | supervisor {handle} "
        f"({member.get('model') or parse_model_from_screen(tail_text) or '모름'}, "
        f"agentState={member.get('agent_state')}) cursor {last_cursor}→{latest}, "
        f"새 출력 {returned}줄, 도구 실행 줄 {tool_lines}, "
        f"Context {prev_ctx}%→{ctx if ctx is not None else '변화없음'}, "
        f"도는 일반 카드 {active_count if active_count is not None else '모름'}(상주 {resident}장 제외) "
        f"dispatch 건강·정체·완료·모름={healthy}·{stale}·{done}·{unknown} "
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
