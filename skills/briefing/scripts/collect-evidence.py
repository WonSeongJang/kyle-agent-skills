#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
# ─── How to run ───
# uv run scripts/collect-evidence.py --from 2026-07-29 --to 2026-07-30

from __future__ import annotations

import argparse
import sys
from datetime import date, datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from briefing_evidence import CollectionConfig, collect_bundle, serializable_bundle
from briefing_evidence.private_files import write_private_json

SEOUL = ZoneInfo("Asia/Seoul")


class ArgumentContractError(ValueError):
    pass


def parse_date(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("date must be YYYY-MM-DD") from error


def parse_as_of(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("as-of must be ISO-8601") from error
    if parsed.tzinfo is None:
        raise argparse.ArgumentTypeError("as-of must include a UTC offset")
    return parsed.astimezone(SEOUL)


def parser() -> argparse.ArgumentParser:
    today = datetime.now(SEOUL).date()
    result = argparse.ArgumentParser(description="Collect deterministic evidence for Kyle's activity briefing")
    result.add_argument("--dev-root", type=Path, default=Path.home() / "Dev")
    result.add_argument("--hub-root", type=Path, default=Path.home() / "Dev" / "kyle-hub")
    result.add_argument("--from", dest="start_date", type=parse_date, default=today - timedelta(days=14))
    result.add_argument("--to", dest="end_date", type=parse_date, default=today)
    result.add_argument("--as-of", type=parse_as_of)
    result.add_argument("--assistant-state-root", type=Path)
    result.add_argument("--output", type=Path)
    return result


def build_config(arguments: argparse.Namespace) -> CollectionConfig:
    start_date: date = arguments.start_date
    end_date: date = arguments.end_date
    if start_date > end_date:
        raise ArgumentContractError("--from must not be after --to")
    generated_at: datetime = arguments.as_of or datetime.now(SEOUL)
    start_time = datetime.combine(start_date, time.min, SEOUL)
    end_time = datetime.combine(end_date + timedelta(days=1), time.min, SEOUL)
    output_path: Path = arguments.output or (
        Path.home()
        / ".local"
        / "state"
        / "kyle-briefing"
        / "evidence"
        / f"{generated_at.strftime('%Y-%m-%dT%H%M%S%z')}.json"
    )
    return CollectionConfig(
        dev_root=arguments.dev_root.expanduser().resolve(),
        hub_root=arguments.hub_root.expanduser().resolve(),
        output_path=output_path.expanduser().resolve(),
        start_date=start_date.isoformat(),
        end_date=end_date.isoformat(),
        start_time=start_time.isoformat(),
        end_time_exclusive=end_time.isoformat(),
        generated_at=generated_at.isoformat(),
        assistant_state_root=arguments.assistant_state_root.expanduser().resolve() if arguments.assistant_state_root else None,
    )


def main() -> int:
    arguments = parser().parse_args()
    try:
        config = build_config(arguments)
    except ArgumentContractError as error:
        parser().error(str(error))
    bundle = collect_bundle(config)
    write_private_json(config.output_path, serializable_bundle(bundle))
    print(config.output_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
