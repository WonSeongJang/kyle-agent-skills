"""헤드리스 중계기 순찰 회귀 — dispatch 건강도 기반 정체 보고 계약.

Why (2026-08-12 F-RELAY-STRUCTURED-STALL 실측): 활성 카드(task_34f7e248c920)의
dispatch(ctx_0665dde17589)가 정상 심박을 내고 있었는데, 감독이 worker_done 을 기다리며
화면이 조용하다는 것만 보고 순찰이 supervisor_stall 로 오판했다(msg_b07782b049cf). 게다가
그 escalation 에 taskId/dispatchId 구조화 필드가 없어 수명주기 소비자가
MALFORMED_LIFECYCLE_REPORT 로 격리했다.

여기서 잠그는 계약은 coordinator.ts getStaleDispatches 의 권위 정의를 따른 것이다.
  1. 건강한 활성 worker(정상 심박) + 조용한 감독 = 정상 대기. escalation 0 (목표 1).
  2. 진짜 정체는 worker dispatch 의 권위 심박 시각으로 잰다(10분 = 심박 5분 × 2).
     보고는 --task-id/--dispatch-id 구조화 필드에 실어 MALFORMED 격리를 막는다(목표 2).
  3. 활성이 여러 개면 각 dispatch 를 따로 보고, stale 만 정확히 한 번(목표 3·4).
  4. task-list/dispatch-show 가 망가지면 정상·정체 추측 없이 '모름'으로 닫는다(목표 4·6).
  5. dispatch 가 stale 를 벗어나면 보고 기록이 지워져 재정체 때 다시 보고한다(목표 5).
  6. taskId/dispatchId 없음·불일치·위조·completed dispatch 는 상태 적용용 보고에서 거른다(목표 5).

실제 우편은 한 통도 나가지 않는다. 번들 CLI 자리는 통째로 가짜(fixture)로 바꾼다.
"""

from __future__ import annotations

import importlib.util
import sys
from datetime import datetime, timezone
from pathlib import Path
from types import ModuleType

import pytest

SCRIPT = Path(__file__).parents[1] / "relay-patrol.py"

PROJECT = "kyle-agent-skills"
BOARD = "test-board"
RUN = "run_testrelay0001"
SUPERVISOR_HANDLE = "term_supervisor_0001"
RELAY_HANDLE = "term_relay_0001"

# dispatch 심박 신선도 판정의 고정 기준 시각. with_fake 가 _now_utc 를 이 값으로 고정한다.
NOW = datetime(2026, 8, 11, 19, 45, 0, tzinfo=timezone.utc)
# NOW 기준 시각선:
#   FRESH ≈ 1분 전(건강), STALE_AGE = 15분 전(정체).
#   EXACT_10MIN = 정확히 10분 전(== 임계, stale 아님 — 권위 SQL `< threshold` 경계).
#   OVER_10MIN = 10분 1초 전(> 임계, stale).
#   UNDER_10MIN = 9분 59초 전(< 임계, healthy).
FRESH = "2026-08-11T19:44:06.000Z"
STALE_AGE = "2026-08-11T19:30:00.000Z"
EXACT_10MIN = "2026-08-11T19:35:00.000Z"
OVER_10MIN = "2026-08-11T19:34:59.000Z"
UNDER_10MIN = "2026-08-11T19:35:01.000Z"
# task-list / dispatch-show 가 서로 일치해야 할 권위 기본값.
DEFAULT_DISPATCH_ID = "ctx_0665dde17589"
DEFAULT_ASSIGNEE = "term_worker_0001"


