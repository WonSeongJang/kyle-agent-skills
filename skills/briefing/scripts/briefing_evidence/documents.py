from __future__ import annotations

import re
from datetime import date
from pathlib import Path
from typing import Final

from .models import (
    DocumentEvidence,
    DocumentKind,
    HubDocumentEvidence,
    PreviousBriefingEvidence,
    PublicationEvidence,
    WorktreeEvidence,
)
from .security import MAX_PERFORMANCE_CHARS, bounded_text, file_digest, is_sensitive_path, redact_text

_VALIDATION_DIRS: Final = {"qa", "validation", "validations", "user-feedback", "experiments"}
_VALIDATION_NAME: Final = re.compile(r"(?:validation|feedback|experiment|metric|usage-log)", re.IGNORECASE)
_BRIEFING_NAME: Final = re.compile(r"^(\d{4}-\d{2}-\d{2})-briefing\.md$")


def _read_document(
    path: Path,
    kind: DocumentKind,
    worktree: Path,
    relative_path: str,
    *,
    changed_in_window: bool,
) -> DocumentEvidence:
    raw = path.read_bytes()
    content, truncated = bounded_text(raw.decode("utf-8", errors="replace"))
    return DocumentEvidence(
        kind,
        relative_path,
        str(worktree),
        file_digest(raw),
        len(raw),
        truncated,
        changed_in_window,
        content,
    )


def _is_validation_markdown(relative_path: str) -> bool:
    path = Path(relative_path)
    if path.suffix.lower() != ".md":
        return False
    lowered_parts = {part.lower() for part in path.parts}
    return bool(lowered_parts & _VALIDATION_DIRS) or bool(_VALIDATION_NAME.search(path.name))


def _daily_paths(worktree: Path, start_date: str, end_date: str) -> tuple[Path, ...]:
    daily_root = worktree / "docs" / "daily"
    if not daily_root.is_dir():
        return ()
    paths = [
        path
        for path in daily_root.glob("*/*.md")
        if start_date <= path.parent.name <= end_date
        and not is_sensitive_path(path.relative_to(worktree))
    ]
    return tuple(sorted(paths))


def collect_repository_documents(
    worktrees: tuple[WorktreeEvidence, ...],
    changed_paths: frozenset[str],
    start_date: str,
    end_date: str,
) -> tuple[DocumentEvidence, ...]:
    documents: list[DocumentEvidence] = []
    seen: set[tuple[str, str, DocumentKind]] = set()
    for worktree_evidence in worktrees:
        worktree = Path(worktree_evidence.path)
        worktree_dirty = {change.path for change in worktree_evidence.changes}
        fixed_candidates: tuple[tuple[str, DocumentKind], ...] = (
            ("TODO.md", "todo"),
            ("docs/TODO.md", "todo"),
            ("docs/phase-history.md", "phase-history"),
        )
        for relative_path, kind in fixed_candidates:
            path = worktree / relative_path
            key = (str(worktree), relative_path, kind)
            if path.is_file() and key not in seen:
                documents.append(
                    _read_document(
                        path,
                        kind,
                        worktree,
                        relative_path,
                        changed_in_window=relative_path in changed_paths or relative_path in worktree_dirty,
                    )
                )
                seen.add(key)
        for path in _daily_paths(worktree, start_date, end_date):
            relative_path = path.relative_to(worktree).as_posix()
            key = (str(worktree), relative_path, "daily")
            if key not in seen:
                documents.append(
                    _read_document(
                        path,
                        "daily",
                        worktree,
                        relative_path,
                        changed_in_window=True,
                    )
                )
                seen.add(key)
        for relative_path in sorted(changed_paths | worktree_dirty):
            if not _is_validation_markdown(relative_path):
                continue
            path = worktree / relative_path
            key = (str(worktree), relative_path, "validation")
            if path.is_file() and not is_sensitive_path(Path(relative_path)) and key not in seen:
                documents.append(
                    _read_document(
                        path,
                        "validation",
                        worktree,
                        relative_path,
                        changed_in_window=True,
                    )
                )
                seen.add(key)
    ordered = sorted(documents, key=lambda item: (item.kind, item.relative_path, item.worktree))
    unique: dict[tuple[DocumentKind, str, str], DocumentEvidence] = {}
    for document in ordered:
        key = (document.kind, document.relative_path, document.sha256)
        existing = unique.get(key)
        if existing is None or (document.changed_in_window and not existing.changed_in_window):
            unique[key] = document
    return tuple(unique.values())


