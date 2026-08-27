from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from briefing_evidence.compass_contract import CompassContractError, parse_compass_contract


VALID_CONTRACT = {
    "schema_version": 1,
    "contract_id": "kyle-work-direction",
    "effective_from": "2026-06-26",
    "status": "active",
    "north_star": {
        "statement": "개인 자산 라인에서 작은 매출 또는 실제 반응 1건",
        "evidence": ["revenue", "user-response", "user-validation"],
    },
    "decision_gate": {
        "question": "완성·매출·검증에 직접 닿나?",
        "pass_when": ["finishes-current-line", "creates-market-evidence"],
    },
    "lanes": [
        {
            "id": "personal-validation",
            "kind": "primary",
            "description": "kidi에서 contents-core로 이어지는 개인 매출 검증",
            "repositories": ["kidi", "contents-core-kyle"],
            "keywords": ["매출", "사용자 검증"],
            "expected_evidence": ["revenue", "user-response"],
        },
        {
            "id": "company-maintenance",
            "kind": "maintenance",
            "description": "운영 중단 방지와 위임",
            "repositories": ["moducerti_vibe"],
            "keywords": ["인수인계", "위임"],
            "expected_evidence": ["handoff", "operational-continuity"],
        },
    ],
    "review": {"cadence_days": 7, "warning_observation_weeks": 2},
}


def markdown(contract: dict[str, object]) -> str:
    payload = json.dumps(contract, ensure_ascii=False, indent=2)
    return f"# Direction\n\n<!-- compass-contract:start -->\n```json\n{payload}\n```\n<!-- compass-contract:end -->\n"


class CompassContractTest(unittest.TestCase):
    def test_parses_complete_contract(self) -> None:
        contract = parse_compass_contract(markdown(VALID_CONTRACT))

        self.assertEqual(contract.contract_id, "kyle-work-direction")
        self.assertEqual(contract.north_star.statement, "개인 자산 라인에서 작은 매출 또는 실제 반응 1건")
        self.assertEqual([lane.id for lane in contract.lanes], ["personal-validation", "company-maintenance"])
        self.assertEqual(contract.review.cadence_days, 7)

    def test_rejects_unknown_top_level_field(self) -> None:
        invalid = {**VALID_CONTRACT, "surprise": True}

        with self.assertRaisesRegex(CompassContractError, "unknown fields: surprise"):
            parse_compass_contract(markdown(invalid))

    def test_rejects_repository_assigned_to_two_lanes(self) -> None:
        invalid = json.loads(json.dumps(VALID_CONTRACT))
        invalid["lanes"][1]["repositories"].append("kidi")

        with self.assertRaisesRegex(CompassContractError, "repository appears in multiple lanes: kidi"):
            parse_compass_contract(markdown(invalid))

    def test_rejects_duplicate_contract_blocks(self) -> None:
        source = f"{markdown(VALID_CONTRACT)}\n{markdown(VALID_CONTRACT)}"

        with self.assertRaisesRegex(CompassContractError, "exactly one compass contract"):
            parse_compass_contract(source)


if __name__ == "__main__":
    unittest.main()