def load_patrol() -> ModuleType:
    spec = importlib.util.spec_from_file_location("relay_patrol_under_test", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def with_fake(
    fake: object,
    monkeypatch: pytest.MonkeyPatch,
    judge: tuple[str, str] | None = None,
    now: datetime | None = None,
) -> ModuleType:
    """순찰기를 새로 읽고 바깥으로 나가는 자리를 모두 가짜로 막는다.

    orca() 는 번들 CLI, ask_judge() 는 DeepSeek 호출이다. 둘 다 막으므로 실제 우편도
    실제 모델 호출도 일어나지 않는다. now 를 주면 dispatch 심박 신선도의 기준 시각을
    고정한다(기본 NOW). judge 를 주지 않은 시험이 애매 갈래로 가면 그 자리에서 떨어진다.
    """
    module = load_patrol()
    monkeypatch.setattr(module, "orca", fake)
    monkeypatch.setattr(module, "_now_utc", lambda: now if now is not None else NOW)

    def judge_stub(snippet: str) -> tuple[str, str]:
        if judge is None:
            raise AssertionError("이 시험은 모델 판정 갈래로 가면 안 된다(셸 확정 갈래여야 한다)")
        return judge

    monkeypatch.setattr(module, "ask_judge", judge_stub)
    return module


_UNSET = object()
_NO_DISPATCH = object()
_DISPATCH_FAIL = object()


# title → 권위 16진수 task_id 매핑. F-RELAY-STRUCTURED-STALL-3: 시험 fixture 의
# taskId 를 비권위(task_F-REAL-WORK)에서 권위 형식(task_<소문자16진수 8+>)으로 바꾼다.
# 결정적 매핑이라 같은 title 은 항상 같은 ID 를 주어 card/disp 교차검증이 맞는다.
TITLE_TASK_IDS = {
    "F-REAL-WORK": "task_a1b2c3d4e5f60001",
    "F-HEALTHY": "task_a1b2c3d4e5f60002",
    "F-STALE": "task_a1b2c3d4e5f60003",
    "RELAY-MONITOR-test-board": "task_a1b2c3d4e5f60004",
    "RELAY-MONITORING — ordinary feature card": "task_a1b2c3d4e5f60005",
    "F-REAL": "task_a1b2c3d4e5f60006",
    "F-OLD-DONE": "task_a1b2c3d4e5f60007",
    "R-SOMETHING": "task_a1b2c3d4e5f60008",
    "F-DONE": "task_a1b2c3d4e5f60009",
    "F-REAL-CASE": "task_a1b2c3d4e5f6000a",
}


def _task_id_for(title: str | None) -> str:
    """title 의 권위 task_id. 모르는 title 은 결정적 해시 기반 16진수 ID 를 만든다."""
    if title in TITLE_TASK_IDS:
        return TITLE_TASK_IDS[title]
    # 결정적 fallback: title 해시를 소문자 16진수 8자리로.
    import hashlib
    h = hashlib.sha256(str(title).encode()).hexdigest()[:8]
    return f"task_fb{h}"


def card(
    title: str | None,
    status: object = "dispatched",
    *,
    dispatch_id: str | None = DEFAULT_DISPATCH_ID,
    assignee: str | None = DEFAULT_ASSIGNEE,
    task_id: str | None = None,
) -> dict:
    """시험용 카드 한 장. id 는 권위 형식 task_<소문자16진수 8+> (title 매핑).

    title 은 사람이 읽는 라벨(task_title)이고 task_id 는 권위 식별자다.
    F-RELAY-STRUCTURED-STALL-3: 비권위 ID(task_F-REAL-WORK)를 쓰면 TASK_ID_RE 검증이
    시험 자체를 깨뜨리므로 권위 16진수 ID 로 바꾼다. task_id= 로 직접 줄 수도 있다
    (위조 ID 공격 시험용).
    """
    tid_val = task_id if task_id is not None else _task_id_for(title)
    row: dict = {"id": tid_val}
    if title is not None:
        row["task_title"] = title
    if status is not None:
        row["status"] = status
        if status == "dispatched":
            if dispatch_id is not None:
                row["dispatch_id"] = dispatch_id
            if assignee is not None:
                row["assignee_handle"] = assignee
    return row


def tid(title: str = "F-REAL-WORK") -> str:
    """title 의 권위 task_id (card() 와 같은 매핑)."""
    return _task_id_for(title)


def disp(
    task_id: str,
    dispatch_id: str = DEFAULT_DISPATCH_ID,
    *,
    status: str = "dispatched",
    heartbeat: str | None = FRESH,
    dispatched: str = FRESH,
    run_id: str = RUN,
    assignee: str = DEFAULT_ASSIGNEE,
) -> dict:
    """시험용 dispatch 행 한 개. dispatch-show 의 result.dispatch 모양을 따른다."""
    return {
        "id": dispatch_id,
        "task_id": task_id,
        "run_id": run_id,
        "status": status,
        "assignee_handle": assignee,
        "assignee_pane_key": "pane_worker_0001",
        "dispatched_at": dispatched,
        "last_heartbeat_at": heartbeat,
    }


def stale_disp(task_id: str, **kw: object) -> dict:
    kw.setdefault("heartbeat", STALE_AGE)
    kw.setdefault("dispatched", STALE_AGE)
    return disp(task_id, **kw)  # type: ignore[arg-type]


def done_disp(task_id: str, **kw: object) -> dict:
    kw.setdefault("status", "completed")
    return disp(task_id, **kw)  # type: ignore[arg-type]


def _dispatch_show_response(fixture: object) -> dict | None:
    """dispatch-show 가짜 응답. fixture 모양에 따라 정상·무기록·실패·망가짐을 낸다."""
    if fixture is _DISPATCH_FAIL:
        return None
    if fixture is _NO_DISPATCH:
        return {"ok": True, "result": {"dispatch": None}}
    if isinstance(fixture, tuple) and fixture and fixture[0] == "__raw__":
        return fixture[1]  # 전체 orca 응답을 그대로 준다(망가진 result 모양 재현).
    return {"ok": True, "result": {"dispatch": fixture}}


class FakeOrca:
    """번들 CLI 자리를 대신한다. 실제로는 아무것도 보내지 않고 argv 만 모은다."""

    def __init__(
        self,
        tasks: object,
        *,
        relay_live: bool = True,
        send_results: list[dict] | None = None,
        task_list_result: object = _UNSET,
        dispatches: dict | None = None,
    ) -> None:
        # tasks 는 목록이 아닐 수도 있다. 망가진 응답도 그대로 흘려보내야 fail-closed 를 잰다.
        self.tasks = tasks
        self.task_list_result = task_list_result
        self.relay_live = relay_live
        self.dispatches = dispatches or {}
        # 순서대로 하나씩 꺼내 쓴다. 다 떨어지면 마지막 것을 계속 쓴다.
        self.send_results = send_results or [
            {"ok": True, "result": {"message": {"id": "msg_ok_0001"}}}
        ]
        self.calls: list[list[str]] = []
        # 새 출력이 몇 칸 늘었는지. 0이면 "커서 불변" — 셸이 모델 없이 확정하는 정체 조건이다.
        self.advance = 0

    @property
    def sends(self) -> list[list[str]]:
        return [args for args in self.calls if args[:2] == ["orchestration", "send"]]

    def __call__(self, args: list[str]) -> dict | None:
        self.calls.append(list(args))
        if args[:2] == ["roster", "resolve"]:
            role = args[args.index("--role") + 1]
            if role == "project-supervisor":
                return self._member(SUPERVISOR_HANDLE, "gpt-5.6-sol", "done")
            if role == "relay":
                if not self.relay_live:
                    return {"ok": True, "result": {"member": {"live": False}}}
                return self._member(RELAY_HANDLE, None, None)
            return {"ok": False, "error": {"code": "role_roster_not_found"}}
        if args[:2] == ["terminal", "read"]:
            requested = int(args[args.index("--cursor") + 1])
            return {
                "ok": True,
                "result": {
                    "terminal": {
                        "tail": [],
                        "latestCursor": requested + self.advance,
                        "returnedLineCount": 0,
                    }
                },
            }
        if args[:2] == ["orchestration", "task-list"]:
            if self.task_list_result is not _UNSET:
                return {"ok": True, "result": self.task_list_result}
            # 공개 CLI 계약: result.runId 는 번들이 해석한 실제 run 이다 (기본 RUN).
            return {"ok": True, "result": {"runId": RUN, "tasks": self.tasks}}
        if args[:2] == ["orchestration", "dispatch-show"]:
            task = args[args.index("--task") + 1]
            return _dispatch_show_response(self.dispatches.get(task, _NO_DISPATCH))
        if args[:2] == ["orchestration", "send"]:
            return (
                self.send_results.pop(0) if len(self.send_results) > 1 else self.send_results[0]
            )
        raise AssertionError(f"가짜 CLI 가 모르는 명령: {args}")

    @staticmethod
    def _member(handle: str, model: str | None, agent_state: str | None) -> dict:
        return {
            "ok": True,
            "result": {
                "member": {
                    "live": True,
                    "currentHandle": handle,
                    "model": model,
                    "agentState": agent_state,
                }
            },
        }


@pytest.fixture
def paths(tmp_path: Path) -> tuple[Path, Path]:
    return tmp_path / "board.relay-log.md", tmp_path / "board.relay-state.json"


def run_patrol(module: ModuleType, paths: tuple[Path, Path], times: int = 1) -> list[str]:
    log_path, state_path = paths
    for _ in range(times):
        module.patrol(PROJECT, BOARD, RUN, log_path, state_path)
    return log_path.read_text().splitlines()


def flag(args: list[str], name: str) -> str:
    return args[args.index(name) + 1]



# --- 1. 상주 카드 제외 / count_dispatched 단위 계약 --------------------------
def test_resident_card_is_not_counted_as_active_work(monkeypatch: pytest.MonkeyPatch) -> None:
    module = with_fake(
        FakeOrca(
            [
                card("RELAY-MONITOR-test-board"),
                card("F-OLD-DONE", status="completed"),
            ]
        ),
        monkeypatch,
    )
    assert module.count_dispatched(RUN) == (0, 1)



def test_mixed_cards_count_only_ordinary_work(monkeypatch: pytest.MonkeyPatch) -> None:
    module = with_fake(
        FakeOrca(
            [
                card("RELAY-MONITOR-test-board"),
                card("F-RELAY-RESIDENT-COUNT — 상주 카드 오계수"),
                card("R-SOMETHING", status="ready"),
                card("F-DONE", status="completed"),
            ]
        ),
        monkeypatch,
    )
    assert module.count_dispatched(RUN) == (1, 1)



def test_task_list_failure_stays_unknown_not_zero(monkeypatch: pytest.MonkeyPatch) -> None:
    module = with_fake(lambda args: None, monkeypatch)
    assert module.count_dispatched(RUN) is None



def test_quiet_supervisor_with_only_resident_card_reports_idle(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = FakeOrca([card("RELAY-MONITOR-test-board")])
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=3)

    assert len(lines) == 3
    for line in lines:
        assert "판정=유휴" in line
        assert "도는 일반 카드 0(상주 1장 제외)" in line
        assert "연속무진행=0" in line
    # 유휴는 상신 대상이 아니다. 세 번 돌아도 우편은 한 통도 없다.
    assert fake.sends == []





# --- 2. dispatch 건강도 기반 정체 보고 (목표 1·2·3) ---------------------------
#
# Why (2026-08-12 F-RELAY-STRUCTURED-STALL): 감독 화면 무출력만으로 정체로 보면,
# worker_done 을 정상적으로 기다리는 조용한 감독이 정체로 오판된다. 보고의 방아쇠는
# 감독 화면 주기가 아니라 worker dispatch 의 권위 심박 시각이다.


def test_healthy_worker_quiet_supervisor_is_normal_wait_no_escalation(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 사건 msg_b07782b049cf 재현: 건강한 worker(정상 심박) + 조용한 감독.
    t = tid("F-REAL-WORK")
    fake = FakeOrca([card("F-REAL-WORK")], dispatches={t: disp(t)})
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=3)

    assert len(lines) == 3
    for line in lines:
        assert "판정=정상 대기" in line
        assert "건강 1" in line
        assert "연속무진행=0" in line
    # 정상 대기는 보고 대상이 아니다. 세 번 돌아도 우편은 한 통도 없다.
    assert fake.sends == []


def test_worker_done_wait_heartbeat_refresh_is_normal_wait(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # worker_done 대기 중 심박이 계속 갱신되면 계속 정상 대기다 (필수 회귀 2).
    t = tid("F-REAL-WORK")
    fake = FakeOrca([card("F-REAL-WORK")], dispatches={t: disp(t, heartbeat=FRESH)})
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=4)

    assert all("판정=정상 대기" in line for line in lines)
    assert fake.sends == []


def test_stale_dispatch_escalates_once_with_accurate_ids(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 진짜 정체(stale 심박)는 권위 taskId+dispatchId 를 가진 보고 정확히 1회 (필수 회귀 3).
    t = tid("F-REAL-WORK")
    fake = FakeOrca([card("F-REAL-WORK")], dispatches={t: stale_disp(t)})
    module = with_fake(fake, monkeypatch)

    first = run_patrol(module, paths, times=1)
    assert "판정=정체" in first[0]
    assert "worker dispatch 정체(stale 1)" in first[0]
    assert len(fake.sends) == 1
    sent = fake.sends[0]
    assert flag(sent, "--task-id") == t
    assert flag(sent, "--dispatch-id") == "ctx_0665dde17589"
    assert flag(sent, "--type") == "escalation"

    # 같은 stale dispatch 가 이어져도 두 번째 우편은 없다.
    lines = run_patrol(module, paths, times=2)
    assert len(fake.sends) == 1
    assert "escalation" not in lines[1].split("| 조치=")[1]
    assert "escalation" not in lines[2].split("| 조치=")[1]


def test_escalation_carries_full_bundle_cli_contract(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca([card("F-REAL-WORK", dispatch_id="ctx_aabbccdd0001")],
                        dispatches={t: stale_disp(t, dispatch_id="ctx_aabbccdd0001")})
    module = with_fake(fake, monkeypatch)

    run_patrol(module, paths, times=1)

    assert len(fake.sends) == 1
    sent = fake.sends[0]
    # --from 없이 부르면 데몬 환경에서 no_active_sender_terminal 로 거절된다.
    assert "--from" in sent
    assert flag(sent, "--from") == RELAY_HANDLE
    assert flag(sent, "--to") == f"run:{RUN}"
    assert flag(sent, "--type") == "escalation"
    assert flag(sent, "--task-id") == t
    assert flag(sent, "--dispatch-id") == "ctx_aabbccdd0001"
    assert flag(sent, "--subject") == "worker_dispatch_stale:ctx_aabbccdd0001"
    # 발신 자리는 캐시하지 않고 보내기 직전에 명부에서 다시 찾는다.
    assert ["roster", "resolve"] == fake.calls[-2][:2]
    assert flag(fake.calls[-2], "--role") == "relay"


def test_two_active_one_healthy_one_stale_reports_only_stale(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 활성 2개 중 하나 건강/하나 stale 이면 stale 대상만 정확히 보고 (필수 회귀 4).
    th = tid("F-HEALTHY")
    ts = tid("F-STALE")
    fake = FakeOrca(
        [card("F-HEALTHY", dispatch_id="ctx_aabbccdd0003"),
         card("F-STALE", dispatch_id="ctx_aabbccdd0002")],
        dispatches={th: disp(th, dispatch_id="ctx_aabbccdd0003"),
                    ts: stale_disp(ts, dispatch_id="ctx_aabbccdd0002")},
    )
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=1)
    assert "건강·정체·완료·모름=1·1·0·0" in lines[0]
    assert len(fake.sends) == 1
    assert flag(fake.sends[0], "--task-id") == ts
    assert flag(fake.sends[0], "--dispatch-id") == "ctx_aabbccdd0002"

    # 두 번째 순찰에도 stale 는 그 한 번만, 건강은 끝내 보고하지 않는다.
    run_patrol(module, paths, times=1)
    assert len(fake.sends) == 1


def test_grace_period_dispatched_no_heartbeat_is_healthy(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 발령 직후(첫 심박 유예)엔 심박이 아직 없어도 정체가 아니다 — coordinator getStaleDispatches
    # 의 dispatched_at < 임계 조건이 거기서부터 시작하기 때문이다.
    t = tid("F-REAL-WORK")
    fake = FakeOrca([card("F-REAL-WORK")], dispatches={t: disp(t, heartbeat=None, dispatched=FRESH)})
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=1)
    assert "판정=정상 대기" in lines[0]
    assert fake.sends == []


def test_old_dispatched_but_fresh_heartbeat_is_healthy(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 발령은 오래됐지만 심박이 최신이면 건강이다 — coordinator getStaleDispatches 의
    # (last_heartbeat_at >= 임계) 조건이 정체를 거부한다. 심박 무시 변형을 잡는 대조군.
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: disp(t, heartbeat=FRESH, dispatched=STALE_AGE)},
    )
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=1)
    assert "판정=정상 대기" in lines[0]
    assert fake.sends == []


# --- 3. 발송 실패는 성공으로 기록되지 않는다 (필수 회귀 8) ---------------------


def test_send_failure_is_not_recorded_and_retries_next_patrol(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: stale_disp(t)},
        send_results=[
            {"ok": False, "error": {"code": "no_active_sender_terminal"}},
            {"ok": True, "result": {"message": {"id": "msg_ok_0003"}}},
        ],
    )
    module = with_fake(fake, monkeypatch)
    _, state_path = paths

    lines = run_patrol(module, paths, times=1)
    assert "escalation 발송 실패(no_active_sender_terminal)" in lines[0]
    assert "다음 순찰에 재시도" in lines[0]
    # 실패를 성공으로 적지 않았다 — dispatch_escalations 에 dispatchId 가 없다.
    assert "ctx_0665dde17589" not in state_path.read_text()

    lines = run_patrol(module, paths, times=1)
    assert len(fake.sends) == 2
    assert "escalation 1회(msg_ok_0003)" in lines[1]
    assert "ctx_0665dde17589" in state_path.read_text()

    # 성공한 뒤에는 같은 정체에 대해 더 보내지 않는다.
    run_patrol(module, paths, times=1)
    assert len(fake.sends) == 2


