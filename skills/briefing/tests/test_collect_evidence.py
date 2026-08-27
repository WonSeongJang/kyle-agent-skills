from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "collect-evidence.py"
UV = shutil.which("uv")
if UV is None:
    raise RuntimeError("uv is required to run the evidence collector tests")
FIXED_ENV = {
    **os.environ,
    "GIT_AUTHOR_NAME": "Kyle Test",
    "GIT_AUTHOR_EMAIL": "kyle@example.test",
    "GIT_COMMITTER_NAME": "Kyle Test",
    "GIT_COMMITTER_EMAIL": "kyle@example.test",
    "GIT_AUTHOR_DATE": "2026-07-29T12:00:00+09:00",
    "GIT_COMMITTER_DATE": "2026-07-29T12:00:00+09:00",
}


def run_git(repo: Path, *args: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
        env=FIXED_ENV,
    )
    return completed.stdout


def write_file(root: Path, relative: str, content: str) -> None:
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def initialize_repo(root: Path) -> None:
    root.mkdir(parents=True)
    run_git(root, "init", "-b", "main")
    run_git(root, "config", "user.name", "Kyle Test")
    run_git(root, "config", "user.email", "kyle@example.test")


class EvidenceCollectorE2ETest(unittest.TestCase):
    def test_collects_full_activity_contract_without_secrets(self) -> None:
        # Given: two repositories, a dirty linked worktree, and every evidence kind.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            dev_root = root / "Dev"
            hub = dev_root / "kyle-hub"
            company = dev_root / "certinumber-search"
            linked = root / "orca" / "kyle-hub-worktree"
            stale = root / "orca" / "stale-worktree"
            preserved_stale = root / ".staging" / "stale-worktree"
            broken_root_worktree = dev_root / "broken-root-worktree"
            output_one = root / "bundle-one.json"
            output_two = root / "bundle-two.json"

            broken_root_worktree.mkdir(parents=True)
            write_file(broken_root_worktree, ".git", "gitdir: /missing/worktree-admin\n")
            initialize_repo(hub)
            write_file(hub, "TODO.md", "# TODO\n- [ ] Publish one post\n")
            write_file(hub, "src/in-progress.txt", "base\n")
            write_file(hub, "src/rename-me.txt", "rename fixture\n")
            write_file(hub, "docs/phase-history.md", "# Phase history\n- Shipped collector\n")
            write_file(hub, "docs/daily/2026-07-29/codex.md", "# Daily\n- Built it\n")
            write_file(hub, "docs/qa/user-validation.md", "# Validation\nTOKEN=fixture-secret\nUser passed.\n")
            write_file(hub, "direction/main.md", "# Why\nFinish one project.\n")
            write_file(
                hub,
                "direction/2026-06-16-work-direction.md",
                """# Direction

<!-- compass-contract:start -->
```json
{
  "schema_version": 1,
  "contract_id": "fixture-direction",
  "effective_from": "2026-07-01",
  "status": "active",
  "north_star": {
    "statement": "Get one user response",
    "evidence": ["user-response"]
  },
  "decision_gate": {
    "question": "Does this create evidence?",
    "pass_when": ["creates-market-evidence"]
  },
  "lanes": [
    {
      "id": "fixture-primary",
      "kind": "primary",
      "description": "Fixture primary lane",
      "repositories": ["kyle-hub"],
      "keywords": ["evidence"],
      "expected_evidence": ["user-response"]
    }
  ],
  "review": {
    "cadence_days": 7,
    "warning_observation_weeks": 2
  }
}
```
<!-- compass-contract:end -->
""",
            )
            write_file(
                hub,
                "research/branding/threads-posts/post.md",
                "---\ntitle: Shipped post\nstatus: posted\nposted_date: 2026-07-29\n---\n\n## 성과\n좋아요 12\npassword: should-not-survive\n",
            )
            write_file(hub, "briefings/2026-07-28-briefing.md", "# Old briefing\n")
            write_file(hub, "briefings/2026-07-29-briefing.md", "# Previous briefing\n")
            write_file(hub, "briefings/2026-07-30-briefing.md", "# Current briefing\n")
            run_git(hub, "add", "TODO.md", "src", "docs", "direction", "research", "briefings")
            run_git(hub, "commit", "-m", "ship personal evidence")
            run_git(hub, "worktree", "add", "-b", "feature/dirty", str(linked))
            write_file(linked, "src/in-progress.txt", "uncommitted work\n")
            run_git(linked, "mv", "src/rename-me.txt", "src/renamed.txt")
            for index in range(250):
                write_file(linked, f"generated/cache-{index:03}.bin", "generated\n")
            run_git(hub, "worktree", "add", "-b", "feature/stale", str(stale))
            preserved_stale.parent.mkdir(parents=True)
            stale.rename(preserved_stale)

            initialize_repo(company)
            write_file(company, "README.md", "# Company project\n")
            run_git(company, "add", "README.md")
            run_git(company, "commit", "-m", "ship company evidence")

            command = [
                UV,
                "run",
                str(SCRIPT),
                "--dev-root",
                str(dev_root),
                "--hub-root",
                str(hub),
                "--from",
                "2026-07-29",
                "--to",
                "2026-07-30",
                "--as-of",
                "2026-07-30T09:00:00+09:00",
            ]

            # When: the same fixed-time collection runs twice.
            subprocess.run([*command, "--output", str(output_one)], check=True)
            subprocess.run([*command, "--output", str(output_two)], check=True)
            bundle = json.loads(output_one.read_text(encoding="utf-8"))
            serialized = output_one.read_text(encoding="utf-8")

            # Then: output is deterministic and covers every declared evidence source.
            self.assertEqual(output_one.read_bytes(), output_two.read_bytes())
            self.assertEqual(bundle["schema_version"], 1)
            self.assertEqual({item["name"] for item in bundle["repositories"]}, {"certinumber-search", "kyle-hub"})
            self.assertNotIn("broken-root-worktree", {item["name"] for item in bundle["repositories"]})
            personal = next(item for item in bundle["repositories"] if item["name"] == "kyle-hub")
            self.assertEqual(personal["classification"], "personal")
            self.assertTrue(any(commit["subject"] == "ship personal evidence" for commit in personal["commits"]))
            self.assertTrue(
                any(
                    Path(worktree["path"]).resolve() == linked.resolve() and worktree["dirty"]
                    for worktree in personal["worktrees"]
                )
            )
            dirty_worktree = next(
                worktree
                for worktree in personal["worktrees"]
                if Path(worktree["path"]).resolve() == linked.resolve()
            )
            self.assertTrue(any(change["path"] == "src/in-progress.txt" for change in dirty_worktree["changes"]))
            renamed = next(change for change in dirty_worktree["changes"] if change["path"] == "src/renamed.txt")
            self.assertEqual((renamed["index_status"], renamed["additions"], renamed["deletions"]), ("R", 0, 0))
            self.assertTrue(any(change["path"] == "generated/" for change in dirty_worktree["changes"]))
            self.assertEqual(dirty_worktree["change_count"], 3)
            self.assertFalse(dirty_worktree["changes_truncated"])
            self.assertEqual(
                {document["kind"] for document in personal["documents"]},
                {"daily", "phase-history", "todo", "validation"},
            )
            self.assertEqual(bundle["compass_contract"]["contract_id"], "fixture-direction")
            self.assertEqual(bundle["direction"][0]["relative_path"], "direction/2026-06-16-work-direction.md")
            self.assertEqual(bundle["publications"][0]["status"], "posted")
            self.assertEqual(bundle["publications"][0]["posted_date"], "2026-07-29")
            self.assertEqual(bundle["previous_briefing"]["date"], "2026-07-29")
            self.assertTrue(any(str(stale) in warning for warning in bundle["warnings"]))
            self.assertNotIn("fixture-secret", serialized)
            self.assertNotIn("should-not-survive", serialized)
            self.assertIn("[REDACTED]", serialized)

    def test_collects_assistant_snapshot_state(self) -> None:
        # Given: a minimal repo and an assistant state root with a stale Notion snapshot.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            dev_root = root / "Dev"
            hub = dev_root / "kyle-hub"
            assistant_root = root / "assistant"
            initialize_repo(hub)
            write_file(
                hub,
                "direction/2026-06-16-work-direction.md",
                """# Direction

<!-- compass-contract:start -->
```json
{
  "schema_version": 1,
  "contract_id": "fixture-direction",
  "effective_from": "2026-07-01",
  "status": "active",
  "north_star": {"statement": "Get one user response", "evidence": ["user-response"]},
  "decision_gate": {"question": "Does this create evidence?", "pass_when": ["creates-market-evidence"]},
  "lanes": [{"id": "fixture-primary", "kind": "primary", "description": "Fixture primary lane", "repositories": ["kyle-hub"], "keywords": ["evidence"], "expected_evidence": ["user-response"]}],
  "review": {"cadence_days": 7, "warning_observation_weeks": 2}
}
```
<!-- compass-contract:end -->
""",
            )
            write_file(
                assistant_root,
                "assistant/state.json",
                json.dumps({
                    "schema_version": 1,
                    "run_id": "11111111-1111-4111-8111-111111111111",
                    "started_at": "2026-07-30T00:00:00.000Z",
                    "finished_at": "2026-07-30T00:00:00.000Z",
                    "status": "partial",
                    "sources": {
                        "notion": {
                            "status": "fresh-skip",
                            "observed_at": "2026-07-30T00:00:00.000Z",
                            "stale_reason": "snapshot-stale",
                            "generation_hash": "a" * 64,
                        },
                        "index": {
                            "status": "fresh-skip",
                            "observed_at": "2026-07-30T00:00:00.000Z",
                            "stale_reason": None,
                            "generation_hash": "a" * 64,
                        },
                    },
                    "last_good": {"observed_at": "2026-07-30T00:00:00.000Z", "generation_hash": "a" * 64},
                    "last_failure": None,
                }),
            )

            # When: the collector is told where the assistant state lives.
            output = root / "bundle.json"
            subprocess.run(
                [
                    UV,
                    "run",
                    str(SCRIPT),
                    "--dev-root",
                    str(dev_root),
                    "--hub-root",
                    str(hub),
                    "--assistant-state-root",
                    str(assistant_root),
                    "--from",
                    "2026-07-30",
                    "--to",
                    "2026-07-30",
                    "--as-of",
                    "2026-07-30T09:00:00+09:00",
                    "--output",
                    str(output),
                ],
                check=True,
            )
            bundle = json.loads(output.read_text(encoding="utf-8"))

            # Then: the assistant snapshot is included without inventing completion.
            self.assertEqual(bundle["assistant_snapshot"]["status"], "partial")
            self.assertEqual(bundle["assistant_snapshot"]["stale_reason"], "snapshot-stale")
            self.assertEqual(bundle["assistant_snapshot"]["source"], "notion")


if __name__ == "__main__":
    unittest.main()
