from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

LaneKind = Literal["primary", "support", "conditional", "maintenance", "hold", "unclassified"]
WarningMode = Literal["observation", "active"]
NorthStarStatus = Literal["observed", "not-observed"]


@dataclass(frozen=True, slots=True)
class WorkEpisode:
    id: str
    repository: str
    classification: str
    lane_id: str
    lane_kind: LaneKind
    started_at: str | None
    ended_at: str | None
    ongoing: bool
    commit_count: int
    commit_hashes: tuple[str, ...]
    titles: tuple[str, ...]
    changed_paths: tuple[str, ...]
    dirty_change_count: int
    document_count: int
    publication_count: int
    correlation_keys: frozenset[str]
    observed_evidence: frozenset[str]
    source_paths: tuple[str, ...]
    related_episode_ids: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class LaneSummary:
    lane_id: str
    lane_kind: LaneKind
    description: str
    episode_count: int
    commit_count: int
    ongoing_count: int
    publication_count: int
    observed_evidence: tuple[str, ...]
    expected_evidence: tuple[str, ...]
    evidence_status: str


@dataclass(frozen=True, slots=True)
class ObservationSignal:
    code: str
    message: str
    lane_id: str | None
    episode_ids: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class WeeklyCompassReport:
    schema_version: int
    generated_at: str
    period_start: str
    period_end_exclusive: str
    iso_week: str
    contract_id: str
    contract_sha256: str
    evidence_sha256: str
    warning_mode: WarningMode
    required_observation_weeks: int
    period_complete: bool
    observation_eligible: bool
    north_star_statement: str
    north_star_status: NorthStarStatus
    observed_evidence: tuple[str, ...]
    lane_summaries: tuple[LaneSummary, ...]
    episodes: tuple[WorkEpisode, ...]
    observation_signals: tuple[ObservationSignal, ...]
    automatic_warnings: tuple[str, ...]
