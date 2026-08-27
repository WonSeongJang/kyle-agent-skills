from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from briefing_evidence.episodes import build_work_episodes
from briefing_evidence.weekly_compass import build_weekly_compass


def contract() -> dict[str, object]:
    return {
        "schema_version": 1,
        "contract_id": "fixture-direction",
        "effective_from": "2026-07-01",
        "status": "active",
        "north_star": {
            "statement": "Get one real response",
            "evidence": ["revenue", "user-response", "user-validation"],
        },
        "decision_gate": {
            "question": "Does this create evidence?",
            "pass_when": ["creates-market-evidence"],
        },
        "lanes": [
            {
                "id": "primary",
                "kind": "primary",
                "description": "Primary validation",
                "repositories": ["kidi"],
                "keywords": ["customer test"],
                "expected_evidence": ["user-validation"],
            },
            {
                "id": "support",
                "kind": "support",
                "description": "Distribution",
                "repositories": ["contents-core-kyle-thread"],
                "keywords": ["publish"],
                "expected_evidence": ["publication", "user-response"],
            },
            {
                "id": "maintenance",
                "kind": "maintenance",
                "description": "Company continuity",
                "repositories": ["moducerti_vibe"],
                "keywords": ["handoff"],
                "expected_evidence": ["handoff", "operational-continuity"],
            },
            {
                "id": "hold",
                "kind": "hold",
                "description": "Paused work",
                "repositories": ["hermes-kit"],
                "keywords": ["hermes"],
                "expected_evidence": ["explicit-resume-decision"],
            },
        ],
        "review": {"cadence_days": 7, "warning_observation_weeks": 2},
    }


def repository(
    name: str,
    commits: list[tuple[str, str]],
    *,
    dirty: bool = False,
    validation: bool = False,
) -> dict[str, object]:
    commit_items = [
        {
            "hash": hashlib.sha256(f"{name}-{index}".encode()).hexdigest(),
            "authored_at": occurred_at,
            "subject": subject,
            "path_count": 1,
            "paths_truncated": False,
            "paths": ["src/main.py"],
        }
        for index, (occurred_at, subject) in enumerate(commits)
    ]
    changes = [
        {
            "path": "src/pending.py",
            "index_status": " ",
            "worktree_status": "M",
            "tracked": True,
            "additions": 2,
            "deletions": 1,
        }
    ] if dirty else []
    documents = [
        {
            "kind": "validation",
            "relative_path": "docs/validation/customer-test.md",
            "worktree": f"/tmp/{name}",
            "sha256": "a" * 64,
            "byte_count": 32,
            "truncated": False,
            "changed_in_window": True,
            "content": "User validation completed with one customer response.",
        }
    ] if validation else []
    return {
        "name": name,
        "root": f"/tmp/{name}",
        "classification": "personal",
        "classification_basis": "fixture",
        "active": True,
        "commits": commit_items,
        "worktrees": [
            {
                "path": f"/tmp/{name}",
                "branch": "main",
                "head": "b" * 40,
                "dirty": dirty,
                "change_count": len(changes),
                "changes_truncated": False,
                "change_groups": [],
                "changes": changes,
            }
        ],
        "documents": documents,
    }


def evidence() -> dict[str, object]:
    return {
        "schema_version": 1,
        "generated_at": "2026-07-27T09:00:00+09:00",
        "window": {
            "start": "2026-07-20T00:00:00+09:00",
            "end": "2026-07-27T00:00:00+09:00",
            "timezone": "Asia/Seoul",
        },
        "summary": {},
        "repositories": [
            repository(
                "kidi",
                [
                    ("2026-07-25T09:00:00+09:00", "customer test episode:launch"),
                    ("2026-07-25T14:00:00+09:00", "record validation episode:launch"),
                    ("2026-07-26T08:00:00+09:00", "new day follow-up"),
                ],
                dirty=True,
                validation=True,
            ),
            repository(
                "contents-core-kyle-thread",
                [("2026-07-25T10:00:00+09:00", "publish episode:launch")],
            ),
            repository(
                "hermes-kit",
                [("2026-07-26T11:00:00+09:00", "build hermes dashboard")],
            ),
        ],
        "direction": [],
        "compass_contract": contract(),
        "publications": [
            {
                "relative_path": "research/branding/threads-posts/post.md",
                "title": "Launch post",
                "status": "posted",
                "posted_date": "2026-07-25",
                "performance": "12 likes and 2 replies",
                "sha256": "c" * 64,
            }
        ],
        "previous_briefing": None,
        "warnings": [],
    }


