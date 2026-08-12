from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Final, Literal

Classification = Literal["company", "personal"]
DocumentKind = Literal["daily", "phase-history", "todo", "validation"]
CompassLaneKind = Literal["primary", "support", "conditional", "maintenance", "hold"]
CompassStatus = Literal["active", "superseded"]

SCHEMA_VERSION: Final = 1


@dataclass(frozen=True, slots=True)
class CollectionConfig:
    dev_root: Path
    hub_root: Path
    output_path: Path
    assistant_state_root: Path | None
    start_date: str
    end_date: str
    start_time: str
    end_time_exclusive: str
    generated_at: str


@dataclass(frozen=True, slots=True)
class CommitEvidence:
    hash: str
    authored_at: str
    subject: str
    path_count: int
    paths_truncated: bool
    paths: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class ChangeEvidence:
    path: str
    index_status: str
    worktree_status: str
    tracked: bool
    additions: int | None
    deletions: int | None


@dataclass(frozen=True, slots=True)
class ChangeGroupEvidence:
    path_prefix: str
    count: int


@dataclass(frozen=True, slots=True)
class WorktreeEvidence:
    path: str
    branch: str | None
    head: str
    dirty: bool
    change_count: int
    changes_truncated: bool
    change_groups: tuple[ChangeGroupEvidence, ...]
    changes: tuple[ChangeEvidence, ...]


@dataclass(frozen=True, slots=True)
class DocumentEvidence:
    kind: DocumentKind
    relative_path: str
    worktree: str
    sha256: str
    byte_count: int
    truncated: bool
    changed_in_window: bool
    content: str


@dataclass(frozen=True, slots=True)
class RepositoryEvidence:
    name: str
    root: str
    classification: Classification
    classification_basis: str
    active: bool
    commits: tuple[CommitEvidence, ...]
    worktrees: tuple[WorktreeEvidence, ...]
    documents: tuple[DocumentEvidence, ...]


@dataclass(frozen=True, slots=True)
class HubDocumentEvidence:
    relative_path: str
    sha256: str
    byte_count: int
    truncated: bool
    content: str


@dataclass(frozen=True, slots=True)
class PublicationEvidence:
    relative_path: str
    title: str
    status: str
    posted_date: str | None
    performance: str | None
    sha256: str


@dataclass(frozen=True, slots=True)
class PreviousBriefingEvidence:
    date: str
    relative_path: str
    sha256: str
    byte_count: int
    truncated: bool
    content: str


@dataclass(frozen=True, slots=True)
class BundleSummary:
    repository_count: int
    active_repository_count: int
    commit_count: int
    dirty_worktree_count: int
    document_count: int
    publication_count: int


@dataclass(frozen=True, slots=True)
class CompassNorthStar:
    statement: str
    evidence: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class DecisionGate:
    question: str
    pass_when: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class CompassLane:
    id: str
    kind: CompassLaneKind
    description: str
    repositories: tuple[str, ...]
    keywords: tuple[str, ...]
    expected_evidence: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class CompassReview:
    cadence_days: int
    warning_observation_weeks: int


@dataclass(frozen=True, slots=True)
class CompassContract:
    schema_version: int
    contract_id: str
    effective_from: str
    status: CompassStatus
    north_star: CompassNorthStar
    decision_gate: DecisionGate
    lanes: tuple[CompassLane, ...]
    review: CompassReview


@dataclass(frozen=True, slots=True)
class EvidenceBundle:
    schema_version: int
    generated_at: str
    window: DateWindow
    summary: BundleSummary
    repositories: tuple[RepositoryEvidence, ...]
    direction: tuple[HubDocumentEvidence, ...]
    compass_contract: CompassContract
    publications: tuple[PublicationEvidence, ...]
    previous_briefing: PreviousBriefingEvidence | None
    warnings: tuple[str, ...]
    assistant_snapshot: AssistantSnapshotEvidence | None
    commitments: tuple[TypedEvidence, ...]
    schedule_summary: TypedEvidence | None
    session_digest: TypedEvidence | None
    daily_life_summary: TypedEvidence | None
    diary_reflection: TypedEvidence | None
    automation_health: TypedEvidence | None


@dataclass(frozen=True, slots=True)
class DateWindow:
    start: str
    end: str
    timezone: str


@dataclass(frozen=True, slots=True)
class AssistantSnapshotEvidence:
    status: str
    snapshot_status: str | None
    source: str
    observed_at: str | None
    stale_reason: str | None
    generation_hash: str | None


@dataclass(frozen=True, slots=True)
class TypedEvidence:
    kind: str
    source: str
    status: str
    observed_at: str | None
    summary: str
    source_link: str | None
