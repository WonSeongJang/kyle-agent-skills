from __future__ import annotations

import subprocess
from pathlib import Path


class WorktreeManager:
    def __init__(self, project_root: Path):
        self.project_root = project_root

    def create(self, branch_name: str) -> Path:
        worktree_path = self.project_root.parent / f"{self.project_root.name}-{branch_name}"
        if worktree_path.exists():
            return worktree_path

        existing = subprocess.run(
            ["git", "branch", "--list", branch_name],
            cwd=str(self.project_root),
            capture_output=True,
            text=True,
        )

        command = ["git", "worktree", "add"]
        if branch_name not in existing.stdout:
            command.extend(["-b", branch_name])
        command.extend([str(worktree_path), branch_name])

        subprocess.run(
            command,
            cwd=str(self.project_root),
            check=True,
            capture_output=True,
            text=True,
        )
        return worktree_path

    def remove(self, branch_name: str) -> None:
        worktree_path = self.project_root.parent / f"{self.project_root.name}-{branch_name}"
        if worktree_path.exists():
            subprocess.run(
                ["git", "worktree", "remove", str(worktree_path)],
                cwd=str(self.project_root),
                check=True,
                capture_output=True,
                text=True,
            )