class WorkEpisodeTest(unittest.TestCase):
    def test_groups_by_time_and_keeps_dirty_work_separate(self) -> None:
        episodes = build_work_episodes(evidence())
        kidi = [episode for episode in episodes if episode.repository == "kidi"]

        self.assertEqual(len(kidi), 3)
        self.assertEqual([episode.commit_count for episode in kidi], [2, 1, 0])
        self.assertFalse(kidi[0].ongoing)
        self.assertTrue(kidi[-1].ongoing)
        self.assertIn("user-validation", kidi[1].observed_evidence | kidi[0].observed_evidence)

    def test_links_cross_repository_only_with_explicit_episode_key(self) -> None:
        episodes = build_work_episodes(evidence())
        launch = [episode for episode in episodes if "launch" in episode.correlation_keys]

        self.assertEqual({episode.repository for episode in launch}, {"kidi", "contents-core-kyle-thread"})
        self.assertTrue(all(episode.related_episode_ids for episode in launch))

    def test_exact_repository_lane_wins_over_keyword(self) -> None:
        source = evidence()
        source["repositories"][0]["commits"][0]["subject"] = "publish customer test"
        episodes = build_work_episodes(source)
        kidi = [episode for episode in episodes if episode.repository == "kidi"]

        self.assertTrue(all(episode.lane_id == "primary" for episode in kidi))

    def test_creates_standalone_publication_episode_without_support_activity(self) -> None:
        source = evidence()
        source["repositories"] = [
            item
            for item in source["repositories"]
            if item["name"] != "contents-core-kyle-thread"
        ]
        episodes = build_work_episodes(source)
        publication = next(episode for episode in episodes if episode.repository == "publication-ledger")

        self.assertEqual(publication.lane_id, "support")
        self.assertEqual(publication.publication_count, 1)
        self.assertIn("publication", publication.observed_evidence)

    def test_publication_requires_positive_response_metric(self) -> None:
        source = evidence()
        source["publications"][0]["performance"] = "성과 측정 전"
        without_metric = build_work_episodes(source)
        support_without_metric = next(episode for episode in without_metric if episode.lane_id == "support")

        self.assertNotIn("user-response", support_without_metric.observed_evidence)

        source["publications"][0]["performance"] = "좋아요 12, 댓글 2"
        with_metric = build_work_episodes(source)
        support_with_metric = next(episode for episode in with_metric if episode.lane_id == "support")

        self.assertIn("user-response", support_with_metric.observed_evidence)

    def test_commit_title_does_not_count_as_result_evidence(self) -> None:
        source = evidence()
        source["repositories"] = [
            repository(
                "kidi",
                [("2026-07-25T09:00:00+09:00", "user validation and customer response")],
            )
        ]
        source["publications"] = []

        report = build_weekly_compass(source)

        self.assertEqual(report.north_star_status, "not-observed")

    def test_rejects_window_that_crosses_iso_week(self) -> None:
        source = evidence()
        source["window"] = {
            "start": "2026-07-24T00:00:00+09:00",
            "end": "2026-07-31T00:00:00+09:00",
            "timezone": "Asia/Seoul",
        }

        with self.assertRaisesRegex(ValueError, "start Monday"):
            build_weekly_compass(source)

    def test_old_backfill_is_not_observation_eligible(self) -> None:
        source = evidence()
        source["generated_at"] = "2026-07-30T09:00:00+09:00"

        report = build_weekly_compass(source, operational=True)

        self.assertTrue(report.period_complete)
        self.assertFalse(report.observation_eligible)

    def test_company_validation_does_not_satisfy_personal_north_star(self) -> None:
        source = evidence()
        company = repository(
            "moducerti_vibe",
            [("2026-07-25T09:00:00+09:00", "operational maintenance")],
            validation=True,
        )
        company["classification"] = "company"
        source["repositories"] = [company]
        source["publications"] = []

        report = build_weekly_compass(source)

        self.assertEqual(report.north_star_status, "not-observed")

    def test_weekly_report_stays_in_observation_mode(self) -> None:
        report = build_weekly_compass(evidence())

        self.assertEqual(report.warning_mode, "observation")
        self.assertTrue(report.period_complete)
        self.assertFalse(report.observation_eligible)
        self.assertEqual(report.north_star_status, "observed")
        self.assertIn("hold-activity", {signal.code for signal in report.observation_signals})
        self.assertEqual(report.automatic_warnings, ())
        self.assertTrue(any(summary.lane_id == "primary" for summary in report.lane_summaries))


if __name__ == "__main__":
    unittest.main()
