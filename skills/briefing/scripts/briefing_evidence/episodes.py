from __future__ import annotations

import hashlib
import json
import re
from collections.abc import Mapping, Sequence
from dataclasses import replace
from datetime import datetime
from typing import Final, cast

from .compass_models import LaneKind, WorkEpisode

_MAX_GAP_SECONDS: Final = 8 * 60 * 60
_CORRELATION_KEY: Final = re.compile(r"\bepisode:([a-z0-9][a-z0-9._-]*)", re.IGNORECASE)
_RESPONSE_METRIC: Final = re.compile(
    r"(?ix)(?:(\d[\d,]*)\s*(?:likes?|repl(?:y|ies)|comments?|좋아요|댓글|답글|반응)"
    r"|(?:likes?|repl(?:y|ies)|comments?|좋아요|댓글|답글|반응)\s*[:=]?\s*(\d[\d,]*))"
)
_RESULT_DOCUMENT_KINDS: Final = {"phase-history", "validation"}
_REVENUE_METRIC: Final = re.compile(
    r"(?ix)(?:(?:revenue|payment|매출|결제)\s*[:=]?\s*(?:₩|\$)?\s*(\d[\d,]*)"
    r"|(?:₩|\$)?\s*(\d[\d,]*)\s*(?:원|usd|달러)?\s*(?:revenue|payment|매출|결제))"
)
_REVENUE_COMPLETION: Final = re.compile(r"(?i)\bpayment received\b|\bpaid\b|결제 완료|매출 발생")
_EVIDENCE_TERMS: Final = {
    "user-response": ("user response", "customer response", "reply", "replies", "사용자 반응", "고객 반응", "실제 반응"),
    "user-validation": ("user validation", "customer test", "demand test", "사용자 검증", "수요 검증", "페이크 테스트"),
    "handoff": ("handoff", "인수인계", "위임"),
    "operational-continuity": ("operational continuity", "outage", "hotfix", "운영 중단", "장애"),
    "explicit-resume-decision": ("resume decision", "resume approved", "재개 결정", "재개 승인"),
}


def _mapping(value: object, location: str) -> Mapping[str, object]:
    if not isinstance(value, Mapping) or any(not isinstance(key, str) for key in value):
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


def _observed_evidence(text: str, document_kind: str | None = None) -> frozenset[str]:
    lowered = text.casefold()
    observed = {kind for kind, terms in _EVIDENCE_TERMS.items() if any(term.casefold() in lowered for term in terms)}
    if _REVENUE_COMPLETION.search(text) or any(
        int((first or second).replace(",", "")) > 0
        for first, second in _REVENUE_METRIC.findall(text)
    ):
        observed.add("revenue")
    if document_kind == "validation":
        observed.add("user-validation")
    return frozenset(observed)


def _has_positive_response_metric(performance: object) -> bool:
    if not isinstance(performance, str):
        return False
    return any(
        int((first or second).replace(",", "")) > 0
        for first, second in _RESPONSE_METRIC.findall(performance)
    )


def _document_observed_evidence(document: Mapping[str, object]) -> frozenset[str]:
    kind = _text(document["kind"], "document.kind")
    if kind not in _RESULT_DOCUMENT_KINDS or document.get("changed_in_window") is not True:
        return frozenset()
    content = _text(document["content"], "document.content")
    return _observed_evidence(content, kind)


def _lane(repository: str, text: str, contract: Mapping[str, object]) -> tuple[str, LaneKind]:
    lanes = tuple(_mapping(item, "compass_contract.lanes[]") for item in _items(contract["lanes"], "compass_contract.lanes"))
    exact = [lane for lane in lanes if repository in _texts(lane["repositories"], "lane.repositories")]
    if len(exact) == 1:
        return _text(exact[0]["id"], "lane.id"), cast(LaneKind, _text(exact[0]["kind"], "lane.kind"))
    lowered = text.casefold()
    matches = [lane for lane in lanes if any(keyword.casefold() in lowered for keyword in _texts(lane["keywords"], "lane.keywords"))]
    if len(matches) == 1:
        return _text(matches[0]["id"], "lane.id"), cast(LaneKind, _text(matches[0]["kind"], "lane.kind"))
    return "unclassified", "unclassified"


