from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType

SCRIPT = Path(__file__).parents[1] / "routing_shadow.py"
CONFIG = Path(__file__).parents[2] / "references" / "routing-providers.json"


def load_shadow() -> ModuleType:
    spec = importlib.util.spec_from_file_location("routing_shadow", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_all_registered_models_declare_harness_and_task_class_priors() -> None:
    raw = json.loads(CONFIG.read_text())

    models = [model for provider in raw["providers"] for model in provider["models"]]

    assert all(isinstance(model["harness"], str) and model["harness"] for model in models)
    assert all(isinstance(model["taskClassPrior"], dict) for model in models)


def test_frontend_prior_changes_only_the_shadow_selection() -> None:
    shadow = load_shadow()
    config = shadow.RoutingConfig.model_validate(
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
                    "id": "review",
                    "models": [
                        {
                            "id": "critic",
                            "role": "reviewer",
                            "effort": "medium",
                            "harness": "claude-code",
                            "taskClassPrior": {},
                        }
                    ],
                },
            ]
        }
    )
    decision = shadow.RoutingDecision.model_validate(
        {
            "developer": {"provider": "alpha", "family": "a", "model": "steady", "effort": "medium", "command": "alpha"},
            "reviewer": {"provider": "review", "family": "r", "model": "critic", "effort": "medium", "command": "review"},
            "score": 200,
            "last_resort": False,
            "same_family": False,
            "reasons": [],
            "ranked_pairs": [
                {
                    "developer": {"provider": "alpha", "family": "a", "model": "steady", "effort": "medium", "command": "alpha"},
                    "reviewer": {"provider": "review", "family": "r", "model": "critic", "effort": "medium", "command": "review"},
                    "score": 200,
                    "last_resort": False,
                    "same_family": False,
                    "reasons": [],
                },
                {
                    "developer": {"provider": "beta", "family": "b", "model": "visual", "effort": "medium", "command": "beta"},
                    "reviewer": {"provider": "review", "family": "r", "model": "critic", "effort": "medium", "command": "review"},
                    "score": 195,
                    "last_resort": False,
                    "same_family": False,
                    "reasons": [],
                },
            ],
        }
    )

    payload = shadow.build_shadow_payload(decision, config, shadow.TaskClass.FRONTEND)

    assert payload.developer.provider == "alpha"
    assert payload.shadow.selected.developer.provider == "beta"
    assert payload.shadow.selected.developer.harness == "kiro"
    assert payload.shadow.selected.task_class_score == 10
