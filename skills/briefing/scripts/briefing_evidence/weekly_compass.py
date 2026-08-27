from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping, Sequence
from dataclasses import asdict
from datetime import datetime, timedelta
from typing import cast

from .compass_models import LaneKind, LaneSummary, ObservationSignal, WeeklyCompassReport, WorkEpisode
from .episodes import build_work_episodes


def _mapping(value: object, location: str) -> Mapping[str, object]:
    if not isinstance(value, Mapping):
        raise ValueError(f"{location} must be an object")
    return cast(Mapping[str, object], value)


def _items(value: object, location: str) -> tuple[object, ...]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        raise ValueError(f"{location} must be an array")
    return tuple(value)


def _text(value: object, location: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{location} must be a string")
    return value


def _texts(value: object, location: str) -> tuple[str, ...]:
    return tuple(_text(item, f"{location}[]") for item in _items(value, location))


def _lane_summaries(contract: Mapping[str, object], episodes: tuple[WorkEpisode, ...]) -> tuple[LaneSummary, ...]:
    summaries: list[LaneSummary] = []
    for raw in _items(contract["lanes"], "compass_contract.lanes"):
        lane = _mapping(raw, "lane")
        lane_id = _text(lane["id"], "lane.id")
        selected = tuple(episode for episode in episodes if episode.lane_id == lane_id)
        observed = tuple(sorted({kind for episode in selected for kind in episode.observed_evidence}))
        expected = _texts(lane["expected_evidence"], "lane.expected_evidence")
        summaries.append(
            LaneSummary(
                lane_id=lane_id,
                lane_kind=cast(LaneKind, _text(lane["kind"], "lane.kind")),
                description=_text(lane["description"], "lane.description"),
                episode_count=len(selected),
                commit_count=sum(episode.commit_count for episode in selected),
                ongoing_count=sum(episode.ongoing for episode in selected),
                publication_count=sum(episode.publication_count for episode in selected),
                observed_evidence=observed,
                expected_evidence=expected,
                evidence_status="observed" if set(observed) & set(expected) else "not-observed",
            )
        )
    unclassified = tuple(episode for episode in episodes if episode.lane_id == "unclassified")
    if unclassified:
        summaries.append(
            LaneSummary(
                lane_id="unclassified", lane_kind="unclassified", description="방향 계약으로 분류되지 않은 활동",
                episode_count=len(unclassified), commit_count=sum(item.commit_count for item in unclassified),
                ongoing_count=sum(item.ongoing for item in unclassified), publication_count=sum(item.publication_count for item in unclassified),
                observed_evidence=tuple(sorted({kind for item in unclassified for kind in item.observed_evidence})),
                expected_evidence=(), evidence_status="not-applicable",
            )
        )
    return tuple(summaries)


def _signals(summaries: tuple[LaneSummary, ...], episodes: tuple[WorkEpisode, ...]) -> tuple[ObservationSignal, ...]:
    signals: list[ObservationSignal] = []
    by_kind = {kind: tuple(episode for episode in episodes if episode.lane_kind == kind) for kind in ("primary", "conditional", "maintenance", "hold", "unclassified")}
    if by_kind["hold"]:
        signals.append(ObservationSignal("hold-activity", "보류 갈래에서 활동이 관찰됨", None, tuple(item.id for item in by_kind["hold"])))
    if not by_kind["primary"]:
        signals.append(ObservationSignal("primary-activity-missing", "메인 갈래 활동이 관찰되지 않음", None, ()))
    primary_summaries = [summary for summary in summaries if summary.lane_kind == "primary"]
    if by_kind["primary"] and all(summary.evidence_status == "not-observed" for summary in primary_summaries):
        signals.append(ObservationSignal("primary-evidence-missing", "메인 활동은 있으나 기대 결과 증거가 관찰되지 않음", None, tuple(item.id for item in by_kind["primary"])))
    for summary in (item for item in summaries if item.lane_kind == "conditional" and item.episode_count and item.evidence_status == "not-observed"):
        selected = tuple(episode.id for episode in episodes if episode.lane_id == summary.lane_id)
        signals.append(ObservationSignal("conditional-evidence-missing", "조건부 갈래 활동에 검증 증거가 관찰되지 않음", summary.lane_id, selected))
    if len(by_kind["maintenance"]) > len(by_kind["primary"]) and by_kind["maintenance"]:
        signals.append(ObservationSignal("maintenance-dominance", "회사 수성 작업 묶음이 메인 작업 묶음보다 많음", None, tuple(item.id for item in by_kind["maintenance"])))
    if by_kind["unclassified"]:
        signals.append(ObservationSignal("unclassified-activity", "방향 계약으로 분류되지 않은 활동이 있음", None, tuple(item.id for item in by_kind["unclassified"])))
    return tuple(signals)


def _weekly_period(start: str, end: str) -> tuple[str, bool, datetime]:
    start_time = datetime.fromisoformat(start)
    end_time = datetime.fromisoformat(end)
    next_week = start_time + timedelta(days=7)
    starts_at_midnight = start_time.time().replace(tzinfo=None) == datetime.min.time()
    ends_at_midnight = end_time.time().replace(tzinfo=None) == datetime.min.time()
    if (
        start_time.tzinfo is None
        or end_time.tzinfo is None
        or start_time.weekday() != 0
        or not starts_at_midnight
        or not ends_at_midnight
        or not start_time < end_time <= next_week
    ):
        raise ValueError("weekly compass window must start Monday 00:00 and stay within one ISO week")
    year, week, _ = start_time.date().isocalendar()
    return f"{year}-W{week:02d}", end_time == next_week, end_time


def build_weekly_compass(
    evidence: Mapping[str, object],
    *,
    evidence_sha256: str | None = None,
    operational: bool = False,
) -> WeeklyCompassReport:
    contract = _mapping(evidence["compass_contract"], "compass_contract")
    window = _mapping(evidence["window"], "window")
    start = _text(window["start"], "window.start")
    end = _text(window["end"], "window.end")
    iso_week, period_complete, period_end = _weekly_period(start, end)
    generated_at = _text(evidence["generated_at"], "generated_at")
    generated_time = datetime.fromisoformat(generated_at)
    operational_window = period_end <= generated_time <= period_end + timedelta(days=2)
    episodes = build_work_episodes(evidence)
    summaries = _lane_summaries(contract, episodes)
    observed = tuple(sorted({kind for episode in episodes for kind in episode.observed_evidence}))
    eligible_north_star_episodes = tuple(
        episode
        for episode in episodes
        if episode.classification == "personal"
        and episode.lane_kind in {"primary", "support", "conditional"}
    )
    north_star_observed = {
        kind
        for episode in eligible_north_star_episodes
        for kind in episode.observed_evidence
    }
    north_star = _mapping(contract["north_star"], "north_star")
    north_star_evidence = set(_texts(north_star["evidence"], "north_star.evidence"))
    canonical = json.dumps(evidence, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    source_hash = evidence_sha256 or hashlib.sha256(canonical.encode()).hexdigest()
    contract_canonical = json.dumps(contract, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    contract_hash = hashlib.sha256(contract_canonical.encode()).hexdigest()
    review = _mapping(contract["review"], "compass_contract.review")
    required_observation_weeks = int(review["warning_observation_weeks"])
    return WeeklyCompassReport(
        schema_version=1,
        generated_at=generated_at,
        period_start=start,
        period_end_exclusive=end,
        iso_week=iso_week,
        contract_id=_text(contract["contract_id"], "contract_id"),
        contract_sha256=contract_hash,
        evidence_sha256=source_hash,
        warning_mode="observation",
        required_observation_weeks=required_observation_weeks,
        period_complete=period_complete,
        observation_eligible=operational and period_complete and operational_window,
        north_star_statement=_text(north_star["statement"], "north_star.statement"),
        north_star_status="observed" if north_star_observed & north_star_evidence else "not-observed",
        observed_evidence=observed,
        lane_summaries=summaries,
        episodes=episodes,
        observation_signals=_signals(summaries, episodes),
        automatic_warnings=(),
    )


def report_payload(report: WeeklyCompassReport) -> dict[str, object]:
    payload = asdict(report)
    for episode in cast(list[dict[str, object]], payload["episodes"]):
        episode["correlation_keys"] = sorted(cast(set[str], episode["correlation_keys"]))
        episode["observed_evidence"] = sorted(cast(set[str], episode["observed_evidence"]))
    return cast(dict[str, object], payload)


def render_weekly_compass(report: WeeklyCompassReport) -> str:
    lines = [
        f"# {report.iso_week} 주간 방향 나침반",
        "",
        "## Why",
        "",
        "이번 주의 작업량이 아니라, 선언한 방향에 실제 결과 증거가 쌓였는지 확인한다.",
        "",
        f"- 기간: `{report.period_start}` ~ `{report.period_end_exclusive}` (끝 시각 제외)",
        f"- 방향 계약: `{report.contract_id}` (`{report.contract_sha256[:12]}…`)",
        f"- 경고 모드: `{report.warning_mode}` / 자동 경고: `{len(report.automatic_warnings)}개`",
        f"- 필요한 관찰 주차: `{report.required_observation_weeks}주`",
        f"- 주차 상태: `{'완료' if report.period_complete else '진행 중'}` / 관찰 주차 인정: `{'예' if report.observation_eligible else '아니오'}`",
        f"- 북극성: {report.north_star_statement}",
        f"- 북극성 증거: **{'관찰됨' if report.north_star_status == 'observed' else '관찰되지 않음'}**",
        "",
        "## 갈래별 결과",
        "",
        "| 갈래 | 종류 | 작업 묶음 | 커밋 | 진행 중 | 발행 | 결과 증거 |",
        "|---|---:|---:|---:|---:|---:|---|",
    ]
    for summary in report.lane_summaries:
        evidence = ", ".join(summary.observed_evidence) or "없음"
        lines.append(f"| {summary.lane_id} | {summary.lane_kind} | {summary.episode_count} | {summary.commit_count} | {summary.ongoing_count} | {summary.publication_count} | {evidence} |")
    if report.automatic_warnings:
        lines.extend(["", "## 자동 경고", ""])
        lines.extend(f"- {warning}" for warning in report.automatic_warnings)
    lines.extend(["", "## 관찰 신호", ""])
    if report.observation_signals:
        lines.extend(f"- `{signal.code}`: {signal.message}" for signal in report.observation_signals)
    else:
        lines.append("- 특이 신호 없음")
    lines.extend(["", "## 작업 묶음", ""])
    for episode in report.episodes:
        title = episode.titles[0] if episode.titles else "제목 없음"
        evidence = ", ".join(sorted(episode.observed_evidence)) or "결과 증거 없음"
        state = "진행 중" if episode.ongoing else f"커밋 {episode.commit_count}개"
        lines.append(f"- `{episode.lane_id}` / **{episode.repository}** / {state}: {title} ({evidence})")
    lines.extend(["", f"원본 evidence SHA-256: `{report.evidence_sha256}`", ""])
    return "\n".join(lines)