def _episode_id(repository: str, marker: object) -> str:
    canonical = json.dumps([repository, marker], ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return f"ep-{hashlib.sha256(canonical.encode()).hexdigest()[:16]}"


def _commit_episode(
    repository: str,
    classification: str,
    commits: tuple[Mapping[str, object], ...],
    documents: tuple[Mapping[str, object], ...],
    contract: Mapping[str, object],
) -> WorkEpisode:
    hashes = tuple(_text(commit["hash"], "commit.hash") for commit in commits)
    titles = tuple(_text(commit["subject"], "commit.subject") for commit in commits)
    paths = tuple(sorted({path for commit in commits for path in _texts(commit["paths"], "commit.paths")}))[:200]
    source_paths = tuple(sorted({_text(document["relative_path"], "document.relative_path") for document in documents}))
    document_text = "\n".join(_text(document["content"], "document.content") for document in documents)
    title_text = "\n".join(titles)
    lane_id, lane_kind = _lane(repository, f"{title_text}\n{' '.join(paths)}\n{document_text}", contract)
    observed: set[str] = set()
    for document in documents:
        observed.update(_document_observed_evidence(document))
    keys = frozenset(match.casefold() for match in _CORRELATION_KEY.findall(title_text))
    started_at = _text(commits[0]["authored_at"], "commit.authored_at")
    ended_at = _text(commits[-1]["authored_at"], "commit.authored_at")
    return WorkEpisode(
        id=_episode_id(repository, hashes), repository=repository, classification=classification,
        lane_id=lane_id, lane_kind=lane_kind, started_at=started_at, ended_at=ended_at,
        ongoing=False, commit_count=len(commits), commit_hashes=hashes, titles=titles,
        changed_paths=paths, dirty_change_count=0, document_count=len(documents), publication_count=0,
        correlation_keys=keys, observed_evidence=frozenset(observed), source_paths=source_paths,
        related_episode_ids=(),
    )


def _ongoing_episode(repository: str, classification: str, worktrees: tuple[Mapping[str, object], ...], contract: Mapping[str, object]) -> WorkEpisode:
    changes = tuple(_mapping(change, "worktree.changes[]") for worktree in worktrees for change in _items(worktree["changes"], "worktree.changes"))
    paths = tuple(sorted({_text(change["path"], "change.path") for change in changes}))[:200]
    heads = tuple(_text(worktree["head"], "worktree.head") for worktree in worktrees)
    lane_id, lane_kind = _lane(repository, " ".join(paths), contract)
    return WorkEpisode(
        id=_episode_id(repository, ["ongoing", heads, paths]), repository=repository, classification=classification,
        lane_id=lane_id, lane_kind=lane_kind, started_at=None, ended_at=None, ongoing=True,
        commit_count=0, commit_hashes=(), titles=("미커밋 진행 중",), changed_paths=paths,
        dirty_change_count=sum(int(worktree["change_count"]) for worktree in worktrees), document_count=0,
        publication_count=0, correlation_keys=frozenset(), observed_evidence=frozenset(),
        source_paths=tuple(_text(worktree["path"], "worktree.path") for worktree in worktrees), related_episode_ids=(),
    )


def _repository_episodes(repository: Mapping[str, object], contract: Mapping[str, object]) -> list[WorkEpisode]:
    name = _text(repository["name"], "repository.name")
    classification = _text(repository["classification"], "repository.classification")
    commits = sorted(
        (_mapping(item, "repository.commits[]") for item in _items(repository["commits"], "repository.commits")),
        key=lambda item: datetime.fromisoformat(_text(item["authored_at"], "commit.authored_at")),
    )
    groups: list[list[Mapping[str, object]]] = []
    for commit in commits:
        if not groups:
            groups.append([commit])
            continue
        previous = datetime.fromisoformat(_text(groups[-1][-1]["authored_at"], "commit.authored_at"))
        current = datetime.fromisoformat(_text(commit["authored_at"], "commit.authored_at"))
        if (current - previous).total_seconds() <= _MAX_GAP_SECONDS:
            groups[-1].append(commit)
        else:
            groups.append([commit])
    documents = tuple(_mapping(item, "repository.documents[]") for item in _items(repository["documents"], "repository.documents"))
    episodes = [_commit_episode(name, classification, tuple(group), documents if index == len(groups) - 1 else (), contract) for index, group in enumerate(groups)]
    dirty = tuple(_mapping(item, "repository.worktrees[]") for item in _items(repository["worktrees"], "repository.worktrees") if bool(_mapping(item, "worktree")["dirty"]))
    if dirty:
        ongoing = _ongoing_episode(name, classification, dirty, contract)
        if not episodes and documents:
            observed: set[str] = set()
            for document in documents:
                observed.update(_document_observed_evidence(document))
            ongoing = replace(ongoing, document_count=len(documents), observed_evidence=frozenset(observed), source_paths=tuple(sorted({_text(document["relative_path"], "document.relative_path") for document in documents})))
        episodes.append(ongoing)
    return episodes


def _attach_publications(episodes: list[WorkEpisode], evidence: Mapping[str, object], contract: Mapping[str, object]) -> list[WorkEpisode]:
    publications = tuple(_mapping(item, "publications[]") for item in _items(evidence["publications"], "publications"))
    support_lanes = tuple(
        (_text(lane["id"], "lane.id"), cast(LaneKind, _text(lane["kind"], "lane.kind")))
        for lane in (_mapping(item, "lane") for item in _items(contract["lanes"], "lanes"))
        if _text(lane["kind"], "lane.kind") == "support"
    )
    support_ids = {lane_id for lane_id, _ in support_lanes}
    window = _mapping(evidence["window"], "window")
    start_date = _text(window["start"], "window.start")[:10]
    end_date = _text(window["end"], "window.end")[:10]
    for publication in publications:
        posted_date = publication.get("posted_date")
        if (
            publication.get("status") != "posted"
            or not isinstance(posted_date, str)
            or not start_date <= posted_date < end_date
        ):
            continue
        observed = {"publication"}
        if _has_positive_response_metric(publication.get("performance")):
            observed.add("user-response")
        source = _text(publication["relative_path"], "publication.relative_path")
        candidates = [
            index
            for index, episode in enumerate(episodes)
            if episode.lane_id in support_ids
            and episode.started_at is not None
            and episode.started_at[:10] == posted_date
        ]
        if candidates:
            index = candidates[-1]
            episodes[index] = replace(
                episodes[index],
                publication_count=episodes[index].publication_count + 1,
                observed_evidence=episodes[index].observed_evidence | frozenset(observed),
                source_paths=tuple(sorted(set(episodes[index].source_paths) | {source})),
            )
            continue
        lane_id, lane_kind = support_lanes[0] if len(support_lanes) == 1 else ("unclassified", "unclassified")
        title = _text(publication["title"], "publication.title")
        occurred_at = f"{posted_date}T00:00:00+09:00"
        episodes.append(
            WorkEpisode(
                id=_episode_id("publication-ledger", [source, posted_date]),
                repository="publication-ledger",
                classification="personal",
                lane_id=lane_id,
                lane_kind=lane_kind,
                started_at=occurred_at,
                ended_at=occurred_at,
                ongoing=False,
                commit_count=0,
                commit_hashes=(),
                titles=(title,),
                changed_paths=(),
                dirty_change_count=0,
                document_count=0,
                publication_count=1,
                correlation_keys=frozenset(match.casefold() for match in _CORRELATION_KEY.findall(title)),
                observed_evidence=frozenset(observed),
                source_paths=(source,),
                related_episode_ids=(),
            )
        )
    return episodes


def _link_correlations(episodes: list[WorkEpisode]) -> tuple[WorkEpisode, ...]:
    linked: list[WorkEpisode] = []
    for episode in episodes:
        related = sorted({other.id for key in episode.correlation_keys for other in episodes if other.id != episode.id and other.repository != episode.repository and key in other.correlation_keys})
        linked.append(replace(episode, related_episode_ids=tuple(related)))
    return tuple(sorted(linked, key=lambda item: (item.started_at is None, item.started_at or "", item.repository, item.id)))


def build_work_episodes(evidence: Mapping[str, object]) -> tuple[WorkEpisode, ...]:
    contract = _mapping(evidence["compass_contract"], "compass_contract")
    episodes = [episode for raw in _items(evidence["repositories"], "repositories") for episode in _repository_episodes(_mapping(raw, "repository"), contract)]
    return _link_correlations(_attach_publications(episodes, evidence, contract))
