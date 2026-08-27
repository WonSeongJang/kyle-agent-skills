from __future__ import annotations

import json
import re
from datetime import date
from typing import Final, cast

from .models import CompassContract, CompassLane, CompassNorthStar, CompassReview, DecisionGate

_START: Final = "<!-- compass-contract:start -->"
_END: Final = "<!-- compass-contract:end -->"
_BLOCK: Final = re.compile(
    rf"{re.escape(_START)}\s*```json\s*(.*?)\s*```\s*{re.escape(_END)}",
    re.DOTALL,
)
_TOP_FIELDS: Final = {
    "schema_version",
    "contract_id",
    "effective_from",
    "status",
    "north_star",
    "decision_gate",
    "lanes",
    "review",
}
_LANE_KINDS: Final = {"primary", "support", "conditional", "maintenance", "hold"}
_STATUSES: Final = {"active", "superseded"}


class CompassContractError(ValueError):
    pass


def _object(value: object, location: str) -> dict[str, object]:
    if not isinstance(value, dict) or any(not isinstance(key, str) for key in value):
        raise CompassContractError(f"{location} must be an object")
    return cast(dict[str, object], value)


def _exact_fields(value: dict[str, object], expected: set[str], location: str) -> None:
    unknown = sorted(set(value) - expected)
    if unknown:
        raise CompassContractError(f"{location} unknown fields: {', '.join(unknown)}")
    missing = sorted(expected - set(value))
    if missing:
        raise CompassContractError(f"{location} missing fields: {', '.join(missing)}")


def _string(value: object, location: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise CompassContractError(f"{location} must be a non-empty string")
    return value.strip()


def _strings(value: object, location: str, *, allow_empty: bool = False) -> tuple[str, ...]:
    if not isinstance(value, list):
        raise CompassContractError(f"{location} must be an array")
    strings = tuple(_string(item, f"{location}[]") for item in value)
    if not allow_empty and not strings:
        raise CompassContractError(f"{location} must not be empty")
    if len(strings) != len(set(strings)):
        raise CompassContractError(f"{location} must not contain duplicates")
    return strings


def _positive_integer(value: object, location: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise CompassContractError(f"{location} must be an integer greater than zero")
    return value


def _north_star(value: object) -> CompassNorthStar:
    source = _object(value, "north_star")
    _exact_fields(source, {"statement", "evidence"}, "north_star")
    return CompassNorthStar(
        statement=_string(source["statement"], "north_star.statement"),
        evidence=_strings(source["evidence"], "north_star.evidence"),
    )


def _decision_gate(value: object) -> DecisionGate:
    source = _object(value, "decision_gate")
    _exact_fields(source, {"question", "pass_when"}, "decision_gate")
    return DecisionGate(
        question=_string(source["question"], "decision_gate.question"),
        pass_when=_strings(source["pass_when"], "decision_gate.pass_when"),
    )


def _lane(value: object, index: int) -> CompassLane:
    location = f"lanes[{index}]"
    source = _object(value, location)
    fields = {"id", "kind", "description", "repositories", "keywords", "expected_evidence"}
    _exact_fields(source, fields, location)
    kind = _string(source["kind"], f"{location}.kind")
    if kind not in _LANE_KINDS:
        raise CompassContractError(f"{location}.kind is unsupported: {kind}")
    repositories = _strings(source["repositories"], f"{location}.repositories", allow_empty=True)
    keywords = _strings(source["keywords"], f"{location}.keywords", allow_empty=True)
    if not repositories and not keywords:
        raise CompassContractError(f"{location} needs repositories or keywords")
    return CompassLane(
        id=_string(source["id"], f"{location}.id"),
        kind=kind,
        description=_string(source["description"], f"{location}.description"),
        repositories=repositories,
        keywords=keywords,
        expected_evidence=_strings(source["expected_evidence"], f"{location}.expected_evidence"),
    )


def _lanes(value: object) -> tuple[CompassLane, ...]:
    if not isinstance(value, list) or not value:
        raise CompassContractError("lanes must be a non-empty array")
    lanes = tuple(_lane(item, index) for index, item in enumerate(value))
    ids = [lane.id for lane in lanes]
    duplicate_ids = sorted({lane_id for lane_id in ids if ids.count(lane_id) > 1})
    if duplicate_ids:
        raise CompassContractError(f"duplicate lane ids: {', '.join(duplicate_ids)}")
    repositories = [repository for lane in lanes for repository in lane.repositories]
    duplicates = sorted({repository for repository in repositories if repositories.count(repository) > 1})
    if duplicates:
        raise CompassContractError(f"repository appears in multiple lanes: {', '.join(duplicates)}")
    return lanes


def _review(value: object) -> CompassReview:
    source = _object(value, "review")
    _exact_fields(source, {"cadence_days", "warning_observation_weeks"}, "review")
    return CompassReview(
        cadence_days=_positive_integer(source["cadence_days"], "review.cadence_days"),
        warning_observation_weeks=_positive_integer(
            source["warning_observation_weeks"],
            "review.warning_observation_weeks",
        ),
    )


def parse_compass_contract(markdown: str) -> CompassContract:
    if markdown.count(_START) != 1 or markdown.count(_END) != 1:
        raise CompassContractError("document must contain exactly one compass contract")
    matches = _BLOCK.findall(markdown)
    if len(matches) != 1:
        raise CompassContractError("document must contain exactly one compass contract")
    try:
        parsed = cast(object, json.loads(matches[0]))
    except json.JSONDecodeError as error:
        raise CompassContractError(f"compass contract is invalid JSON: {error.msg}") from error
    source = _object(parsed, "contract")
    _exact_fields(source, _TOP_FIELDS, "contract")
    version = _positive_integer(source["schema_version"], "schema_version")
    if version != 1:
        raise CompassContractError(f"unsupported schema_version: {version}")
    status = _string(source["status"], "status")
    if status not in _STATUSES:
        raise CompassContractError(f"unsupported status: {status}")
    effective_from = _string(source["effective_from"], "effective_from")
    try:
        date.fromisoformat(effective_from)
    except ValueError as error:
        raise CompassContractError("effective_from must be YYYY-MM-DD") from error
    return CompassContract(
        schema_version=version,
        contract_id=_string(source["contract_id"], "contract_id"),
        effective_from=effective_from,
        status=status,
        north_star=_north_star(source["north_star"]),
        decision_gate=_decision_gate(source["decision_gate"]),
        lanes=_lanes(source["lanes"]),
        review=_review(source["review"]),
    )
