from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping, Sequence
from dataclasses import asdict, dataclass, replace
from datetime import date, datetime
from typing import cast

from .compass_models import WeeklyCompassReport

class WarningPolicyError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class JsonArtifact:
    payload: dict[str, object]
    sha256: str


@dataclass(frozen=True, slots=True)
class WarningPolicy:
    schema_version: int
    status: str
    activated_at: str
    contract_id: str
    contract_sha256: str
    required_observation_weeks: int
    source_weeks: tuple[str, ...]
    source_report_sha256: tuple[str, ...]
    source_review_sha256: tuple[str, ...]
    enabled_signal_codes: tuple[str, ...]


def canonical_json_bytes(payload: Mapping[str, object]) -> bytes:
    return f"{json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)}\n".encode()


def load_json_artifact(path: str) -> JsonArtifact:
    raw = __import__("pathlib").Path(path).read_bytes()
    parsed = cast(object, json.loads(raw))
    if not isinstance(parsed, dict) or any(not isinstance(key, str) for key in parsed):
        raise WarningPolicyError(f"{path} must contain a JSON object")
    return JsonArtifact(cast(dict[str, object], parsed), hashlib.sha256(raw).hexdigest())


def _mapping(value: object, location: str) -> Mapping[str, object]:
    if not isinstance(value, Mapping) or any(not isinstance(key, str) for key in value):
        raise WarningPolicyError(f"{location} must be an object")
    return cast(Mapping[str, object], value)


def _items(value: object, location: str) -> tuple[object, ...]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        raise WarningPolicyError(f"{location} must be an array")
    return tuple(value)


