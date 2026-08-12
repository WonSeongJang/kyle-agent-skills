#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///

from __future__ import annotations

import argparse
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from briefing_evidence.private_files import write_private_json
from briefing_evidence.warning_policy import load_json_artifact
from briefing_evidence.warning_readiness import assess_warning_readiness, readiness_payload

SEOUL = ZoneInfo("Asia/Seoul")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="Check whether reviewed weekly reports are ready for warning activation")
    result.add_argument(
        "--report-dir",
        type=Path,
        default=Path.home() / ".local" / "state" / "kyle-briefing" / "compass",
    )
    result.add_argument(
        "--review-dir",
        type=Path,
        default=Path.home() / ".local" / "state" / "kyle-briefing" / "reviews",
    )
    result.add_argument(
        "--output",
        type=Path,
        default=Path.home() / ".local" / "state" / "kyle-briefing" / "activation-readiness.json",
    )
    result.add_argument("--as-of")
    return result


def artifacts(root: Path) -> tuple:
    if not root.is_dir():
        return ()
    return tuple(load_json_artifact(str(path)) for path in sorted(root.glob("????-W??.json")))


def main() -> int:
    arguments = parser().parse_args()
    checked_at = arguments.as_of or datetime.now(SEOUL).isoformat()
    readiness = assess_warning_readiness(
        artifacts(arguments.report_dir.expanduser().resolve()),
        artifacts(arguments.review_dir.expanduser().resolve()),
        checked_at=checked_at,
    )
    output = arguments.output.expanduser().resolve()
    write_private_json(output, readiness_payload(readiness))
    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
