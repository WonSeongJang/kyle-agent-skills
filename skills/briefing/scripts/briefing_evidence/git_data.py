from __future__ import annotations

import subprocess
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Final

from .models import ChangeEvidence, ChangeGroupEvidence, CommitEvidence, WorktreeEvidence
from .security import redact_text

MAX_COMMIT_PATHS: Final = 200
MAX_WORKTREE_CHANGES: Final = 200
MAX_CHANGE_GROUPS: Final = 20


class GitCommandError(RuntimeError):
    def __init__(self, repo: Path, arguments: tuple[str, ...], stderr: str) -> None:
        super().__init__(f"git failed in {repo}: {' '.join(arguments)}: {stderr.strip()}")
        self.repo = repo
        self.arguments = arguments
        self.stderr = stderr


@dataclass(frozen=True, slots=True)
class WorktreeRecord:
    path: Path
    head: str
    branch: str | None


def git_text(repo: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(repo), *arguments],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise GitCommandError(repo, arguments, completed.stderr)
    return completed.stdout


def git_bytes(repo: Path, *arguments: str) -> bytes:
    completed = subprocess.run(
        ["git", "-C", str(repo), *arguments],
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise GitCommandError(repo, arguments, completed.stderr.decode("utf-8", errors="replace"))
    return completed.stdout


def discover_repository_roots(dev_root: Path) -> tuple[Path, ...]:
    roots = [
        child
        for child in dev_root.iterdir()
        if child.is_dir()
        and not child.name.startswith("_")
        and "-worktrees" not in child.name
        and (child / ".git").is_dir()
    ]
    return tuple(sorted(roots, key=lambda item: item.name.casefold()))


def list_worktrees(repo: Path) -> tuple[WorktreeRecord, ...]:
    raw = git_bytes(repo, "worktree", "list", "--porcelain", "-z")
    records: list[WorktreeRecord] = []
    fields: dict[str, str] = {}
    for token in raw.decode("utf-8", errors="surrogateescape").split("\0"):
        if not token:
            if "worktree" in fields and "HEAD" in fields:
                records.append(
                    WorktreeRecord(
                        path=Path(fields["worktree"]),
                        head=fields["HEAD"],
                        branch=fields.get("branch", "").removeprefix("refs/heads/") or None,
                    )
                )
            fields = {}
            continue
        key, _, value = token.partition(" ")
        fields[key] = value
    return tuple(sorted(records, key=lambda item: str(item.path)))


def collect_commits(repo: Path, start_time: str, end_time_exclusive: str) -> tuple[CommitEvidence, ...]:
    raw = git_text(
        repo,
        "log",
        "--all",
        "--no-merges",
        f"--since={start_time}",
        f"--until={end_time_exclusive}",
        "--format=%H%x1f%aI%x1f%s%x1e",
    )
    commits: list[CommitEvidence] = []
    seen: set[str] = set()
    for record in raw.split("\x1e"):
        stripped = record.strip()
        if not stripped:
            continue
        commit_hash, authored_at, subject = stripped.split("\x1f", maxsplit=2)
        if commit_hash in seen:
            continue
        seen.add(commit_hash)
        paths_raw = git_bytes(repo, "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", "-z", commit_hash)
        paths = tuple(sorted(path for path in paths_raw.decode("utf-8", errors="surrogateescape").split("\0") if path))
        commits.append(
            CommitEvidence(
                hash=commit_hash,
                authored_at=authored_at,
                subject=redact_text(subject),
                path_count=len(paths),
                paths_truncated=len(paths) > MAX_COMMIT_PATHS,
                paths=paths[:MAX_COMMIT_PATHS],
            )
        )
    return tuple(sorted(commits, key=lambda item: (item.authored_at, item.hash)))


def _numstat(worktree: Path, staged: bool) -> dict[str, tuple[int | None, int | None]]:
    arguments = ("diff", "--cached", "--numstat", "-z") if staged else ("diff", "--numstat", "-z")
    tokens = git_bytes(worktree, *arguments).decode("utf-8", errors="surrogateescape").split("\0")
    stats: dict[str, tuple[int | None, int | None]] = {}
    index = 0
    while index < len(tokens):
        record = tokens[index]
        index += 1
        if not record:
            continue
        additions_raw, deletions_raw, path = record.split("\t", maxsplit=2)
        if not path:
            if index + 1 >= len(tokens):
                raise ValueError(f"incomplete rename numstat in {worktree}")
            index += 1  # old path
            path = tokens[index]
            index += 1
        additions = int(additions_raw) if additions_raw.isdigit() else None
        deletions = int(deletions_raw) if deletions_raw.isdigit() else None
        stats[path] = (additions, deletions)
    return stats


def collect_worktree(record: WorktreeRecord) -> WorktreeEvidence:
    staged_stats = _numstat(record.path, staged=True)
    unstaged_stats = _numstat(record.path, staged=False)
    raw = git_bytes(record.path, "status", "--porcelain=v1", "-z", "--untracked-files=normal")
    tokens = raw.decode("utf-8", errors="surrogateescape").split("\0")
    changes: list[ChangeEvidence] = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        index += 1
        if not token:
            continue
        status = token[:2]
        path = token[3:]
        if (status[0] in {"R", "C"} or status[1] in {"R", "C"}) and index < len(tokens):
            index += 1
        staged = staged_stats.get(path)
        unstaged = unstaged_stats.get(path)
        additions_values = [value[0] for value in (staged, unstaged) if value is not None and value[0] is not None]
        deletions_values = [value[1] for value in (staged, unstaged) if value is not None and value[1] is not None]
        changes.append(
            ChangeEvidence(
                path=path,
                index_status=status[0],
                worktree_status=status[1],
                tracked=status != "??",
                additions=sum(additions_values) if additions_values else None,
                deletions=sum(deletions_values) if deletions_values else None,
            )
        )
    ordered = tuple(sorted(changes, key=lambda item: (not item.tracked, item.path)))
    prefix_counts = Counter(change.path.split("/", maxsplit=1)[0] for change in ordered)
    groups = tuple(
        ChangeGroupEvidence(path_prefix=prefix, count=count)
        for prefix, count in sorted(prefix_counts.items(), key=lambda item: (-item[1], item[0]))[:MAX_CHANGE_GROUPS]
    )
    return WorktreeEvidence(
        path=str(record.path),
        branch=record.branch,
        head=record.head,
        dirty=bool(ordered),
        change_count=len(ordered),
        changes_truncated=len(ordered) > MAX_WORKTREE_CHANGES,
        change_groups=groups,
        changes=ordered[:MAX_WORKTREE_CHANGES],
    )
