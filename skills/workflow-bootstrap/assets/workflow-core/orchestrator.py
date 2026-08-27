#!/usr/bin/env python3
"""
Reusable workflow orchestrator starter.

This starter keeps the public entrypoint small and delegates project-specific
choices to conventions and optional workflow overrides.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from core.bootstrap import bootstrap_project
from core.config import load_runtime_config
from core.conventions import resolve_base_branch, resolve_guides
from core.daily_logger import DailyLogger
from core.task_store import TaskStore


def cmd_bootstrap(_: argparse.Namespace) -> None:
    config = load_runtime_config()
    result = bootstrap_project(config)
    print(json.dumps(result, ensure_ascii=False, indent=2))


def cmd_config(_: argparse.Namespace) -> None:
    config = load_runtime_config()
    payload = {
        "project_root": str(config.project_root),
        "workflow_dir": str(config.workflow_dir),
        "tasks_dir": str(config.tasks_dir),
        "daily_dir": str(config.daily.dir),
        "base_branch": resolve_base_branch(config.project_root, config.branch),
        "guides": [str(p) for p in resolve_guides(config.project_root, config.guides)],
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))


def cmd_new(args: argparse.Namespace) -> None:
    config = load_runtime_config()
    store = TaskStore(config.tasks_dir)
    task = store.create(title=args.title, instruction=args.instruction)
    logger = DailyLogger(config.daily)
    logger.write(
        tool="orchestrator",
        purpose=f"[{task.task_id}] workflow task bootstrap",
        done=f"task created: {task.title}",
    )
    print(json.dumps(task.to_dict(), ensure_ascii=False, indent=2))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Reusable workflow orchestrator starter")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("bootstrap", help="Create missing workflow/docs/daily structure")
    sub.add_parser("config", help="Print resolved runtime configuration")

    new_parser = sub.add_parser("new", help="Create a task record")
    new_parser.add_argument("title")
    new_parser.add_argument("instruction")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    commands = {
        "bootstrap": cmd_bootstrap,
        "config": cmd_config,
        "new": cmd_new,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