def test_cli_no_output_failure_names_its_reason(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    class Silent(FakeOrca):
        def __call__(self, args: list[str]) -> dict | None:
            result = super().__call__(args)
            return None if args[:2] == ["orchestration", "send"] else result

    t = tid("F-REAL-WORK")
    fake = Silent([card("F-REAL-WORK")], dispatches={t: stale_disp(t)})
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=1)
    assert "escalation 발송 실패(cli_no_output)" in lines[0]
    assert len(fake.sends) == 1


def test_missing_relay_sender_holds_instead_of_sending(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca([card("F-REAL-WORK")], dispatches={t: stale_disp(t)}, relay_live=False)
    module = with_fake(fake, monkeypatch)
    _, state_path = paths

    lines = run_patrol(module, paths, times=1)
    assert fake.sends == []
    assert "escalation 보류" in lines[0]
    assert "발신 자리(role=relay)를 못 찾았다" in lines[0]
    assert "ctx_0665dde17589" not in state_path.read_text()


# --- 4. 제목 경계: 상주 이름과 남남인 제목을 가른다 (patrol 수준) ---------------
#
# 유사 제목(RELAY-MONITORING …)은 상주가 아니라 일반 작업이다. 그 카드의 dispatch 가
# stale 면 정체 보고가 나가야 한다 — 상주로 잘못 빠지면 유휴로 덮인다.


def test_similar_title_is_ordinary_and_its_stale_dispatch_escalates(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("RELAY-MONITORING — ordinary feature card")
    fake = FakeOrca(
        [card("RELAY-MONITORING — ordinary feature card")],
        dispatches={t: stale_disp(t)},
    )
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=1)
    assert "도는 일반 카드 1(상주 0장 제외)" in lines[0]
    assert "판정=정체" in lines[0]
    assert len(fake.sends) == 1


# --- 5. 망가진 응답은 정체/정상 추측 없이 '모름'으로 닫는다 (목표 4·6) ---------
#
# Why: task-list/dispatch-show 가 망가지면 정상도 정체도 알 수 없다. 예전에는 망가진
# task-list 를 정체로 추측해 식별자 없는 보고를 보냈다. 이제 모름으로 닫고 보고 0,
# 거짓 정상 0, 예외 0 이다 (필수 회귀 6).


def test_unknown_task_status_closes_as_unknown_no_escalation(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = FakeOrca([card("F-REAL-WORK", status="mystery")])
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=3)

    assert all("판정=모름" in line for line in lines)
    assert all("도는 일반 카드 모름" in line for line in lines)
    # 모름은 보고도, 거짓 정상도 아니다.
    assert fake.sends == []
    assert not any("판정=유휴" in line or "판정=정상 대기" in line for line in lines)


def test_broken_task_list_row_closes_as_unknown_no_escalation(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = FakeOrca([None, card("F-REAL-WORK")])
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=2)

    assert len(lines) == 2
    assert all("판정=모름" in line for line in lines)
    assert all("도는 일반 카드 모름" in line for line in lines)
    assert fake.sends == []


@pytest.mark.parametrize("task_list_result", ["ok", {"count": 0}, "dispatched"])
def test_malformed_task_list_result_closes_as_unknown(
    task_list_result: object,
    paths: tuple[Path, Path],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fake = FakeOrca([], task_list_result=task_list_result)
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=2)

    assert all("판정=모름" in line for line in lines)
    assert fake.sends == []


class _TaskListFail(FakeOrca):
    def __call__(self, args: list[str]) -> dict | None:
        if args[:2] == ["orchestration", "task-list"]:
            return None
        return super().__call__(args)


def test_task_list_cli_failure_closes_as_unknown(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # roster/terminal 은 정상이고 task-list 만 None(모름)이면 판정도 모름이다.
    fake = _TaskListFail([card("F-REAL-WORK")])
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=2)
    assert all("판정=모름" in line for line in lines)
    assert fake.sends == []


# --- 6. status 자료형까지 fail-closed (patrol 수준) ----------------------------


@pytest.mark.parametrize("status", [[], {}, ["dispatched"]])
def test_unhashable_status_closes_as_unknown_no_crash(
    status: object,
    paths: tuple[Path, Path],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """해시 불가 status 가 와도 순찰은 돌고, 모름으로 닫힌다. 보고는 0, 예외는 0."""
    fake = FakeOrca([card("F-REAL-WORK", status=status)])
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=3)

    assert len(lines) == 3
    assert all("판정=모름" in line for line in lines)
    assert all("도는 일반 카드 모름" in line for line in lines)
    assert fake.sends == []


# --- 7. 식별자 거부·상태 변경 초기화·비상태 진단 (목표 3·5) ---------------------
#
# Why (필수 회귀 5·목표 3): taskId/dispatchId 없음·불일치·위조·completed dispatch 는
# 상태 적용용 보고에서 거른다. dispatch 가 stale 를 벗어나면 보고 기록이 지워져
# 재정체 때 다시 보고한다. 어떤 카드에도 귀속 못 시킨 supervisor-only 상태는
# lifecycle 보고가 아니라 모름 진단으로 분리한다.


@pytest.mark.parametrize(
    ("label", "fixture"),
    [
        ("task_id 없음", {"id": "ctx_0665dde17589", "task_id": None, "status": "dispatched",
                          "dispatched_at": STALE_AGE, "last_heartbeat_at": None}),
        ("dispatch_id 없음", {"id": None, "task_id": tid(), "status": "dispatched",
                              "dispatched_at": STALE_AGE, "last_heartbeat_at": None}),
        ("task_id 불일치", disp("task_SOMEONE_ELSE", heartbeat=None, dispatched=STALE_AGE)),
        ("위조 dispatch_id", {"id": "ctx_forged", "task_id": tid(), "status": "dispatched",
                               "dispatched_at": STALE_AGE, "last_heartbeat_at": None}),
        ("completed dispatch", done_disp(tid())),
        ("pending dispatch", {"id": "ctx_0665dde17589", "task_id": tid(), "status": "pending",
                               "dispatched_at": STALE_AGE, "last_heartbeat_at": None}),
    ],
)
def test_unauthoritative_or_terminal_dispatch_never_escalates(
    label: str,
    fixture: dict,
    paths: tuple[Path, Path],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca([card("F-REAL-WORK")], dispatches={t: fixture})
    module = with_fake(fake, monkeypatch)

    run_patrol(module, paths, times=3)
    # 권위 식별자가 없거나 종료된 dispatch 는 stale 가 될 수 없어 보고도 안 나간다.
    assert fake.sends == [], label


def test_dispatch_leaving_stale_resets_so_restall_reports_again(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # stale → 보고 1회 → healthy 로 바뀌면 기록 초기화 → 다시 stale → 다시 보고 (목표 5).
    t = tid("F-REAL-WORK")
    fixture = stale_disp(t)
    fake = FakeOrca([card("F-REAL-WORK")], dispatches={t: fixture})
    module = with_fake(fake, monkeypatch)

    run_patrol(module, paths, times=1)
    assert len(fake.sends) == 1

    # worker 가 다시 심박을 내면 정상 대기로 돌아가고, 보고 기록이 지워진다.
    fixture["last_heartbeat_at"] = FRESH
    fixture["dispatched_at"] = FRESH
    lines = run_patrol(module, paths, times=1)
    assert "판정=정상 대기" in lines[1]
    assert len(fake.sends) == 1  # 새 보고 없음

    # 다시 stale 로 떨어지면 기록이 비어 있어 다시 한 번 보고한다.
    fixture["last_heartbeat_at"] = STALE_AGE
    fixture["dispatched_at"] = STALE_AGE
    fake.send_results = [{"ok": True, "result": {"message": {"id": "msg_restall_0002"}}}]
    lines = run_patrol(module, paths, times=1)
    assert "escalation 1회(msg_restall_0002)" in lines[2]
    assert len(fake.sends) == 2


def test_dispatch_disappearing_from_task_list_resets_tracking(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 카드가 task-list 에서 사라져(예: worker_done 종결)도 보고 기록이 지워진다.
    t = tid("F-REAL-WORK")
    fake = FakeOrca([card("F-REAL-WORK")], dispatches={t: stale_disp(t)})
    module = with_fake(fake, monkeypatch)

    run_patrol(module, paths, times=1)
    assert len(fake.sends) == 1

    fake.tasks = []  # 카드 종결
    run_patrol(module, paths, times=1)
    _, state_path = paths
    assert "dispatch_escalations" not in state_path.read_text() or \
        "ctx_0665dde17589" not in state_path.read_text()


def test_supervisor_only_state_with_all_unknown_is_not_lifecycle_escalation(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 활성 카드는 있으나 dispatch-show 를 전부 못 읽으면(모름) 어떤 카드에도 귀속 못 시킨다.
    # 이 supervisor-only 상태는 lifecycle 보고가 아니라 모름 진단이다 (목표 3).
    t = tid("F-REAL-WORK")
    fake = FakeOrca([card("F-REAL-WORK")], dispatches={t: _DISPATCH_FAIL})
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=3)
    assert all("판정=모름" in line for line in lines)
    assert all("모름 1" in line for line in lines)
    assert fake.sends == []


def test_malformed_dispatch_show_result_closes_as_unknown(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: ("__raw__", {"ok": True, "result": "not-an-object"})},
    )
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=2)
    assert all("판정=모름" in line for line in lines)
    assert fake.sends == []


def test_known_dispatch_statuses_match_the_shipped_bundle() -> None:
    """dispatch_contexts.status 가 허용하는 값 5개 (소스 DispatchStatus union 실측).

    src/main/runtime/orchestration/types.ts:21
        DispatchStatus = 'pending'|'dispatched'|'completed'|'failed'|'circuit_broken'
    이 집합이 조용히 바뀌면 모르는 상태를 정상/정체로 뭉갤 수 있으므로 여기서 못박는다.
    """
    module = load_patrol()
    assert module.KNOWN_DISPATCH_STATUSES == {
        "pending",
        "dispatched",
        "completed",
        "failed",
        "circuit_broken",
    }


def test_dispatch_stale_sec_matches_coordinator_hung_threshold() -> None:
    """coordinator.ts:75 HUNG_THRESHOLD_MS = 10*60*1000 (10분 = 심박 5분 × 2)."""
    module = load_patrol()
    assert module.DISPATCH_STALE_SEC == 10 * 60


# --- 8. 권위 교차검증 (F-RELAY-STRUCTURED-STALL-2 중요 1·2·3) ------------------
#
# Why: task-list 와 dispatch-show 의 dispatch/run/assignee 를 교차검증하지 않으면 외국
# dispatch 를 현재 판의 정체로 보고하거나 서로 다른 작업자를 결합하는 권위 오결합이 난다.
# 하나라도 누락·빈값·불일치면 모름으로 닫고 보고 0 이다. 검수 독립 공격 9개 전부 여기 잠긴다.


def test_task_list_dispatch_id_mismatch_fails_closed(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # task-list dispatch_id=ctx_b, dispatch-show id=ctx_a → 모름, 보고 0 (중요 1).
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK", dispatch_id="ctx_bbbbbbb0002")],
        dispatches={t: stale_disp(t, dispatch_id=DEFAULT_DISPATCH_ID)},
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=모름" in lines[0]
    assert fake.sends == []


def test_assignee_mismatch_fails_closed(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK", assignee=DEFAULT_ASSIGNEE)],
        dispatches={t: stale_disp(t, assignee="term_worker_OTHER")},
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=모름" in lines[0]
    assert fake.sends == []


def test_dispatch_assignee_missing_fails_closed(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: stale_disp(t, assignee=None)},
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=모름" in lines[0]
    assert fake.sends == []


def test_task_list_assignee_missing_fails_closed(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK", assignee=None)],
        dispatches={t: stale_disp(t)},
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=모름" in lines[0]
    assert fake.sends == []


def test_task_list_dispatch_id_missing_fails_closed(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK", dispatch_id=None)],
        dispatches={t: stale_disp(t)},
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=모름" in lines[0]
    assert fake.sends == []


def test_dispatch_run_mismatch_fails_closed(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: stale_disp(t, run_id="run_FOREIGN0001")},
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=모름" in lines[0]
    assert fake.sends == []


@pytest.mark.parametrize("run_id", [None, ""])
def test_dispatch_run_missing_or_empty_fails_closed(
    run_id: object,
    paths: tuple[Path, Path],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: stale_disp(t, run_id=run_id)},  # type: ignore[arg-type]
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=모름" in lines[0]
    assert fake.sends == []


def test_task_list_run_id_mismatch_fails_closed(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # task-list result.runId 가 요청 run 과 다르면 외국 판이다 — 모름으로 닫는다 (중요 3).
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: stale_disp(t)},
        task_list_result={"runId": "run_FOREIGN0001", "tasks": [card("F-REAL-WORK")]},
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=모름" in lines[0]
    assert fake.sends == []


def test_task_list_missing_run_id_fails_closed(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: stale_disp(t)},
        task_list_result={"tasks": [card("F-REAL-WORK")]},  # runId 칸 자체가 없다
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=모름" in lines[0]
    assert fake.sends == []


def test_pending_dispatch_is_unknown_not_false_done(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # pending 은 done 이 아니라 모름이다 — 정상 대기로 꾸미면 거짓 정상이 된다 (중요 4).
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: stale_disp(t, status="pending")},
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=모름" in lines[0]
    # pending 은 done 으로 세지 않는다 — 완료 0, 모름 1.
    assert "건강·정체·완료·모름=0·0·0·1" in lines[0]
    assert fake.sends == []


# --- 9. 정확히 10분 경계 (F-RELAY-STRUCTURED-STALL-2 중요 5) -------------------
#
# Why: coordinator getStaleDispatches 의 권위 SQL `julianday(x) < threshold` 는 엄격
# 미만이다. 정확히 10분은 stale 가 아니고 10분 초과만 stale 다. 현재 코드는 `>= threshold`
# 로 올바르다. 변형 X1(`>` 로 바꾸어 정확히 10분을 stale 로 만듦)이 반드시 거부돼야 한다.
# heartbeat=None 으로 두어 X1 이 dispatched_at 갈래를 벗어나면 stale 로 떨어지게 한다.


def test_exact_ten_minute_boundary_is_healthy(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 정확히 10분 전(== 임계)은 stale 가 아니다 — `>= threshold` 가 참이다 (X1 거부용).
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: disp(t, dispatched=EXACT_10MIN, heartbeat=None)},
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=정상 대기" in lines[0]
    assert fake.sends == []


def test_over_ten_minutes_is_stale(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 10분 1초 전(> 임계)은 stale 다.
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: disp(t, dispatched=OVER_10MIN, heartbeat=None)},
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=정체" in lines[0]
    assert len(fake.sends) == 1


def test_under_ten_minutes_is_healthy(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 9분 59초 전(< 임계)은 healthy 다.
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: disp(t, dispatched=UNDER_10MIN, heartbeat=None)},
    )
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=1)
    assert "판정=정상 대기" in lines[0]
    assert fake.sends == []


def test_done_dispatch_statuses_match_definition() -> None:
    """done 은 completed/failed/circuit_broken 만. pending 은 여기 없다 (중요 3)."""
    module = load_patrol()
    assert module.DONE_DISPATCH_STATUSES == {"completed", "failed", "circuit_broken"}
    assert "pending" not in module.DONE_DISPATCH_STATUSES


# --- 단위 계약: _parse_task_list 권위 필수 검증 (X8/X9 변형 거부용) -------------
#
# Why: task-list 의 dispatched 카드가 dispatch_id/assignee 를 잃으면 _parse_task_list
# 자체가 None 이어야 한다. patrol 수준에서는 dispatch-show 교차검증이 같은 누출을
# 막아 X8/X9 변형이 가려지지만, _parse_task_list 단위에서 직접 잠가야 방어 깊이를
# 검증한다 (중요 1·2).


def test_parse_task_list_dispatch_id_missing_is_none(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    module = with_fake(FakeOrca([card("F-REAL-WORK", dispatch_id=None)]), monkeypatch)
    assert module._parse_task_list(RUN) is None


def test_parse_task_list_assignee_missing_is_none(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    module = with_fake(FakeOrca([card("F-REAL-WORK", assignee=None)]), monkeypatch)
    assert module._parse_task_list(RUN) is None


def test_parse_task_list_preserves_authoritative_fields(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # 정상 dispatched 카드는 task_id·dispatch_id·assignee_handle 을 모두 보존한다.
    module = with_fake(
        FakeOrca([card("F-REAL-WORK", dispatch_id="ctx_aabbccdd0007", assignee="term_w7")]),
        monkeypatch,
    )
    parsed = module._parse_task_list(RUN)
    assert parsed == {"active": [{"task_id": tid("F-REAL-WORK"),
                                   "dispatch_id": "ctx_aabbccdd0007",
                                   "assignee_handle": "term_w7"}],
                      "resident": 0}



# --- 10. 위조 taskId 형식 차단 (F-RELAY-STRUCTURED-STALL-3) -------------------
#
# Why: TASK_ID_RE 가 정의만 되고 쓰이지 않아, task-list 와 dispatch-show 가 같은 위조
# taskId 를 주면 둘이 일치한다는 이유만으로 stale 보고가 나갔다. 이제 _parse_task_list
# 와 classify_dispatch 각각이 TASK_ID_RE.fullmatch 로 권위 형식을 검사한다. 위조 ID 는
# 모름으로 닫히고 보고 0·거짓 정상 0·예외 0 이다.


def test_task_id_re_matches_shipped_contract() -> None:
    """권위 taskId 형식: ^task_[0-9a-f]{8,}$ (companion/소스 실측과 같다)."""
    module = load_patrol()
    assert module.TASK_ID_RE.pattern == r"^task_[0-9a-f]{8,}$"


@pytest.mark.parametrize(
    ("task_id", "expected"),
    [
        ("task_a1b2c3d4", True),            # 8자리 소문자 16진수 (최소)
        ("task_a1b2c3d4e5f6", True),        # 12자리
        ("task_a1b2c3d4e5f60001", True),    # 긴 소문자 16진수
        ("task_abcdef0123456789", True),    # 16자리
        ("task_F-REAL-WORK", False),        # 비권위(대시·대문자)
        ("task_forged", False),             # 16진수 아님
        ("task_zzzzzzzz", False),           # g-z 범위
        ("task_1234567", False),            # 7자리(너무 짧음)
        ("task_", False),                   # 빈 접미
        (" task_a1b2c3d4", False),          # 앞 공백
        ("task_a1b2c3d4 ", False),          # 뒤 공백
        ("task__a1b2c3d4", False),          # 밑줄 2개
        ("Task_a1b2c3d4", False),           # 대문자 T
        ("a1b2c3d4", False),                # 접두 없음
        ("", False),                        # 빈 문자열
    ],
)
def test_task_id_re_boundary(task_id: str, expected: bool) -> None:
    module = load_patrol()
    assert (module.TASK_ID_RE.fullmatch(task_id) is not None) is expected


def test_forged_task_id_in_task_list_fails_closed(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # task-list 가 위조 taskId 를 주면 _parse_task_list 전체가 None 이다 → 보고 0.
    fake = FakeOrca([card("F-REAL-WORK", task_id="task_forged")])
    module = with_fake(fake, monkeypatch)
    assert module._parse_task_list(RUN) is None
    lines = run_patrol(module, paths, times=1)
    assert "판정=모름" in lines[0]
    assert fake.sends == []


@pytest.mark.parametrize(
    "forged",
    ["task_forged", "task_zzzzzzzz", "task_1234567"],
)
def test_self_consistent_forged_task_id_never_escalates(
    forged: str,
    paths: tuple[Path, Path],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # task-list 와 dispatch-show 가 같은 위조 taskId 를 줘도 보고 0·거짓 정상 0·예외 0.
    # 이것이 라운드3 의 핵심 끝단 공격이다 (재검수 중요 1).
    fake = FakeOrca([card("F-REAL-WORK", task_id=forged)])
    fake.dispatches = {forged: stale_disp(forged)}
    module = with_fake(fake, monkeypatch)
    lines = run_patrol(module, paths, times=3)
    assert all("판정=모름" in line for line in lines)
    assert all("거짓" not in line and "정상 대기" not in line and "유휴" not in line for line in lines)
    assert fake.sends == []


def test_classify_dispatch_rejects_forged_task_id_direct(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # classify_dispatch 직접 호출 경로: 위조 task_id 는 None 이다.
    forged = "task_zzzzzzzz"
    fake = FakeOrca([], dispatches={forged: stale_disp(forged)})
    module = with_fake(fake, monkeypatch)
    assert module.classify_dispatch(forged, NOW) is None


def test_classify_dispatch_rejects_forged_dispatch_task_id(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # 정상 task_id 로 호출해도 dispatch-show 의 task_id 가 위조면 None 이다.
    good = tid("F-REAL-WORK")
    forged = "task_forged"
    fake = FakeOrca([], dispatches={good: stale_disp(forged)})
    module = with_fake(fake, monkeypatch)
    assert module.classify_dispatch(good, NOW) is None


def test_classify_dispatch_rejects_task_id_mismatch_direct(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # 둘 다 권위 형식이어도 task_id 가 서로 다르면 None 이다 (X3 변형 거부용).
    # dispatch-show 의 task_id 가 호출 task_id 와 불일치하면 다른 카드의 dispatch 다.
    a = "task_a1b2c3d4e5f60001"
    b = "task_a1b2c3d4e5f60002"
    fake = FakeOrca([], dispatches={a: stale_disp(b)})
    module = with_fake(fake, monkeypatch)
    assert module.classify_dispatch(a, NOW) is None


def test_classify_dispatch_accepts_matching_authoritative_pair_direct(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # 권위 형식 + 일치 + fresh 심박 → healthy. 정상 경로가 X3/X10/X11 에 가려지지 않는다.
    a = tid("F-REAL-WORK")
    fake = FakeOrca([], dispatches={a: disp(a)})
    module = with_fake(fake, monkeypatch)
    assert module.classify_dispatch(a, NOW)["state"] == "healthy"


def test_authoritative_task_id_lengths_preserve_healthy_meaning(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    # 권위 8자리·12자리·긴 ID 는 기존 healthy/stale 의미를 그대로 유지한다 (중요 5).
    import hashlib
    paths = (tmp_path / "l.md", tmp_path / "l.json")
    for label, hexlen in [("8자리", 8), ("12자리", 12), ("긴", 16)]:
        h = hashlib.sha256(label.encode()).hexdigest()[:hexlen]
        good_id = f"task_{h}"
        fake = FakeOrca([card(label, task_id=good_id)], dispatches={good_id: disp(good_id)})
        mod = with_fake(fake, monkeypatch)
        lines = run_patrol(mod, paths, times=1)
        assert "판정=정상 대기" in lines[0], f"{label}({good_id}) healthy 유지 실패"
        assert fake.sends == []


# --- 단위 계약: count_dispatched / is_resident_card / 상태 fail-closed ----------
@pytest.mark.parametrize(
    ("title", "expected_resident"),
    [
        ("RELAY-MONITOR", True),                              # 이름과 정확히 같다
        ("RELAY-MONITOR-mailbox-relay-1", True),              # 이름 + 하이픈 경계
        ("  RELAY-MONITOR-test-board  ", True),               # 앞뒤 공백은 다듬는다
        ("RELAY-MONITORING — ordinary feature card", False),  # 남남인 일반 제목
        ("RELAY-MONITORX", False),                            # 경계 없는 이어붙임
        ("RELAY-MONITOR2", False),                            # 숫자로 이어붙임
        ("relay-monitor-test-board", False),                  # 대소문자가 다르면 다른 이름
        ("F-RELAY-MONITOR-LOOKALIKE", False),                 # 가운데에 들어간 이름
        ("", False),                                          # 빈 제목
        ("   ", False),                                       # 공백뿐인 제목
        (None, False),                                        # 제목 칸 자체가 없다
    ],
)
def test_resident_title_boundary(title: str | None, expected_resident: bool) -> None:
    module = load_patrol()
    assert module.is_resident_card(card(title)) is expected_resident



def test_similar_title_is_counted_as_ordinary_work(monkeypatch: pytest.MonkeyPatch) -> None:
    module = with_fake(
        FakeOrca([card("RELAY-MONITORING — ordinary feature card")]), monkeypatch
    )
    assert module.count_dispatched(RUN) == (1, 0)



def test_missing_task_title_is_ordinary_work(monkeypatch: pytest.MonkeyPatch) -> None:
    # 제목을 모르는 카드는 상주가 아니다. 모를 때 일반으로 세야 정체를 숨기지 않는다.
    module = with_fake(FakeOrca([card(None)]), monkeypatch)
    assert module.count_dispatched(RUN) == (1, 0)



def test_known_task_statuses_match_the_shipped_bundle() -> None:
    """번들이 tasks.status 에 실제로 허용하는 값 6개. 추정이 아니라 실측 사본이다.

    운영 DB `~/Library/Application Support/Orca Kyle/orchestration.db` 의 tasks 테이블:
        CHECK(status IN ('pending','ready','dispatched','completed','failed','blocked'))
    (2026-08-12 읽기 전용 조회. 소스 `TaskStatus` union 과도 같다.)
    이 집합이 조용히 늘거나 줄면 모르는 상태를 정상으로 뭉갤 수 있으므로 여기서 못박는다.
    """
    module = load_patrol()
    assert module.KNOWN_TASK_STATUSES == {
        "pending",
        "ready",
        "dispatched",
        "completed",
        "failed",
        "blocked",
    }



@pytest.mark.parametrize(
    "status",
    ["pending", "ready", "completed", "failed", "blocked"],
)
def test_known_non_dispatched_statuses_are_simply_not_counted(
    status: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    module = with_fake(FakeOrca([card("F-WORK", status=status)]), monkeypatch)
    assert module.count_dispatched(RUN) == (0, 0)



def test_null_row_in_task_list_fails_closed(monkeypatch: pytest.MonkeyPatch) -> None:
    module = with_fake(FakeOrca([None, card("F-REAL-WORK")]), monkeypatch)
    assert module.count_dispatched(RUN) is None



def test_non_object_row_in_task_list_fails_closed(monkeypatch: pytest.MonkeyPatch) -> None:
    module = with_fake(FakeOrca(["F-REAL-WORK", card("F-OTHER")]), monkeypatch)
    assert module.count_dispatched(RUN) is None



def test_task_without_status_fails_closed(monkeypatch: pytest.MonkeyPatch) -> None:
    module = with_fake(FakeOrca([card("F-REAL-WORK", status=None)]), monkeypatch)
    assert module.count_dispatched(RUN) is None



def test_unknown_status_fails_closed(monkeypatch: pytest.MonkeyPatch) -> None:
    module = with_fake(FakeOrca([card("F-REAL-WORK", status="mystery")]), monkeypatch)
    assert module.count_dispatched(RUN) is None



def test_tasks_not_a_list_fails_closed(monkeypatch: pytest.MonkeyPatch) -> None:
    module = with_fake(FakeOrca("dispatched"), monkeypatch)
    assert module.count_dispatched(RUN) is None



def test_missing_tasks_key_fails_closed(monkeypatch: pytest.MonkeyPatch) -> None:
    # 성공 응답은 빈 판이어도 tasks 배열을 준다. 아예 없으면 모르는 모양이다.
    module = with_fake(FakeOrca([], task_list_result={"count": 0}), monkeypatch)
    assert module.count_dispatched(RUN) is None



def test_non_object_result_fails_closed(monkeypatch: pytest.MonkeyPatch) -> None:
    module = with_fake(FakeOrca([], task_list_result="ok"), monkeypatch)
    assert module.count_dispatched(RUN) is None



def test_empty_task_list_is_a_real_zero_not_unknown(monkeypatch: pytest.MonkeyPatch) -> None:
    # 진짜 빈 판은 모름이 아니다. 여기까지 닫아 버리면 유휴 판정이 영영 안 선다.
    module = with_fake(FakeOrca([]), monkeypatch)
    assert module.count_dispatched(RUN) == (0, 0)



@pytest.mark.parametrize(
    ("status", "label"),
    [
        ([], "빈 배열"),
        ({}, "빈 객체"),
        (["dispatched"], "정상값을 담은 배열"),
        ({"value": "dispatched"}, "정상값을 담은 객체"),
        (("dispatched",), "튜플"),
        (7, "정수"),
        (1.5, "실수"),
        (True, "참거짓"),
        (b"dispatched", "바이트열"),
        ("", "빈 문자열"),
        ("mystery", "모르는 문자열"),
        (None, "상태 칸 자체가 없음"),
    ],
)
def test_non_string_or_unknown_status_fails_closed_without_raising(
    status: object, label: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    module = with_fake(FakeOrca([card("F-REAL-WORK", status=status)]), monkeypatch)
    # 예외가 새면 pytest 가 그 자리에서 잡는다. None 이어야 하고, 던져서는 안 된다.
    assert module.count_dispatched(RUN) is None, label



def test_unhashable_status_beside_a_healthy_card_still_fails_closed(
    monkeypatch: pytest.MonkeyPatch
) -> None:
    # 한 행만 망가져도 그 응답 전체를 이해하지 못한 것이다. 나머지로 셈을 이어가지 않는다.
    module = with_fake(
        FakeOrca([card("F-HEALTHY"), card("F-BROKEN", status=[])]), monkeypatch
    )
    assert module.count_dispatched(RUN) is None


# --- 9. 표준 판 식별자 접두사가 붙은 상주 카드 (F-RELAY-RESIDENT-COUNT-4 요구 a) ----
#
# Why (2026-08-12 실측·재현): 카드 제목 계약은 "spec은 항상 `[판:<판이름>]` 접두사로
# 시작"이다 (SKILL.md:154, mechanics.md 판 식별자 절). 살아 있는 mailbox-relay-1 판의
# 상주 카드는 접두사 없는 `RELAY-MONITOR-mailbox-relay-1` 이었지만 같은 판의 일반 카드는
# 전부 `[판:mailbox-relay-1] …` 형태다. 표준대로 지은 새 판의 상주 카드
# `[판:quota-collection-1] RELAY-MONITOR-quota-collection-1` 은 접두사 때문에 상주에서
# 빠지지 않았다(재현: is_resident_card → False). 그 카드의 dispatch 는 판 수명 내내
# 심박 없는 dispatched 라(실측 ctx_5858b93fb90c: dispatched_at 2026-08-11 16:49:30Z,
# last_heartbeat_at=None) 그대로 stale 로 분류돼 두 사고를 한꺼번에 만든다:
#   (1) 일반 작업 0장인 조용한 감독이 "도는 카드 1"로 보여 유휴가 아닌 정체가 된다
#   (2) 자기 감시 카드에 대해 거짓 worker_dispatch_stale 상신이 나가 감독을 잘못 깨운다
# 반대 대조군(접두사가 붙은 유사 제목 일반 카드)은 여전히 일반 작업이어야 한다.


def test_board_prefixed_resident_card_is_not_counted_as_active_work(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 상주만 = 일반 0. 상주 dispatch 가 stale 여도 상신 0 이어야 한다.
    title = "[판:test-board] RELAY-MONITOR-test-board"
    t = tid(title)
    fake = FakeOrca([card(title)], dispatches={t: stale_disp(t)})
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=1)
    assert "도는 일반 카드 0(상주 1장 제외)" in lines[0]
    assert "판정=유휴" in lines[0]
    assert fake.sends == []


def test_board_prefixed_resident_plus_ordinary_counts_one(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 상주 + 일반 1 = 일반 1. 상주는 제외되고 일반 카드의 정체만 보고된다.
    resident = "[판:test-board] RELAY-MONITOR-test-board"
    rt = tid(resident)
    wt = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card(resident), card("F-REAL-WORK", dispatch_id="ctx_aabbccdd0002")],
        dispatches={
            rt: stale_disp(rt),
            wt: stale_disp(wt, dispatch_id="ctx_aabbccdd0002"),
        },
    )
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=1)
    assert "도는 일반 카드 1(상주 1장 제외)" in lines[0]
    assert "worker dispatch 정체(stale 1)" in lines[0]
    assert len(fake.sends) == 1
    # 상신은 일반 카드 것만이다 — 상주 카드의 dispatch 는 절대 보고되지 않는다.
    assert flag(fake.sends[0], "--task-id") == wt
    assert flag(fake.sends[0], "--dispatch-id") == "ctx_aabbccdd0002"


def test_board_prefixed_lookalike_is_ordinary_and_still_escalates(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 반대 대조군: 접두사를 떼도 이름 경계가 어긋나는 제목은 일반 작업이다.
    # 접두사 처리를 넓게 만들어 일반 카드를 숨기면 이 시험이 떨어진다.
    title = "[판:test-board] RELAY-MONITORING — ordinary feature card"
    t = tid(title)
    fake = FakeOrca([card(title)], dispatches={t: stale_disp(t)})
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=1)
    assert "도는 일반 카드 1(상주 0장 제외)" in lines[0]
    assert "판정=정체" in lines[0]
    assert len(fake.sends) == 1


@pytest.mark.parametrize(
    ("title", "expected_resident"),
    [
        # 표준 접두사가 붙은 상주 카드 — 상주로 빠져야 한다.
        ("[판:quota-collection-1] RELAY-MONITOR-quota-collection-1", True),
        ("[판:mailbox-relay-1] RELAY-MONITOR-mailbox-relay-1", True),
        ("[판:x] RELAY-MONITOR", True),
        ("[판:x]RELAY-MONITOR-y", True),           # 접두사 뒤 공백이 없어도 같다
        ("  [판:x] RELAY-MONITOR-y  ", True),      # 바깥 공백은 다듬는다
        # 반대 대조군 — 접두사가 붙어도 일반 작업이다.
        ("[판:x] RELAY-MONITORING — ordinary feature card", False),
        ("[판:x] RELAY-MONITORX", False),
        ("[판:x] F-RELAY-MONITOR-LOOKALIKE", False),
        ("[판:x] relay-monitor-y", False),
        ("[판:x] ", False),
        # 접두사 한 개만 뗀다 — 겹쳐 붙이면 상주로 인정하지 않는다(넓히지 않기).
        ("[판:a] [판:b] RELAY-MONITOR", False),
        # 접두사 모양이 아니면 떼지 않는다.
        ("[board:x] RELAY-MONITOR", False),
        ("[판:x RELAY-MONITOR", False),
        ("prefix [판:x] RELAY-MONITOR", False),
    ],
)
def test_board_prefixed_resident_title_boundary(
    title: str, expected_resident: bool
) -> None:
    module = load_patrol()
    assert module.is_resident_card(card(title)) is expected_resident


# --- 10. 상신 실패 영수증이 번들 실패 원인을 그대로 적는다 (요구 b) --------------
#
# Why (2026-08-12 실측): 번들은 실패를 **종료코드 1 + stdout JSON** 으로 낸다.
#   $ orca-kyle orchestration send --to run:run_deadbeef0000 --json ; echo $?
#   {"ok":false,"error":{"code":"run_not_found", ...}}
#   1
# 예전 orca() 는 `returncode != 0` 을 먼저 보고 None 으로 닫아 이 error.code 를 통째로
# 버렸다. 그래서 어떤 상신 실패든 영수증이 'cli_no_output' 한 가지로만 찍혔고, 실제
# 원인(run_not_found·no_active_sender_terminal·dispatch_run_mismatch…)을 다음 사람이
# 알 방법이 없었다 — 상신 실패 원인 규명 자체가 막혀 있었다. 이제 구조화 실패 응답을
# 그대로 돌려주고, 성공 판정은 부르는 쪽이 ok 로 직접 한다.


class _FakeProc:
    def __init__(self, returncode: int, stdout: str) -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = ""


def _stub_subprocess(module: ModuleType, monkeypatch: pytest.MonkeyPatch, proc: object) -> None:
    monkeypatch.setattr(module.subprocess, "run", lambda *a, **k: proc)


def test_orca_keeps_structured_error_body_from_nonzero_exit(
    monkeypatch: pytest.MonkeyPatch
) -> None:
    module = load_patrol()
    _stub_subprocess(
        module,
        monkeypatch,
        _FakeProc(1, '{"ok":false,"error":{"code":"run_not_found","message":"Run x was not found."}}'),
    )
    data = module.orca(["orchestration", "send"])
    assert data is not None
    assert data.get("ok") is False
    assert module.error_code(data) == "run_not_found"


@pytest.mark.parametrize(
    ("returncode", "stdout", "label"),
    [
        (1, "", "빈 stdout"),
        (1, "   \n", "공백뿐인 stdout"),
        (1, "Error: boom", "JSON 이 아닌 원문"),
        (1, "[1,2]", "객체가 아닌 JSON 배열"),
        (1, '"run_not_found"', "객체가 아닌 JSON 문자열"),
        (0, "not json", "성공 종료인데 JSON 아님"),
    ],
)
def test_orca_returns_unknown_when_there_is_no_usable_response(
    returncode: int, stdout: str, label: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    # 응답 자체가 없거나 이해 못 할 모양이면 None(모름)이다. 지어내지 않는다.
    module = load_patrol()
    _stub_subprocess(module, monkeypatch, _FakeProc(returncode, stdout))
    assert module.orca(["orchestration", "send"]) is None, label
    assert module.error_code(module.orca(["orchestration", "send"])) == "cli_no_output"


def test_orca_returns_unknown_when_the_bundle_cannot_be_called(
    monkeypatch: pytest.MonkeyPatch
) -> None:
    module = load_patrol()

    def boom(*args: object, **kwargs: object) -> object:
        raise OSError("no such binary")

    monkeypatch.setattr(module.subprocess, "run", boom)
    assert module.orca(["orchestration", "send"]) is None


@pytest.mark.parametrize(
    "code",
    ["run_not_found", "no_active_sender_terminal", "dispatch_run_mismatch", "dispatch_capability_invalid"],
)
def test_escalation_failure_receipt_names_the_bundle_error_code(
    code: str, paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 실패 영수증에 진짜 원인이 적히고, 성공으로 기록하지 않으며, 다음 순찰에 재시도한다.
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        dispatches={t: stale_disp(t)},
        send_results=[{"ok": False, "error": {"code": code}}],
    )
    module = with_fake(fake, monkeypatch)
    _, state_path = paths

    lines = run_patrol(module, paths, times=1)
    assert f"escalation 발송 실패({code})" in lines[0]
    assert "다음 순찰에 재시도" in lines[0]
    assert "ctx_0665dde17589" not in state_path.read_text()

    run_patrol(module, paths, times=1)
    assert len(fake.sends) == 2


def test_send_failure_without_error_code_is_named_unknown_not_success(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # ok=false 인데 error.code 가 없으면 'unknown' 이다. 성공으로 꾸미지 않는다.
    t = tid("F-REAL-WORK")
    fake = FakeOrca(
        [card("F-REAL-WORK")], dispatches={t: stale_disp(t)}, send_results=[{"ok": False}]
    )
    module = with_fake(fake, monkeypatch)
    _, state_path = paths

    lines = run_patrol(module, paths, times=1)
    assert "escalation 발송 실패(unknown)" in lines[0]
    assert "ctx_0665dde17589" not in state_path.read_text()


# --- 11. 교차 Run 전송 계약: --to run:<판> 에 --run 을 병용하지 않는다 ------------
#
# Why (mechanics.md 2) 배분과 대기 · 2026-08-11 omo-deep-analysis-1 재현, 2026-08-12
# 이 판에서 번들로 재확인): send 에 `--to run:<판>` 과 `--run <판>` 을 함께 주면 번들이
# 조회 범위를 --run 으로 먼저 잡은 뒤 targetRunId 와 대조해 `run_not_found` 로 거절한다
# (소스 src/main/runtime/rpc/methods/orchestration.ts:406-420 의 resolvedRunId =
# params.runId ?? targetRunId ?? dispatch.run_id → `run && targetRunId !== run.id` 검사).
# 실측 영수증:
#   --to run:run_c3e0754807a5 --run run_7879c26f3598 → {"code":"run_not_found"} exit 1
#   --to run:run_c3e0754807a5 (--run 제거)          → run_not_found 아님(다른 단계로 진행)
# 지금 상신 조립은 --run 없이 --from + --to 만 쓰므로 이미 계약에 맞다. 그 상태를 여기서
# 잠가, 나중에 "판을 명시하자"며 --run 을 덧붙이는 변경이 조용히 들어오지 못하게 한다.


def test_escalation_uses_from_and_to_only_never_run_flag(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = FakeOrca([card("F-REAL-WORK")], dispatches={t: stale_disp(t)})
    module = with_fake(fake, monkeypatch)

    run_patrol(module, paths, times=1)

    assert len(fake.sends) == 1
    sent = fake.sends[0]
    assert flag(sent, "--from") == RELAY_HANDLE
    assert flag(sent, "--to") == f"run:{RUN}"
    # 병용 금지. --run 이 붙으면 번들이 run_not_found 로 거절해 상신이 0통이 된다.
    assert "--run" not in sent


# --- 12. 화면을 못 읽은 것은 정체가 아니라 모름이다 -----------------------------
#
# Why: orca() 가 구조화 실패 응답(ok=false)도 돌려주게 되면서, terminal read 자리에서
# 성공 판정을 직접 하지 않으면 실패 응답의 빈 result 가 "새 출력 0 · 커서 불변"으로
# 읽혀 못 읽은 화면이 확정 정체로 둔갑한다. 그 정체는 상신까지 끌고 간다.


class _ReadFail(FakeOrca):
    """terminal read 만 구조화 실패로 답하는 가짜 CLI."""

    def __call__(self, args: list[str]) -> dict | None:
        if args[:2] == ["terminal", "read"]:
            self.calls.append(list(args))
            return {"ok": False, "error": {"code": "terminal_handle_stale"}}
        return super().__call__(args)


def test_terminal_read_structured_failure_closes_as_unknown_not_stall(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = _ReadFail([card("F-REAL-WORK")], dispatches={t: stale_disp(t)})
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=1)
    assert "READ_FAIL" in lines[0]
    assert "terminal_handle_stale" in lines[0]
    assert "판정=정체" not in lines[0]
    assert fake.sends == []


class _ReadSilent(FakeOrca):
    """terminal read 가 아무 응답도 못 내는 가짜 CLI (호출 불가·시한 초과)."""

    def __call__(self, args: list[str]) -> dict | None:
        if args[:2] == ["terminal", "read"]:
            self.calls.append(list(args))
            return None
        return super().__call__(args)


def test_terminal_read_no_output_still_closes_as_unknown(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    t = tid("F-REAL-WORK")
    fake = _ReadSilent([card("F-REAL-WORK")], dispatches={t: stale_disp(t)})
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=1)
    assert "READ_FAIL" in lines[0]
    assert "cli_no_output" in lines[0]
    assert fake.sends == []
