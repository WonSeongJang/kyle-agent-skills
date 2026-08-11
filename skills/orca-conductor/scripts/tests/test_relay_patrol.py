"""헤드리스 중계기 순찰 회귀 — 상주 카드 제외와 정체 상신 계약.

Why (2026-08-12 F-RELAY-RESIDENT-COUNT 실측): 일반 작업이 0장인데 상주 카드
RELAY-MONITOR 한 장이 dispatched 로 남아 있어서 순찰기가 "도는 카드 1"로 세었다.
그래서 조용한 감독이 유휴가 아니라 정체로 찍혔고, 02:49/02:54/02:59 연속 무진행이
3→5 까지 쌓였다. 같은 시간대에 상신도 8회 연속 실패했는데, 원인은 발신 자리(--from)가
빠진 것이다 — 순찰기는 launchd PPID=1 데몬이라 붙은 터미널이 없어 번들 CLI 가
`no_active_sender_terminal` 로 거절한다.

여기서 잠그는 계약은 셋이다.
  1. 상주 카드만 dispatched 면 일반 활성 수는 0이고 조용한 감독은 유휴다.
  2. 일반 작업 카드가 있으면 그대로 세고, 연속 2회 실제 정체에서 escalation 이
     정확히 한 번 나간다 (--from · --to run:<판> · --type escalation).
  3. 발송 실패는 성공으로 적지 않고, 다음 순찰이 그대로 다시 시도한다.

실제 우편은 한 통도 나가지 않는다. 번들 CLI 자리는 통째로 가짜(fixture)로 바꾼다.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

import pytest

SCRIPT = Path(__file__).parents[1] / "relay-patrol.py"

PROJECT = "kyle-agent-skills"
BOARD = "test-board"
RUN = "run_testrelay0001"
SUPERVISOR_HANDLE = "term_supervisor_0001"
RELAY_HANDLE = "term_relay_0001"


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
) -> ModuleType:
    """순찰기를 새로 읽고 바깥으로 나가는 두 자리를 모두 가짜로 막는다.

    orca() 는 번들 CLI, ask_judge() 는 DeepSeek 호출이다. 둘 다 막으므로 이 시험에서
    실제 우편도, 실제 모델 호출도 일어나지 않는다. judge 를 주지 않은 시험이 애매 갈래로
    새면 그 자리에서 시끄럽게 떨어진다 — 조용히 진짜 모델을 부르는 것보다 낫다.
    """
    module = load_patrol()
    monkeypatch.setattr(module, "orca", fake)

    def judge_stub(snippet: str) -> tuple[str, str]:
        if judge is None:
            raise AssertionError("이 시험은 모델 판정 갈래로 가면 안 된다(셸 확정 갈래여야 한다)")
        return judge

    monkeypatch.setattr(module, "ask_judge", judge_stub)
    return module


_UNSET = object()


def card(title: str | None, status: object = "dispatched") -> dict:
    """시험용 카드 한 장.

    title=None 이면 제목 칸 자체가 없고, status=None 이면 상태 칸 자체가 없다.
    status 에는 문자열이 아닌 값도 그대로 넣을 수 있다 — 망가진 자료형을 재현해야 한다.
    """
    row: dict = {"id": f"task_{title}"}
    if title is not None:
        row["task_title"] = title
    if status is not None:
        row["status"] = status
    return row


class FakeOrca:
    """번들 CLI 자리를 대신한다. 실제로는 아무것도 보내지 않고 argv 만 모은다."""

    def __init__(
        self,
        tasks: object,
        *,
        relay_live: bool = True,
        send_results: list[dict] | None = None,
        task_list_result: object = _UNSET,
    ) -> None:
        # tasks 는 목록이 아닐 수도 있다. 망가진 응답도 그대로 흘려보내야 fail-closed 를 잰다.
        self.tasks = tasks
        # result 껍질 자체를 바꿔 보고 싶을 때만 쓴다(비객체 result 회귀).
        self.task_list_result = task_list_result
        self.relay_live = relay_live
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
            return {"ok": True, "result": {"tasks": self.tasks}}
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


# --- 1. 상주 카드 제외 -------------------------------------------------------


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


# --- 2. 진짜 정체는 정확히 한 번 상신된다 ------------------------------------


def test_two_real_stalls_send_exactly_one_escalation(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = FakeOrca([card("RELAY-MONITOR-test-board"), card("F-REAL-WORK")])
    module = with_fake(fake, monkeypatch)

    first = run_patrol(module, paths, times=1)
    assert "판정=정체" in first[0]
    assert "도는 일반 카드 1(상주 1장 제외)" in first[0]
    assert "연속무진행=1" in first[0]
    assert fake.sends == []

    lines = run_patrol(module, paths, times=3)
    assert len(lines) == 4
    assert "연속무진행=2" in lines[1]
    assert "escalation 1회(msg_ok_0001)" in lines[1]
    # 같은 정체가 이어져도 두 번째 우편은 없다.
    assert "escalation" not in lines[2].split("| 조치=")[1]
    assert "escalation" not in lines[3].split("| 조치=")[1]
    assert len(fake.sends) == 1


def test_escalation_uses_current_bundle_cli_contract(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = FakeOrca([card("RELAY-MONITOR-test-board"), card("F-REAL-WORK")])
    module = with_fake(fake, monkeypatch)

    run_patrol(module, paths, times=2)

    assert len(fake.sends) == 1
    sent = fake.sends[0]
    # --from 없이 부르면 데몬 환경에서 no_active_sender_terminal 로 거절된다.
    assert "--from" in sent
    assert flag(sent, "--from") == RELAY_HANDLE
    assert flag(sent, "--to") == f"run:{RUN}"
    assert flag(sent, "--type") == "escalation"
    assert flag(sent, "--subject") == f"supervisor_stall:{SUPERVISOR_HANDLE}"
    # 발신 자리는 캐시하지 않고 보내기 직전에 명부에서 다시 찾는다.
    assert ["roster", "resolve"] == fake.calls[-2][:2]
    assert flag(fake.calls[-2], "--role") == "relay"


def test_progress_resets_cycles_and_allows_a_later_escalation(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = FakeOrca([card("F-REAL-WORK")])
    module = with_fake(fake, monkeypatch, judge=("진행", "새 도구 실행"))

    run_patrol(module, paths, times=2)
    assert len(fake.sends) == 1

    # 감독이 다시 움직이면 정체 기록이 지워진다.
    fake.advance = 500
    lines = run_patrol(module, paths, times=1)
    assert "판정=진행" in lines[2]
    assert "연속무진행=0" in lines[2]

    # 그리고 다음 정체는 처음부터 다시 세어 새로 한 번만 상신된다.
    fake.advance = 0
    fake.send_results = [{"ok": True, "result": {"message": {"id": "msg_ok_0002"}}}]
    lines = run_patrol(module, paths, times=3)

    assert "연속무진행=1" in lines[3]
    assert "escalation" not in lines[3].split("| 조치=")[1]
    assert "escalation 1회(msg_ok_0002)" in lines[4]
    assert "escalation" not in lines[5].split("| 조치=")[1]
    assert len(fake.sends) == 2


# --- 3. 발송 실패는 성공으로 기록되지 않는다 ---------------------------------


def test_send_failure_is_not_recorded_and_retries_next_patrol(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = FakeOrca(
        [card("F-REAL-WORK")],
        send_results=[
            {"ok": False, "error": {"code": "no_active_sender_terminal"}},
            {"ok": True, "result": {"message": {"id": "msg_ok_0003"}}},
        ],
    )
    module = with_fake(fake, monkeypatch)
    _, state_path = paths

    lines = run_patrol(module, paths, times=2)
    assert "escalation 발송 실패(no_active_sender_terminal)" in lines[1]
    assert "다음 순찰에 재시도" in lines[1]
    # 실패를 성공으로 적지 않았다 — 그래야 다음 순찰이 다시 시도한다.
    assert "stall_escalation_id" not in state_path.read_text()

    lines = run_patrol(module, paths, times=1)
    assert len(fake.sends) == 2
    assert "escalation 1회(msg_ok_0003)" in lines[2]
    assert "msg_ok_0003" in state_path.read_text()

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

    fake = Silent([card("F-REAL-WORK")])
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=2)
    assert "escalation 발송 실패(cli_no_output)" in lines[1]
    assert len(fake.sends) == 1


def test_missing_relay_sender_holds_instead_of_sending(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = FakeOrca([card("F-REAL-WORK")], relay_live=False)
    module = with_fake(fake, monkeypatch)
    _, state_path = paths

    lines = run_patrol(module, paths, times=2)

    assert fake.sends == []
    assert "escalation 보류 — 발신 자리(role=relay)를 못 찾았다" in lines[1]
    assert "stall_escalation_id" not in state_path.read_text()


# --- 4. 제목 경계: 상주 이름과 남남인 제목을 가른다 --------------------------
#
# Why (2026-08-12 독립 검수 중요 1): 앞머리 일치만 보면 `RELAY-MONITORING — 일반 기능
# 카드`도 상주로 빠진다. 그러면 일반 작업이 0장으로 보여 진짜 정체가 통째로 유휴로
# 덮이고 상신이 0통이 된다. 그래서 이름 경계 대조군을 정확·하이픈·유사·공백·없음까지
# 한 표에 깔아 둔다.


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


def test_similar_title_does_not_suppress_escalation(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 유사 제목 한 장이 상주로 잘못 빠지면 이 판은 유휴가 되어 상신이 영영 없다.
    fake = FakeOrca([card("RELAY-MONITORING — ordinary feature card")])
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=3)

    assert any("판정=정체" in line for line in lines)
    assert len(fake.sends) == 1


def test_missing_task_title_is_ordinary_work(monkeypatch: pytest.MonkeyPatch) -> None:
    # 제목을 모르는 카드는 상주가 아니다. 모를 때 일반으로 세야 정체를 숨기지 않는다.
    module = with_fake(FakeOrca([card(None)]), monkeypatch)
    assert module.count_dispatched(RUN) == (1, 0)


# --- 5. 망가진 응답은 0이 아니라 '모름'으로 닫는다 ---------------------------
#
# Why (2026-08-12 독립 검수 중요 2): 검사 없이 task.get() 을 부르면 tasks=[None, 정상카드]
# 하나에 순찰 주기가 예외로 끊기고, 모르는 status 는 조용히 (0, 0) 이 되어 거짓 유휴가
# 된다. 두 갈래 모두 정체를 숨기는 쪽으로 틀린다.


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


def test_unknown_status_does_not_suppress_escalation(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 모름은 유휴가 아니다. 세지 못한 판에서도 정체는 그대로 상신돼야 한다.
    fake = FakeOrca([card("F-REAL-WORK", status="mystery")])
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=3)

    assert any("판정=정체" in line for line in lines)
    assert "도는 일반 카드 모름" in lines[0]
    assert len(fake.sends) == 1


def test_broken_row_does_not_crash_the_patrol_cycle(
    paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    # 예외로 끊기면 그 주기의 감시가 통째로 사라진다. 일기 줄은 반드시 남아야 한다.
    fake = FakeOrca([None, card("F-REAL-WORK")])
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=2)

    assert len(lines) == 2
    assert "도는 일반 카드 모름(상주 0장 제외)" in lines[0]
    assert len(fake.sends) == 1


# --- 6. status 자료형까지 fail-closed ----------------------------------------
#
# Why (2026-08-12 독립 재검수 중요 1): `status not in KNOWN_TASK_STATUSES` 는 해시할 수
# 없는 값에서 비교 자체가 TypeError 다. status=[] · {} · ["dispatched"] 하나면
# count_dispatched 가 None 으로 닫히기는커녕 예외로 빠져 patrol 의 정체 횟수 계산과
# 상신 경로에 아예 닿지 못한다. 상시 반복 모드는 PATROL_ERROR 한 줄만 남기고 다음
# 주기로 넘어가므로, 같은 응답이 이어지면 연속 무진행이 영영 안 쌓이고 상신은 0통이다.
# 그래서 모르는 자료형은 모르는 값과 똑같이 '모름'으로 닫는다.


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


@pytest.mark.parametrize("status", [[], {}, ["dispatched"]])
def test_unhashable_status_does_not_break_the_patrol_cycle(
    status: object, paths: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    """해시 불가 status 가 와도 순찰은 돌고, 진짜 정체는 그대로 한 번 상신된다."""
    fake = FakeOrca([card("F-REAL-WORK", status=status)])
    module = with_fake(fake, monkeypatch)

    lines = run_patrol(module, paths, times=3)

    assert len(lines) == 3
    assert "도는 일반 카드 모름(상주 0장 제외)" in lines[0]
    assert any("판정=정체" in line for line in lines)
    assert len(fake.sends) == 1
    assert flag(fake.sends[0], "--type") == "escalation"


def test_unhashable_status_beside_a_healthy_card_still_fails_closed(
    monkeypatch: pytest.MonkeyPatch
) -> None:
    # 한 행만 망가져도 그 응답 전체를 이해하지 못한 것이다. 나머지로 셈을 이어가지 않는다.
    module = with_fake(
        FakeOrca([card("F-HEALTHY"), card("F-BROKEN", status=[])]), monkeypatch
    )
    assert module.count_dispatched(RUN) is None