def _read_hub_document(path: Path, hub_root: Path) -> HubDocumentEvidence:
    raw = path.read_bytes()
    content, truncated = bounded_text(raw.decode("utf-8", errors="replace"))
    return HubDocumentEvidence(path.relative_to(hub_root).as_posix(), file_digest(raw), len(raw), truncated, content)


def collect_direction(hub_root: Path) -> tuple[HubDocumentEvidence, ...]:
    direction_root = hub_root / "direction"
    if not direction_root.is_dir():
        return ()
    paths = sorted(
        path
        for path in direction_root.glob("*.md")
        if not is_sensitive_path(path.relative_to(hub_root))
    )
    return tuple(_read_hub_document(path, hub_root) for path in paths)


def _frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    closing = text.find("\n---", 4)
    if closing < 0:
        return {}
    values: dict[str, str] = {}
    for line in text[4:closing].splitlines():
        key, separator, value = line.partition(":")
        if not separator:
            continue
        clean = value.strip().split(" #", maxsplit=1)[0].strip().strip("'\"")
        values[key.strip()] = clean
    return values


def _section(text: str, heading: str) -> str | None:
    match = re.search(rf"(?m)^##\s+{re.escape(heading)}[^\n]*\n", text)
    if match is None:
        return None
    next_heading = re.search(r"(?m)^##\s+", text[match.end():])
    end = match.end() + next_heading.start() if next_heading is not None else len(text)
    content = redact_text(text[match.end():end].strip())
    return content[:MAX_PERFORMANCE_CHARS] if content else None


def collect_publications(hub_root: Path) -> tuple[PublicationEvidence, ...]:
    root = hub_root / "research" / "branding" / "threads-posts"
    if not root.is_dir():
        return ()
    publications: list[PublicationEvidence] = []
    for path in sorted(root.glob("*.md")):
        raw = path.read_bytes()
        text = raw.decode("utf-8", errors="replace")
        metadata = _frontmatter(text)
        posted_date = metadata.get("posted_date")
        if posted_date is not None:
            try:
                date.fromisoformat(posted_date)
            except ValueError:
                posted_date = None
        publications.append(
            PublicationEvidence(
                relative_path=path.relative_to(hub_root).as_posix(),
                title=redact_text(metadata.get("title", path.stem)),
                status=metadata.get("status", "unknown"),
                posted_date=posted_date,
                performance=_section(text, "성과"),
                sha256=file_digest(raw),
            )
        )
    return tuple(publications)


def collect_previous_briefing(hub_root: Path, as_of_date: str) -> PreviousBriefingEvidence | None:
    root = hub_root / "briefings"
    if not root.is_dir():
        return None
    candidates: list[tuple[str, Path]] = []
    for path in root.glob("*-briefing.md"):
        match = _BRIEFING_NAME.match(path.name)
        if match is not None and match.group(1) < as_of_date:
            candidates.append((match.group(1), path))
    if not candidates:
        return None
    briefing_date, path = max(candidates, key=lambda item: item[0])
    raw = path.read_bytes()
    content, truncated = bounded_text(raw.decode("utf-8", errors="replace"))
    return PreviousBriefingEvidence(
        briefing_date,
        path.relative_to(hub_root).as_posix(),
        file_digest(raw),
        len(raw),
        truncated,
        content,
    )
