from __future__ import annotations

import subprocess
from pathlib import Path

from .config import BranchConfig, GuideConfig


def _branch_exists(project_root: Path, branch_name: str) -> bool:
    result = subprocess.run(
        ["git", "branch", "--list", branch_name],
        cwd=str(project_root),
        capture_output=True,
        text=True,
    )
    return branch_name in result.stdout


def resolve_base_branch(project_root: Path, config: BranchConfig) -> str:
    candidates = [config.base_branch, *config.fallback_branches]
    for candidate in candidates:
        if _branch_exists(project_root, candidate):
            return candidate

    result = subprocess.run(
        ["git", "branch", "--show-current"],
        cwd=str(project_root),
        capture_output=True,
        text=True,
    )
    current = result.stdout.strip()
    return current or config.base_branch


def resolve_guides(project_root: Path, config: GuideConfig) -> list[Path]:
    resolved: list[Path] = []
    for name in config.priority:
        candidate = project_root / name
        if candidate.exists():
            resolved.append(candidate)
    return resolved
