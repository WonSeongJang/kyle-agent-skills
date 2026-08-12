from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import date, datetime
from typing import cast

from .warning_policy import JsonArtifact, WarningPolicyError, build_warning_policy


@dataclass(frozen=True, slots=True)
class WarningReadiness:
    schema_version: int
    checked_at: str
    status: str
    required_observation_weeks: int
    eligible_weeks: tuple[str, ...]
    reviewed_weeks: tuple[str, ...]
    missing_operational_weeks: int
    missing_review_weeks: tuple[str, ...]
    enabled_signal_codes: tuple[str, ...]
    ready_to_activate: bool
    blockers: tuple[str, ...]


def _aware_time(value: str) -> str:
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        raise WarningPolicyError("checked_at must include a UTC offset")
    return parsed.isoformat()


def _week_start(iso_week: object) -> date:
    if not isinstance(iso_week, str):
        raise WarningPolicyError("report iso_week must be a string")
    try:
        year_raw, week_raw = iso_week.split("-W", maxsplit=1)
        return date.fromisocalendar(int(year_raw), int(week_raw), 1)
    except (TypeError, ValueError) as error:
        raise WarningPolicyError(f"invalid ISO week: {iso_week}") from error


def _required_weeks(reports: tuple[JsonArtifact, ...]) -> int:
    values = [
        value
        for report in reports
        if isinstance((value := report.payload.get("required_observation_weeks")), int)
        and not isinstance(value, bool)
        and value > 0
    ]
    return values[-1] if values else 2


def _eligible_reports(reports: tuple[JsonArtifact, ...]) -> tuple[JsonArtifact, ...]:
    eligible = [
        report
        for report in reports
        if report.payload.get("observation_eligible") is True
        and report.payload.get("warning_mode") == "observation"
    ]
    by_week: dict[str, JsonArtifact] = {}
    for report in eligible:
        week = report.payload.get("iso_week")
        _week_start(week)
        by_week[cast(str, week)] = report
    return tuple(sorted(by_week.values(), key=lambda item: _week_start(item.payload["iso_week"])))


def _candidate_windows(
    reports: tuple[JsonArtifact, ...],
    required: int,
) -> tuple[tuple[JsonArtifact, ...], ...]:
    windows: list[tuple[JsonArtifact, ...]] = []
    for index in range(len(reports) - required + 1):
        window = reports[index:index + required]
        starts = tuple(_week_start(item.payload["iso_week"]) for item in window)
        if all((current - previous).days == 7 for previous, current in zip(starts, starts[1:])):
            windows.append(window)
    return tuple(windows)


def _review_map(reviews: tuple[JsonArtifact, ...]) -> dict[str, JsonArtifact]:
    result: dict[str, JsonArtifact] = {}
    for review in reviews:
        week = review.payload.get("iso_week")
        _week_start(week)
        result[cast(str, week)] = review
    return result


def _waiting_for_weeks(
    eligible: tuple[JsonArtifact, ...],
    required: int,
    checked_at: str,
) -> WarningReadiness:
    latest_run: list[JsonArtifact] = []
    for report in eligible:
        if latest_run:
            previous = _week_start(latest_run[-1].payload["iso_week"])
            current = _week_start(report.payload["iso_week"])
            if (current - previous).days != 7:
                latest_run = []
        latest_run.append(report)
    weeks = tuple(cast(str, item.payload["iso_week"]) for item in latest_run[-required:])
    return WarningReadiness(
        schema_version=1,
        checked_at=checked_at,
        status="waiting-for-operational-weeks",
        required_observation_weeks=required,
        eligible_weeks=weeks,
        reviewed_weeks=(),
        missing_operational_weeks=max(0, required - len(weeks)),
        missing_review_weeks=(),
        enabled_signal_codes=(),
        ready_to_activate=False,
        blockers=("completed observation-eligible weekly reports are still missing",),
    )


def assess_warning_readiness(
    reports: tuple[JsonArtifact, ...],
    reviews: tuple[JsonArtifact, ...],
    *,
    checked_at: str,
) -> WarningReadiness:
    normalized_time = _aware_time(checked_at)
    required = _required_weeks(reports)
    eligible = _eligible_reports(reports)
    windows = _candidate_windows(eligible, required)
    if not windows:
        return _waiting_for_weeks(eligible, required, normalized_time)
    reviews_by_week = _review_map(reviews)
    for window in windows:
        weeks = tuple(cast(str, item.payload["iso_week"]) for item in window)
        if all(week in reviews_by_week for week in weeks):
            selected_reviews = tuple(reviews_by_week[week] for week in weeks)
            try:
                policy = build_warning_policy(window, selected_reviews, activated_at=normalized_time)
            except WarningPolicyError:
                continue
            return WarningReadiness(
                schema_version=1,
                checked_at=normalized_time,
                status="ready-to-activate",
                required_observation_weeks=required,
                eligible_weeks=weeks,
                reviewed_weeks=weeks,
                missing_operational_weeks=0,
                missing_review_weeks=(),
                enabled_signal_codes=policy.enabled_signal_codes,
                ready_to_activate=True,
                blockers=(),
            )
    selected = windows[-1]
    weeks = tuple(cast(str, item.payload["iso_week"]) for item in selected)
    reviewed = tuple(week for week in weeks if week in reviews_by_week)
    missing = tuple(week for week in weeks if week not in reviews_by_week)
    blockers = ("human review is missing",) if missing else ("existing reviews do not pass the activation gate",)
    return WarningReadiness(
        schema_version=1,
        checked_at=normalized_time,
        status="waiting-for-reviews" if missing else "review-invalid",
        required_observation_weeks=required,
        eligible_weeks=weeks,
        reviewed_weeks=reviewed,
        missing_operational_weeks=0,
        missing_review_weeks=missing,
        enabled_signal_codes=(),
        ready_to_activate=False,
        blockers=blockers,
    )


def readiness_payload(readiness: WarningReadiness) -> dict[str, object]:
    return cast(dict[str, object], asdict(readiness))
