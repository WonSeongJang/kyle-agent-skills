from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from dataclasses import replace
from datetime import date, timedelta
from pathlib import Path

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(Path(__file__).parent))

from briefing_evidence.warning_policy import (
    JsonArtifact,
    WarningPolicyError,
    apply_warning_policy,
    build_review,
    build_warning_policy,
    canonical_json_bytes,
    warning_policy_payload,
)
from briefing_evidence.weekly_compass import build_weekly_compass
from test_work_episodes import evidence

ACTIVATE_SCRIPT = SCRIPTS / "activate-warning-policy.py"
REVIEW_SCRIPT = SCRIPTS / "record-compass-review.py"
UV = shutil.which("uv")
if UV is None:
    raise RuntimeError("uv is required to run warning policy tests")


def _fixture_contract_sha256() -> str:
    contract = evidence()["compass_contract"]
    canonical = json.dumps(contract, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return __import__("hashlib").sha256(canonical.encode()).hexdigest()


def report(iso_week: str, signals: tuple[str, ...], *, eligible: bool = True) -> JsonArtifact:
    year, week = (int(part) for part in iso_week.replace("W", "").split("-"))
    monday = date.fromisocalendar(year, week, 1)
    payload: dict[str, object] = {
        "schema_version": 1,
        "iso_week": iso_week,
        "contract_id": "fixture-direction",
        "contract_sha256": _fixture_contract_sha256(),
        "period_start": f"{monday.isoformat()}T00:00:00+09:00",
        "period_end_exclusive": f"{(monday + timedelta(days=7)).isoformat()}T00:00:00+09:00",
        "warning_mode": "observation",
        "required_observation_weeks": 2,
        "observation_eligible": eligible,
        "observation_signals": [
            {"code": code, "message": f"{code} observed", "lane_id": None, "episode_ids": []}
            for code in signals
        ],
        "automatic_warnings": [],
    }
    raw = canonical_json_bytes(payload)
    return JsonArtifact(payload=payload, sha256=__import__("hashlib").sha256(raw).hexdigest())


def review(artifact: JsonArtifact, reviewed_at: str, *, false_positive: tuple[str, ...] = ()) -> JsonArtifact:
    signal_codes = tuple(item["code"] for item in artifact.payload["observation_signals"])
    accepted = tuple(code for code in signal_codes if code not in false_positive)
    payload = build_review(
        artifact,
        reviewer="kyle",
        reviewed_at=reviewed_at,
        accepted_signal_codes=accepted,
        false_positive_signal_codes=false_positive,
    )
    raw = canonical_json_bytes(payload)
    return JsonArtifact(payload=payload, sha256=__import__("hashlib").sha256(raw).hexdigest())


class WarningPolicyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.w31 = report("2026-W31", ("hold-activity", "unclassified-activity"))
        self.w32 = report("2026-W32", ("hold-activity", "unclassified-activity"))
        self.r31 = review(self.w31, "2026-08-03T09:30:00+09:00", false_positive=("unclassified-activity",))
        self.r32 = review(self.w32, "2026-08-10T09:30:00+09:00", false_positive=("unclassified-activity",))

    def test_enables_only_signal_accepted_in_every_reviewed_week(self) -> None:
        policy = build_warning_policy(
            (self.w31, self.w32),
            (self.r31, self.r32),
            activated_at="2026-08-10T10:00:00+09:00",
        )

        self.assertEqual(policy.source_weeks, ("2026-W31", "2026-W32"))
        self.assertEqual(policy.contract_sha256, _fixture_contract_sha256())
        self.assertEqual(policy.enabled_signal_codes, ("hold-activity",))
        self.assertEqual(policy.required_observation_weeks, 2)

    def test_rejects_review_of_incomplete_week(self) -> None:
        ineligible = report("2026-W31", ("hold-activity",), eligible=False)

        with self.assertRaisesRegex(WarningPolicyError, "observation-eligible"):
            review(ineligible, "2026-08-03T09:30:00+09:00")

    def test_rejects_fewer_than_required_operational_weeks(self) -> None:
        with self.assertRaisesRegex(WarningPolicyError, "exactly 2 reviewed weeks"):
            build_warning_policy(
                (self.w31,),
                (self.r31,),
                activated_at="2026-08-10T10:00:00+09:00",
            )

    def test_rejects_backfill_or_incomplete_week(self) -> None:
        ineligible = report("2026-W31", ("hold-activity",), eligible=False)
        forged_payload = dict(self.r31.payload)
        forged_payload["report_sha256"] = ineligible.sha256
        forged_review = JsonArtifact(payload=forged_payload, sha256=self.r31.sha256)

        with self.assertRaisesRegex(WarningPolicyError, "not observation eligible"):
            build_warning_policy(
                (ineligible, self.w32),
                (forged_review, self.r32),
                activated_at="2026-08-10T10:00:00+09:00",
            )

    def test_rejects_nonconsecutive_weeks(self) -> None:
        w33 = report("2026-W33", ("hold-activity",))
        r33 = review(w33, "2026-08-17T09:30:00+09:00")

        with self.assertRaisesRegex(WarningPolicyError, "consecutive ISO weeks"):
            build_warning_policy(
                (self.w31, w33),
                (self.r31, r33),
                activated_at="2026-08-17T10:00:00+09:00",
            )

    def test_rejects_contract_fingerprint_mismatch(self) -> None:
        changed_payload = dict(self.w32.payload)
        changed_payload["contract_sha256"] = "e" * 64
        changed_raw = canonical_json_bytes(changed_payload)
        changed = JsonArtifact(payload=changed_payload, sha256=__import__("hashlib").sha256(changed_raw).hexdigest())
        changed_review = review(changed, "2026-08-10T09:30:00+09:00", false_positive=("unclassified-activity",))

        with self.assertRaisesRegex(WarningPolicyError, "same contract fingerprint"):
            build_warning_policy(
                (self.w31, changed),
                (self.r31, changed_review),
                activated_at="2026-08-10T10:00:00+09:00",
            )

    def test_rejects_review_hash_mismatch(self) -> None:
        tampered_payload = dict(self.r31.payload)
        tampered_payload["report_sha256"] = "0" * 64
        tampered = JsonArtifact(payload=tampered_payload, sha256=self.r31.sha256)

        with self.assertRaisesRegex(WarningPolicyError, "report hash mismatch"):
            build_warning_policy(
                (self.w31, self.w32),
                (tampered, self.r32),
                activated_at="2026-08-10T10:00:00+09:00",
            )

    def test_rejects_unreviewed_signal(self) -> None:
        incomplete_payload = dict(self.r31.payload)
        incomplete_payload["signal_reviews"] = {"hold-activity": "accepted"}
        incomplete = JsonArtifact(payload=incomplete_payload, sha256=self.r31.sha256)

        with self.assertRaisesRegex(WarningPolicyError, "review every signal"):
            build_warning_policy(
                (self.w31, self.w32),
                (incomplete, self.r32),
                activated_at="2026-08-10T10:00:00+09:00",
            )

    def test_policy_applies_only_to_reports_created_after_activation(self) -> None:
        policy = build_warning_policy(
            (self.w31, self.w32),
            (self.r31, self.r32),
            activated_at="2026-08-10T10:00:00+09:00",
        )
        source = evidence()
        future = replace(
            build_weekly_compass(source),
            generated_at="2026-08-11T09:00:00+09:00",
        )
        past = replace(future, generated_at="2026-08-10T09:00:00+09:00")

        active = apply_warning_policy(future, policy)
        unchanged = apply_warning_policy(past, policy)

        self.assertEqual(active.warning_mode, "active")
        self.assertTrue(any(item.startswith("hold-activity:") for item in active.automatic_warnings))
        self.assertEqual(unchanged.warning_mode, "observation")
        self.assertEqual(unchanged.automatic_warnings, ())
    def test_cli_applies_existing_policy_to_later_report(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            evidence_path = root / "evidence.json"
            output_dir = root / "compass"
            policy_path = root / "warning-policy.json"
            source = evidence()
            source["generated_at"] = "2026-08-11T09:00:00+09:00"
            evidence_path.write_text(json.dumps(source, ensure_ascii=False), encoding="utf-8")
            policy = build_warning_policy(
                (self.w31, self.w32),
                (self.r31, self.r32),
                activated_at="2026-08-10T10:00:00+09:00",
            )
            policy_path.write_bytes(canonical_json_bytes(warning_policy_payload(policy)))

            completed = subprocess.run(
                [
                    UV,
                    "run",
                    str(SCRIPTS / "build-weekly-compass.py"),
                    "--evidence",
                    str(evidence_path),
                    "--output-dir",
                    str(output_dir),
                    "--warning-policy",
                    str(policy_path),
                ],
                check=True,
                capture_output=True,
                text=True,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            )

            payload = json.loads(Path(completed.stdout.strip()).read_text(encoding="utf-8"))
            self.assertEqual(payload["warning_mode"], "active")
            self.assertTrue(any(item.startswith("hold-activity:") for item in payload["automatic_warnings"]))


class WarningPolicyCliTest(unittest.TestCase):
    def test_review_and_activation_require_explicit_complete_attestation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            report_dir = root / "compass"
            review_dir = root / "reviews"
            output = root / "warning-policy.json"
            report_dir.mkdir()
            for artifact in (report("2026-W31", ("hold-activity",)), report("2026-W32", ("hold-activity",))):
                path = report_dir / f"{artifact.payload['iso_week']}.json"
                path.write_bytes(canonical_json_bytes(artifact.payload))

            for week, reviewed_at in (("2026-W31", "2026-08-03T09:30:00+09:00"), ("2026-W32", "2026-08-10T09:30:00+09:00")):
                subprocess.run(
                    [
                        UV,
                        "run",
                        str(REVIEW_SCRIPT),
                        "--report",
                        str(report_dir / f"{week}.json"),
                        "--reviewer",
                        "kyle",
                        "--reviewed-at",
                        reviewed_at,
                        "--accept",
                        "hold-activity",
                        "--review-dir",
                        str(review_dir),
                    ],
                    check=True,
                    capture_output=True,
                    text=True,
                    env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
                )

            command = [
                UV,
                "run",
                str(ACTIVATE_SCRIPT),
                "--report",
                str(report_dir / "2026-W31.json"),
                "--report",
                str(report_dir / "2026-W32.json"),
                "--review-dir",
                str(review_dir),
                "--output",
                str(output),
                "--as-of",
                "2026-08-10T10:00:00+09:00",
            ]
            refused = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(refused.returncode, 0)
            self.assertFalse(output.exists())

            subprocess.run(
                [*command, "--confirm-enable"],
                check=True,
                capture_output=True,
                text=True,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            )
            payload = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(payload["enabled_signal_codes"], ["hold-activity"])
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertEqual(review_dir.stat().st_mode & 0o777, 0o700)


if __name__ == "__main__":
    unittest.main()
