from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(Path(__file__).parent))

from briefing_evidence.private_files import write_private_json
from briefing_evidence.warning_policy import canonical_json_bytes
from briefing_evidence.warning_readiness import assess_warning_readiness
from test_warning_policy import report, review

SCRIPT = SCRIPTS / "check-warning-readiness.py"
UV = shutil.which("uv")
if UV is None:
    raise RuntimeError("uv is required to run readiness tests")


def write_artifact(path: Path, payload: dict[str, object]) -> None:
    write_private_json(path, payload)


class WarningReadinessTest(unittest.TestCase):
    def test_waits_for_two_completed_operational_weeks(self) -> None:
        current = report("2026-W31", ("hold-activity",), eligible=False)

        readiness = assess_warning_readiness(
            (current,),
            (),
            checked_at="2026-07-30T18:00:00+09:00",
        )

        self.assertEqual(readiness.status, "waiting-for-operational-weeks")
        self.assertEqual(readiness.required_observation_weeks, 2)
        self.assertEqual(readiness.eligible_weeks, ())
        self.assertEqual(readiness.missing_operational_weeks, 2)
        self.assertFalse(readiness.ready_to_activate)

    def test_waits_for_human_reviews_after_two_eligible_weeks(self) -> None:
        w31 = report("2026-W31", ("hold-activity",))
        w32 = report("2026-W32", ("hold-activity",))
        r31 = review(w31, "2026-08-03T09:30:00+09:00")

        readiness = assess_warning_readiness(
            (w31, w32),
            (r31,),
            checked_at="2026-08-10T09:40:00+09:00",
        )

        self.assertEqual(readiness.status, "waiting-for-reviews")
        self.assertEqual(readiness.eligible_weeks, ("2026-W31", "2026-W32"))
        self.assertEqual(readiness.reviewed_weeks, ("2026-W31",))
        self.assertEqual(readiness.missing_review_weeks, ("2026-W32",))

    def test_becomes_ready_without_creating_policy(self) -> None:
        w31 = report("2026-W31", ("hold-activity",))
        w32 = report("2026-W32", ("hold-activity",))
        r31 = review(w31, "2026-08-03T09:30:00+09:00")
        r32 = review(w32, "2026-08-10T09:30:00+09:00")

        readiness = assess_warning_readiness(
            (w31, w32),
            (r31, r32),
            checked_at="2026-08-10T10:00:00+09:00",
        )

        self.assertEqual(readiness.status, "ready-to-activate")
        self.assertTrue(readiness.ready_to_activate)
        self.assertEqual(readiness.enabled_signal_codes, ("hold-activity",))

    def test_cli_scans_state_and_writes_private_status_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            report_dir = root / "compass"
            review_dir = root / "reviews"
            output = root / "activation-readiness.json"
            policy = root / "warning-policy.json"
            report_dir.mkdir()
            review_dir.mkdir()
            w31 = report("2026-W31", ("hold-activity",))
            w32 = report("2026-W32", ("hold-activity",))
            for artifact in (w31, w32):
                write_artifact(report_dir / f"{artifact.payload['iso_week']}.json", artifact.payload)
            for artifact in (
                review(w31, "2026-08-03T09:30:00+09:00"),
                review(w32, "2026-08-10T09:30:00+09:00"),
            ):
                write_artifact(review_dir / f"{artifact.payload['iso_week']}.json", artifact.payload)

            completed = subprocess.run(
                [
                    UV,
                    "run",
                    str(SCRIPT),
                    "--report-dir",
                    str(report_dir),
                    "--review-dir",
                    str(review_dir),
                    "--output",
                    str(output),
                    "--as-of",
                    "2026-08-10T10:00:00+09:00",
                ],
                check=True,
                capture_output=True,
                text=True,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            )

            payload = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(Path(completed.stdout.strip()).resolve(), output.resolve())
            self.assertEqual(payload["status"], "ready-to-activate")
            self.assertEqual(payload["enabled_signal_codes"], ["hold-activity"])
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertFalse(policy.exists())


if __name__ == "__main__":
    unittest.main()
