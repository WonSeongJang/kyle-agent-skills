#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import cast

from briefing_evidence.private_files import write_private_json, write_private_text
from briefing_evidence.warning_policy import apply_warning_policy, load_json_artifact, parse_warning_policy
from briefing_evidence.weekly_compass import build_weekly_compass, render_weekly_compass, report_payload


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="Build a weekly direction compass from an evidence bundle")
    result.add_argument("--evidence", type=Path, required=True)
    result.add_argument(
        "--output-dir",
        type=Path,
        default=Path.home() / ".local" / "state" / "kyle-briefing" / "compass",
    )
    result.add_argument(
        "--warning-policy",
        type=Path,
        default=Path.home() / ".local" / "state" / "kyle-briefing" / "warning-policy.json",
        help="apply this policy when it exists; absent policy keeps observation mode",
    )
    result.add_argument(
        "--operational",
        action="store_true",
        help="mark a completed, post-period report as eligible for the observation history",
    )
    return result


def read_evidence(path: Path) -> Mapping[str, object]:
    try:
        parsed = cast(object, json.loads(path.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read evidence bundle {path}: {error}") from error
    if not isinstance(parsed, dict) or any(not isinstance(key, str) for key in parsed):
        raise ValueError("evidence bundle must be a JSON object")
    return cast(Mapping[str, object], parsed)


def main() -> int:
    arguments = parser().parse_args()
    evidence_path = arguments.evidence.expanduser().resolve()
    output_dir = arguments.output_dir.expanduser().resolve()
    evidence_bytes = evidence_path.read_bytes()
    report = build_weekly_compass(
        read_evidence(evidence_path),
        evidence_sha256=hashlib.sha256(evidence_bytes).hexdigest(),
        operational=arguments.operational,
    )
    policy_path = arguments.warning_policy.expanduser().resolve()
    if policy_path.exists():
        policy_artifact = load_json_artifact(str(policy_path))
        report = apply_warning_policy(report, parse_warning_policy(policy_artifact.payload))
    json_path = output_dir / f"{report.iso_week}.json"
    markdown_path = output_dir / f"{report.iso_week}.md"
    write_private_json(json_path, report_payload(report))
    write_private_text(markdown_path, render_weekly_compass(report))
    print(json_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
