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
from briefing_evidence.warning_policy import (
    build_warning_policy,
    load_json_artifact,
    warning_policy_payload,
)

SEOUL = ZoneInfo("Asia/Seoul")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="Activate reviewed weekly compass warnings")
    result.add_argument("--report", type=Path, action="append", required=True)
    result.add_argument(
        "--review-dir",
        type=Path,
        default=Path.home() / ".local" / "state" / "kyle-briefing" / "reviews",
    )
    result.add_argument(
        "--output",
        type=Path,
        default=Path.home() / ".local" / "state" / "kyle-briefing" / "warning-policy.json",
    )
    result.add_argument("--as-of")
    result.add_argument("--confirm-enable", action="store_true")
    return result


def main() -> int:
    arguments = parser().parse_args()
    if not arguments.confirm_enable:
        parser().error("--confirm-enable is required after human review")
    report_paths = tuple(path.expanduser().resolve() for path in arguments.report)
    reports = tuple(load_json_artifact(str(path)) for path in report_paths)
    review_dir = arguments.review_dir.expanduser().resolve()
    reviews = tuple(
        load_json_artifact(str(review_dir / f"{report.payload['iso_week']}.json"))
        for report in reports
    )
    activated_at = arguments.as_of or datetime.now(SEOUL).isoformat()
    try:
        policy = build_warning_policy(reports, reviews, activated_at=activated_at)
    except ValueError as error:
        parser().error(str(error))
    output = arguments.output.expanduser().resolve()
    write_private_json(output, warning_policy_payload(policy))
    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
