from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path


@dataclass
class Task:
    task_id: str
    title: str
    instruction: str
    created_at: str
    status: str = "created"
    branch: str = ""
    worktree_path: str = ""
    steps: list[dict[str, str]] = field(default_factory=list)

    def __post_init__(self) -> None:
        if not self.branch:
            self.branch = f"task/{self.task_id}"
        if not self.steps:
            self.steps = [
                {"name": "research", "status": "pending"},
                {"name": "index", "status": "pending"},
                {"name": "develop", "status": "pending"},
                {"name": "review", "status": "pending"},
                {"name": "merge", "status": "pending"},
            ]

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


class TaskStore:
    def __init__(self, tasks_dir: Path):
        self.tasks_dir = tasks_dir
        self.tasks_dir.mkdir(parents=True, exist_ok=True)

    def create(self, title: str, instruction: str) -> Task:
        now = datetime.now()
        task_id = f"TASK-{now.strftime('%Y%m%d')}-{now.strftime('%H%M%S')}"
        task = Task(
            task_id=task_id,
            title=title,
            instruction=instruction,
            created_at=now.isoformat(),
        )
        task_dir = self.tasks_dir / task.task_id
        task_dir.mkdir(parents=True, exist_ok=True)
        (task_dir / "state.json").write_text(
            json.dumps(task.to_dict(), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return task
