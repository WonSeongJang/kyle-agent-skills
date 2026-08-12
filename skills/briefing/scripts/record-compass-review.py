#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from briefing_evidence.private_files import write_private_json
from briefing_evidence.warning_policy import (
    build_review,
    load_json_artifact,
)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="Record a human review of one operational compass report")
    result.add_argument("--report", type=Path, required=True)
    result.add_argument("--reviewer", required=True)
    result.add_argument("--reviewed-at", required=True)
    result.add_argument("--accept", action="append", default=[])
    result.add_argument("--false-positive", action="append", default=[])
    result.add_argument(
        "--review-dir",
        type=Path,
        default=Path.home() / ".local" / "state" / "kyle-briefing" / "reviews",
    )
    return result


def main() -> int:
    arguments = parser().parse_args()
    report = load_json_artifact(str(arguments.report.expanduser().resolve()))
    try:
        review = build_review(
            report,
            reviewer=arguments.reviewer,
            reviewed_at=arguments.reviewed_at,
            accepted_signal_codes=tuple(arguments.accept),
            false_positive_signal_codes=tuple(arguments.false_positive),
        )
    except ValueError as error:
        parser().error(str(error))
    week = str(review["iso_week"])
    output = arguments.review_dir.expanduser().resolve() / f"{week}.json"
    write_private_json(output, review)
    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
