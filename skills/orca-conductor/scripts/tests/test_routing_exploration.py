from __future__ import annotations

import importlib.util
import json
import sys
from enum import StrEnum
from pathlib import Path
from types import ModuleType

import pytest
from pydantic import BaseModel, JsonValue, ValidationError

SCRIPT = Path(__file__).parents[1] / "routing_exploration.py"


def load_exploration() -> ModuleType:
    spec = importlib.util.spec_from_file_location("routing_exploration", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def routing_config(exploration: ModuleType) -> BaseModel:
    return exploration.RoutingConfig.model_validate_json(
        json.dumps(
        {
            "providers": [
                {
                    "id": "alpha",
                    "models": [
                        {
                            "id": "steady",
                            "role": "developer",
                            "effort": "medium",
                            "harness": "codex",
                            "taskClassPrior": {},
                        }
                    ],
                },
                {
                    "id": "beta",
                    "models": [
                        {
                            "id": "visual",
                            "role": "developer",
                            "effort": "medium",
                            "harness": "kiro",
                            "taskClassPrior": {"frontend": 10},
                        }
                    ],
                },
                {
                    "id": "gamma",
                    "models": [
                        {
                            "id": "generalist",
                            "role": "developer",
                            "effort": "medium",
                            "harness": "claude-code",
                            "taskClassPrior": {"frontend": 4},
                        }
                    ],
                },
                {
                    "id": "review",
                    "models": [
                        {
                            "id": "critic",
                            "role": "reviewer",
                            "effort": "medium",
                            "harness": "codex",
                            "taskClassPrior": {},
                        }
                    ],
                },
            ]
        }
        )
    )


def routing_decision(exploration: ModuleType, alternative_score: float = 195) -> BaseModel:
    def pair(provider: str, model: str, score: float) -> JsonValue:
        return {
            "developer": {
                "provider": provider,
                "family": provider,
                "model": model,
                "effort": "medium",
                "command": provider,
            },
            "reviewer": {
                "provider": "review",
                "family": "review",
                "model": "critic",
                "effort": "medium",
                "command": "review",
            },
            "score": score,
            "last_resort": False,
            "same_family": False,
            "reasons": [],
        }

    pairs = [
        pair("alpha", "steady", 200),
        pair("beta", "visual", alternative_score),
        pair("gamma", "generalist", alternative_score - 1),
    ]
    return exploration.RoutingDecision.model_validate_json(json.dumps({**pairs[0], "ranked_pairs": pairs}))


def inside_key(exploration: ModuleType, task_class: StrEnum) -> str:
    return next(
        f"card-{index}"
        for index in range(1_000)
        if exploration.exploration_bucket(f"card-{index}", task_class) < 10
        and exploration.exploration_slot(f"card-{index}", task_class, 2) == 0
    )


def test_share_zero_preserves_the_base_pair() -> None:
    exploration = load_exploration()
    request = exploration.ExplorationRequest(
        decision=routing_decision(exploration),
        config=routing_config(exploration),
        context=exploration.ExplorationContext(
            task_class=exploration.TaskClass.FRONTEND,
            task_size=exploration.TaskSize.LIGHT,
            experiment_key="card-off",
            share_percent=0,
            risk_flags=(),
        ),
    )

    result = exploration.apply_exploration(request)

    assert result.developer.provider == "alpha"
    assert result.exploration.selected is False
    assert result.exploration.reason == exploration.ExplorationReason.SHARE_DISABLED


def test_safe_frontend_slot_uses_task_prior_alternative() -> None:
    exploration = load_exploration()
    task_class = exploration.TaskClass.FRONTEND
    request = exploration.ExplorationRequest(
        decision=routing_decision(exploration),
        config=routing_config(exploration),
        context=exploration.ExplorationContext(
            task_class=task_class,
            task_size=exploration.TaskSize.LIGHT,
            experiment_key=inside_key(exploration, task_class),
            share_percent=10,
            risk_flags=(),
            risk_assessment_complete=True,
        ),
    )

    result = exploration.apply_exploration(request)

    assert result.developer.provider == "beta"
    assert result.exploration.selected is True
    assert result.exploration.chosen.developer.harness == "kiro"


@pytest.mark.parametrize(
    ("task_class", "task_size", "risk_flags", "reason"),
    [
        ("frontend", "LIGHT", ("user_visible",), "risk_flagged"),
        ("targeted_implementation", "HEAVY", (), "unsafe_task_context"),
        ("security", "LIGHT", (), "unsafe_task_context"),
    ],
)
def test_unsafe_context_never_changes_the_pair(
    task_class: str,
    task_size: str,
    risk_flags: tuple[str, ...],
    reason: str,
) -> None:
    exploration = load_exploration()
    parsed_class = exploration.TaskClass(task_class)
    request = exploration.ExplorationRequest(
        decision=routing_decision(exploration),
        config=routing_config(exploration),
        context=exploration.ExplorationContext(
            task_class=parsed_class,
            task_size=exploration.TaskSize(task_size),
            experiment_key=inside_key(exploration, parsed_class),
            share_percent=10,
            risk_flags=tuple(exploration.RiskFlag(flag) for flag in risk_flags),
            risk_assessment_complete=True,
        ),
    )

    result = exploration.apply_exploration(request)

    assert result.developer.provider == "alpha"
    assert result.exploration.selected is False
    assert result.exploration.reason.value == reason


def test_alternative_outside_quality_gap_is_not_selected() -> None:
    exploration = load_exploration()
    task_class = exploration.TaskClass.FRONTEND
    request = exploration.ExplorationRequest(
        decision=routing_decision(exploration, alternative_score=180),
        config=routing_config(exploration),
        context=exploration.ExplorationContext(
            task_class=task_class,
            task_size=exploration.TaskSize.LIGHT,
            experiment_key=inside_key(exploration, task_class),
            share_percent=10,
            risk_flags=(),
            risk_assessment_complete=True,
        ),
    )

    result = exploration.apply_exploration(request)

    assert result.developer.provider == "alpha"
    assert result.exploration.reason == exploration.ExplorationReason.NO_SAFE_ALTERNATIVE


def test_exploration_share_cannot_exceed_ten_percent() -> None:
    exploration = load_exploration()

    with pytest.raises(ValidationError):
        exploration.ExplorationContext(
            task_class=exploration.TaskClass.QA,
            task_size=exploration.TaskSize.LIGHT,
            experiment_key="card-too-wide",
            share_percent=11,
            risk_flags=(),
        )


def test_enabled_share_requires_completed_risk_assessment() -> None:
    exploration = load_exploration()
    task_class = exploration.TaskClass.FRONTEND
    request = exploration.ExplorationRequest(
        decision=routing_decision(exploration),
        config=routing_config(exploration),
        context=exploration.ExplorationContext(
            task_class=task_class,
            task_size=exploration.TaskSize.LIGHT,
            experiment_key=inside_key(exploration, task_class),
            share_percent=10,
            risk_flags=(),
            risk_assessment_complete=False,
        ),
    )

    result = exploration.apply_exploration(request)

    assert result.developer.provider == "alpha"
    assert result.exploration.reason == exploration.ExplorationReason.RISK_ASSESSMENT_REQUIRED


@pytest.mark.parametrize(("field", "coerced"), [("score", "200"), ("last_resort", "false")])
def test_routing_boundary_rejects_coerced_primitives(field: str, coerced: str) -> None:
    exploration = load_exploration()
    raw = routing_decision(exploration).model_dump()
    raw[field] = coerced

    with pytest.raises(ValidationError):
        exploration.RoutingDecision.model_validate(raw)


def test_context_boundary_rejects_string_share() -> None:
    exploration = load_exploration()

    with pytest.raises(ValidationError):
        exploration.ExplorationContext.model_validate(
            {
                "task_class": exploration.TaskClass.QA,
                "task_size": exploration.TaskSize.LIGHT,
                "experiment_key": "strict-card",
                "share_percent": "10",
                "risk_flags": (),
            }
        )
