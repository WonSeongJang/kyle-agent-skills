from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


def detect_project_root() -> Path:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
        )
        return Path(result.stdout.strip())
    except Exception:
        return Path.cwd()


def _load_override(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}

    if path.suffix == ".json":
        return json.loads(path.read_text(encoding="utf-8"))

    try:
        import yaml  # type: ignore
    except Exception:
        return {}

    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data or {}


@dataclass(frozen=True)
class DailyConfig:
    enabled: bool = True
    dir: Path = Path("docs/daily")
    auto_bootstrap: bool = True
    tools: tuple[str, ...] = ("codex", "claude", "kimi", "opencode")


@dataclass(frozen=True)
class BranchConfig:
    base_branch: str = "main"
    fallback_branches: tuple[str, ...] = ("dev",)
    prefix: str = "task/"
    merge_mode: str = "no-ff"
    delete_branch_after_merge: bool = True
    delete_worktree_after_merge: bool = True


@dataclass(frozen=True)
class GuideConfig:
    priority: tuple[str, ...] = ("AGENTS.md", "CLAUDE.md", "WORKFLOW.md")


@dataclass(frozen=True)
class AgentRuntimeConfig:
    cmd: str
    flags: tuple[str, ...]


@dataclass(frozen=True)
class RuntimeConfig:
    project_root: Path
    workflow_dir: Path
    tasks_dir: Path
    daily: DailyConfig
    branch: BranchConfig
    guides: GuideConfig
    agents: dict[str, AgentRuntimeConfig] = field(default_factory=dict)


def load_runtime_config() -> RuntimeConfig:
    root = detect_project_root()
    workflow_dir = root / "workflow"

    override = _load_override(workflow_dir / "workflow.yml")
    if not override:
        override = _load_override(workflow_dir / "workflow.json")

    daily_override = override.get("daily", {})
    branch_override = override.get("branch", {})
    guide_override = override.get("guides", {})
    agent_override = override.get("agents", {})

    daily = DailyConfig(
        enabled=daily_override.get("enabled", True),
        dir=root / daily_override.get("dir", "docs/daily"),
        auto_bootstrap=daily_override.get("auto_bootstrap", True),
        tools=tuple(daily_override.get("tools", ["codex", "claude", "kimi", "opencode"])),
    )

    branch = BranchConfig(
        base_branch=branch_override.get("base_branch", "main"),
        fallback_branches=tuple(branch_override.get("fallback_branches", ["dev"])),
        prefix=branch_override.get("prefix", "task/"),
        merge_mode=branch_override.get("merge_mode", "no-ff"),
        delete_branch_after_merge=branch_override.get("delete_branch_after_merge", True),
        delete_worktree_after_merge=branch_override.get("delete_worktree_after_merge", True),
    )

    guides = GuideConfig(
        priority=tuple(guide_override.get("priority", ["AGENTS.md", "CLAUDE.md", "WORKFLOW.md"]))
    )

    default_agents = {
        "kimi": AgentRuntimeConfig("kimi", ("--quiet", "--yolo", "-p")),
        "claude": AgentRuntimeConfig(
            "claude",
            ("--print", "--dangerously-skip-permissions", "--chrome", "-p"),
        ),
        "codex": AgentRuntimeConfig(
            "codex",
            ("exec", "--dangerously-bypass-approvals-and-sandbox"),
        ),
    }

    resolved_agents: dict[str, AgentRuntimeConfig] = {}
    for name, default in default_agents.items():
        current = agent_override.get(name, {})
        resolved_agents[name] = AgentRuntimeConfig(
            cmd=current.get("cmd", default.cmd),
            flags=tuple(current.get("flags", list(default.flags))),
        )

    return RuntimeConfig(
        project_root=root,
        workflow_dir=workflow_dir,
        tasks_dir=root / override.get("tasks_dir", "workflow/tasks"),
        daily=daily,
        branch=branch,
        guides=guides,
        agents=resolved_agents,
    )
