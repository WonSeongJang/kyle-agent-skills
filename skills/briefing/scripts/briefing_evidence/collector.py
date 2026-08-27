from __future__ import annotations

from dataclasses import asdict
import json
from pathlib import Path
from typing import Final

from .compass_contract import parse_compass_contract
from .documents import collect_direction, collect_previous_briefing, collect_publications, collect_repository_documents
from .git_data import GitCommandError, collect_commits, collect_worktree, discover_repository_roots, list_worktrees
from .models import (
    AssistantSnapshotEvidence,
    BundleSummary,
    CollectionConfig,
    DateWindow,
    EvidenceBundle,
    RepositoryEvidence,
    SCHEMA_VERSION,
    TypedEvidence,
)

_COMPANY_REPOSITORIES: Final = {"moducerti_vibe", "securenet-hub", "securenetImWeb", "certinumber-search"}


def _repository_evidence(
    repo: Path,
    config: CollectionConfig,
) -> tuple[RepositoryEvidence, tuple[str, ...]]:
    commits = collect_commits(repo, config.start_time, config.end_time_exclusive)
    worktrees: list[WorktreeEvidence] = []
    warnings: list[str] = []
    for record in list_worktrees(repo):
        try:
            worktrees.append(collect_worktree(record))
        except GitCommandError as error:
            warnings.append(f"Skipped unavailable worktree {record.path}: {error.stderr.strip()}")
    collected_worktrees = tuple(worktrees)
    active = bool(commits) or any(worktree.dirty for worktree in collected_worktrees)
    changed_paths = frozenset(path for commit in commits for path in commit.paths)
    documents = (
        collect_repository_documents(collected_worktrees, changed_paths, config.start_date, config.end_date)
        if active
        else ()
    )
    company = repo.name in _COMPANY_REPOSITORIES
    evidence = RepositoryEvidence(
        name=repo.name,
        root=str(repo),
        classification="company" if company else "personal",
        classification_basis="briefing company allowlist" if company else "briefing personal default",
        active=active,
        commits=commits,
        worktrees=collected_worktrees,
        documents=documents,
    )
    return evidence, tuple(warnings)


def _compass_contract(hub_root: Path):
    path = hub_root / "direction" / "2026-06-16-work-direction.md"
    return parse_compass_contract(path.read_text(encoding="utf-8"))


def _assistant_snapshot(config: CollectionConfig) -> AssistantSnapshotEvidence | None:
    if config.assistant_state_root is None:
        return None
    state_path = Path(config.assistant_state_root) / "assistant" / "state.json"
    if not state_path.exists():
        return None
    state = json.loads(state_path.read_text(encoding="utf-8"))
    notion = state["sources"]["notion"]
    return AssistantSnapshotEvidence(
        status=state["status"],
        snapshot_status=notion.get("snapshot_status"),
        source="notion",
        observed_at=notion.get("observed_at"),
        stale_reason=notion.get("stale_reason"),
        generation_hash=notion.get("generation_hash"),
    )


def collect_bundle(config: CollectionConfig) -> EvidenceBundle:
    collected = tuple(
        _repository_evidence(repo, config)
        for repo in discover_repository_roots(config.dev_root)
    )
    repositories = tuple(evidence for evidence, _ in collected)
    warnings = tuple(warning for _, repo_warnings in collected for warning in repo_warnings)
    active_repositories = tuple(repo for repo in repositories if repo.active)
    publications = collect_publications(config.hub_root)
    summary = BundleSummary(
        repository_count=len(repositories),
        active_repository_count=len(active_repositories),
        commit_count=sum(len(repo.commits) for repo in repositories),
        dirty_worktree_count=sum(worktree.dirty for repo in repositories for worktree in repo.worktrees),
        document_count=sum(len(repo.documents) for repo in repositories),
        publication_count=len(publications),
    )
    return EvidenceBundle(
        schema_version=SCHEMA_VERSION,
        generated_at=config.generated_at,
        window=DateWindow(config.start_time, config.end_time_exclusive, "Asia/Seoul"),
        summary=summary,
        repositories=repositories,
        direction=collect_direction(config.hub_root),
        compass_contract=_compass_contract(config.hub_root),
        publications=publications,
        previous_briefing=collect_previous_briefing(config.hub_root, config.generated_at[:10]),
        warnings=warnings,
        assistant_snapshot=_assistant_snapshot(config),
        commitments=(),
        schedule_summary=None,
        session_digest=None,
        daily_life_summary=None,
        diary_reflection=None,
        automation_health=None,
    )


def serializable_bundle(bundle: EvidenceBundle) -> dict[str, object]:  # noqa: OBJECT_OK
    return asdict(bundle)