def _text(value: object, location: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise WarningPolicyError(f"{location} must be a non-empty string")
    return value.strip()


def _positive_integer(value: object, location: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise WarningPolicyError(f"{location} must be a positive integer")
    return value


def _aware_time(value: object, location: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(_text(value, location))
    except ValueError as error:
        raise WarningPolicyError(f"{location} must be ISO-8601") from error
    if parsed.tzinfo is None:
        raise WarningPolicyError(f"{location} must include a UTC offset")
    return parsed


def _signal_codes(report: Mapping[str, object]) -> tuple[str, ...]:
    signals = tuple(_mapping(item, "observation_signals[]") for item in _items(report["observation_signals"], "observation_signals"))
    codes = tuple(_text(signal["code"], "observation_signals[].code") for signal in signals)
    if len(codes) != len(set(codes)):
        raise WarningPolicyError("observation signal codes must be unique")
    return codes


def build_review(
    report: JsonArtifact,
    *,
    reviewer: str,
    reviewed_at: str,
    accepted_signal_codes: tuple[str, ...],
    false_positive_signal_codes: tuple[str, ...],
) -> dict[str, object]:
    if report.payload.get("observation_eligible") is not True:
        raise WarningPolicyError("only an observation-eligible report can be reviewed")
    if report.payload.get("warning_mode") != "observation":
        raise WarningPolicyError("reviewed report must still be in observation mode")
    signals = set(_signal_codes(report.payload))
    accepted = set(accepted_signal_codes)
    false_positive = set(false_positive_signal_codes)
    if accepted & false_positive:
        raise WarningPolicyError("a signal cannot be accepted and false-positive")
    if accepted | false_positive != signals:
        raise WarningPolicyError("review every signal exactly once")
    decisions = {
        code: "accepted" if code in accepted else "false-positive"
        for code in sorted(signals)
    }
    return {
        "schema_version": 1,
        "iso_week": _text(report.payload["iso_week"], "iso_week"),
        "contract_id": _text(report.payload["contract_id"], "contract_id"),
        "contract_sha256": _text(report.payload["contract_sha256"], "contract_sha256"),
        "report_sha256": report.sha256,
        "reviewer": _text(reviewer, "reviewer"),
        "reviewed_at": _aware_time(reviewed_at, "reviewed_at").isoformat(),
        "signal_reviews": decisions,
    }


def _week_start(iso_week: str) -> date:
    try:
        year_raw, week_raw = iso_week.split("-W", maxsplit=1)
        return date.fromisocalendar(int(year_raw), int(week_raw), 1)
    except (ValueError, TypeError) as error:
        raise WarningPolicyError(f"invalid ISO week: {iso_week}") from error


def _validated_pair(
    report: JsonArtifact,
    review: JsonArtifact,
) -> tuple[str, str, str, set[str], int, datetime]:
    report_payload = report.payload
    review_payload = review.payload
    week = _text(report_payload["iso_week"], "report.iso_week")
    if report_payload.get("observation_eligible") is not True:
        raise WarningPolicyError(f"{week} is not observation eligible")
    if report_payload.get("warning_mode") != "observation":
        raise WarningPolicyError(f"{week} must still be in observation mode")
    contract_id = _text(report_payload["contract_id"], "report.contract_id")
    contract_sha256 = _text(report_payload["contract_sha256"], "report.contract_sha256")
    if _text(review_payload["iso_week"], "review.iso_week") != week:
        raise WarningPolicyError(f"review week mismatch for {week}")
    if _text(review_payload["contract_id"], "review.contract_id") != contract_id:
        raise WarningPolicyError(f"review contract mismatch for {week}")
    if _text(review_payload["contract_sha256"], "review.contract_sha256") != contract_sha256:
        raise WarningPolicyError(f"review contract fingerprint mismatch for {week}")
    if _text(review_payload["report_sha256"], "review.report_sha256") != report.sha256:
        raise WarningPolicyError(f"report hash mismatch for {week}")
    signal_codes = set(_signal_codes(report_payload))
    decisions = _mapping(review_payload["signal_reviews"], "review.signal_reviews")
    if set(decisions) != signal_codes:
        raise WarningPolicyError(f"review every signal for {week}")
    invalid = sorted(value for value in decisions.values() if value not in {"accepted", "false-positive"})
    if invalid:
        raise WarningPolicyError(f"invalid review decisions for {week}: {', '.join(cast(list[str], invalid))}")
    accepted = {code for code, decision in decisions.items() if decision == "accepted"}
    reviewed_at = _aware_time(review_payload["reviewed_at"], "review.reviewed_at")
    period_end = _aware_time(report_payload["period_end_exclusive"], "report.period_end_exclusive")
    if reviewed_at < period_end:
        raise WarningPolicyError(f"review for {week} happened before period end")
    required = _positive_integer(report_payload["required_observation_weeks"], "required_observation_weeks")
    return week, contract_id, contract_sha256, accepted, required, reviewed_at


def build_warning_policy(
    reports: tuple[JsonArtifact, ...],
    reviews: tuple[JsonArtifact, ...],
    *,
    activated_at: str,
) -> WarningPolicy:
    if not reports:
        raise WarningPolicyError("reports must not be empty")
    required = _positive_integer(reports[0].payload["required_observation_weeks"], "required_observation_weeks")
    if len(reports) != required or len(reviews) != required:
        raise WarningPolicyError(f"activation requires exactly {required} reviewed weeks")
    reviews_by_week = {_text(item.payload["iso_week"], "review.iso_week"): item for item in reviews}
    if len(reviews_by_week) != len(reviews):
        raise WarningPolicyError("review weeks must be unique")
    paired: list[tuple[JsonArtifact, JsonArtifact, str, str, str, set[str], datetime]] = []
    for report in reports:
        week = _text(report.payload["iso_week"], "report.iso_week")
        review = reviews_by_week.get(week)
        if review is None:
            raise WarningPolicyError(f"missing review for {week}")
        validated_week, contract_id, contract_sha256, accepted, report_required, reviewed_at = _validated_pair(report, review)
        if report_required != required:
            raise WarningPolicyError("required observation weeks must match")
        paired.append((report, review, validated_week, contract_id, contract_sha256, accepted, reviewed_at))
    paired.sort(key=lambda item: _week_start(item[2]))
    starts = tuple(_week_start(item[2]) for item in paired)
    if any((current - previous).days != 7 for previous, current in zip(starts, starts[1:])):
        raise WarningPolicyError("reports must cover consecutive ISO weeks")
    contract_ids = {item[3] for item in paired}
    if len(contract_ids) != 1:
        raise WarningPolicyError("all reports must use the same contract")
    contract_hashes = {item[4] for item in paired}
    if len(contract_hashes) != 1:
        raise WarningPolicyError("all reports must use the same contract fingerprint")
    activation_time = _aware_time(activated_at, "activated_at")
    if activation_time < max(item[6] for item in paired):
        raise WarningPolicyError("activation must happen after every review")
    enabled = set.intersection(*(item[5] for item in paired))
    if not enabled:
        raise WarningPolicyError("no signal was accepted in every reviewed week")
    return WarningPolicy(
        schema_version=1,
        status="active",
        activated_at=activation_time.isoformat(),
        contract_id=next(iter(contract_ids)),
        contract_sha256=next(iter(contract_hashes)),
        required_observation_weeks=required,
        source_weeks=tuple(item[2] for item in paired),
        source_report_sha256=tuple(item[0].sha256 for item in paired),
        source_review_sha256=tuple(item[1].sha256 for item in paired),
        enabled_signal_codes=tuple(sorted(enabled)),
    )


def warning_policy_payload(policy: WarningPolicy) -> dict[str, object]:
    return cast(dict[str, object], asdict(policy))


def parse_warning_policy(payload: Mapping[str, object]) -> WarningPolicy:
    version = _positive_integer(payload["schema_version"], "policy.schema_version")
    status = _text(payload["status"], "policy.status")
    required = _positive_integer(payload["required_observation_weeks"], "policy.required_observation_weeks")
    weeks = tuple(_text(item, "policy.source_weeks[]") for item in _items(payload["source_weeks"], "policy.source_weeks"))
    report_hashes = tuple(_text(item, "policy.source_report_sha256[]") for item in _items(payload["source_report_sha256"], "policy.source_report_sha256"))
    review_hashes = tuple(_text(item, "policy.source_review_sha256[]") for item in _items(payload["source_review_sha256"], "policy.source_review_sha256"))
    enabled = tuple(_text(item, "policy.enabled_signal_codes[]") for item in _items(payload["enabled_signal_codes"], "policy.enabled_signal_codes"))
    contract_sha256 = _text(payload["contract_sha256"], "policy.contract_sha256")
    if version != 1 or status != "active":
        raise WarningPolicyError("warning policy must be active schema version 1")
    if len(weeks) != required or len(report_hashes) != required or len(review_hashes) != required:
        raise WarningPolicyError("warning policy evidence count does not match required weeks")
    starts = tuple(_week_start(week) for week in weeks)
    if any((current - previous).days != 7 for previous, current in zip(starts, starts[1:])):
        raise WarningPolicyError("warning policy source weeks must be consecutive")
    if not enabled or len(enabled) != len(set(enabled)):
        raise WarningPolicyError("warning policy must enable unique signal codes")
    return WarningPolicy(
        schema_version=version,
        status=status,
        activated_at=_aware_time(payload["activated_at"], "policy.activated_at").isoformat(),
        contract_id=_text(payload["contract_id"], "policy.contract_id"),
        contract_sha256=contract_sha256,
        required_observation_weeks=required,
        source_weeks=weeks,
        source_report_sha256=report_hashes,
        source_review_sha256=review_hashes,
        enabled_signal_codes=enabled,
    )


def apply_warning_policy(report: WeeklyCompassReport, policy: WarningPolicy) -> WeeklyCompassReport:
    if (
        policy.status != "active"
        or report.contract_id != policy.contract_id
        or report.contract_sha256 != policy.contract_sha256
    ):
        return report
    if _aware_time(report.generated_at, "report.generated_at") < _aware_time(policy.activated_at, "policy.activated_at"):
        return report
    enabled = set(policy.enabled_signal_codes)
    warnings = tuple(
        f"{signal.code}: {signal.message}"
        for signal in report.observation_signals
        if signal.code in enabled
    )
    return replace(report, warning_mode="active", automatic_warnings=warnings)
