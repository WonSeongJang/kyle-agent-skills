from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TESTS = Path(__file__).parent
SCRIPTS = TESTS.parent / "scripts"
sys.path.insert(0, str(TESTS))

from test_work_episodes import evidence

SCRIPT = SCRIPTS / "build-weekly-compass.py"
UV = shutil.which("uv")
if UV is None:
    raise RuntimeError("uv is required to run the weekly compass tests")


class WeeklyCompassCliTest(unittest.TestCase):
    def test_writes_deterministic_private_json_and_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            evidence_path = root / "evidence.json"
            output_dir = root / "compass"
            evidence_path.write_text(json.dumps(evidence(), ensure_ascii=False), encoding="utf-8")
            command = [
                UV,
                "run",
                str(SCRIPT),
                "--evidence",
                str(evidence_path),
                "--output-dir",
                str(output_dir),
                "--operational",
            ]

            first = subprocess.run(command, check=True, capture_output=True, text=True, env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
            json_path = Path(first.stdout.strip())
            markdown_path = json_path.with_suffix(".md")
            first_json = json_path.read_bytes()
            first_markdown = markdown_path.read_bytes()
            subprocess.run(command, check=True, capture_output=True, text=True, env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})

            payload = json.loads(json_path.read_text(encoding="utf-8"))
            self.assertEqual(json_path.name, "2026-W30.json")
            self.assertEqual(json_path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(markdown_path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(output_dir.stat().st_mode & 0o777, 0o700)
            self.assertEqual(first_json, json_path.read_bytes())
            self.assertEqual(first_markdown, markdown_path.read_bytes())
            self.assertEqual(payload["warning_mode"], "observation")
            self.assertTrue(payload["period_complete"])
            self.assertTrue(payload["observation_eligible"])
            self.assertEqual(payload["automatic_warnings"], [])
            self.assertIn("주간 방향 나침반", markdown_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
