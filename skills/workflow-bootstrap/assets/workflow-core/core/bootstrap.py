from __future__ import annotations

from datetime import datetime
from pathlib import Path

from .config import RuntimeConfig


DEFAULT_TOOL_HEADER = "# {date} {tool} 작업 로그\n"


def bootstrap_project(config: RuntimeConfig) -> dict[str, object]:
    created: list[str] = []

    config.workflow_dir.mkdir(parents=True, exist_ok=True)
    config.tasks_dir.mkdir(parents=True, exist_ok=True)
    created.append(str(config.workflow_dir))
    created.append(str(config.tasks_dir))

    if config.daily.enabled and config.daily.auto_bootstrap:
        config.daily.dir.mkdir(parents=True, exist_ok=True)
        created.append(str(config.daily.dir))

        date_str = datetime.now().strftime("%Y-%m-%d")
        day_dir = config.daily.dir / date_str
        day_dir.mkdir(parents=True, exist_ok=True)
        created.append(str(day_dir))

        for tool in config.daily.tools:
            tool_file = day_dir / f"{tool}.md"
            if not tool_file.exists():
                tool_file.write_text(
                    DEFAULT_TOOL_HEADER.format(date=date_str, tool=tool),
                    encoding="utf-8",
                )
                created.append(str(tool_file))

    return {
        "project_root": str(config.project_root),
        "created_or_verified": created,
    }
