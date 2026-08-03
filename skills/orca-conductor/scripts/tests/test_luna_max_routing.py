from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType


SCRIPT = Path(__file__).parents[1] / "select_routing_pair.py"
CONFIG = Path(__file__).parents[2] / "references" / "routing-providers.json"


def load_router() -> ModuleType:
    spec = importlib.util.spec_from_file_location("select_routing_pair_luna_max", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_luna_max_is_available_as_guarded_developer_and_reviewer() -> None:
    router = load_router()
    config = router.RoutingConfig.model_validate_json(CONFIG.read_text())
    openai = next(provider for provider in config.providers if provider.id == "openai")
    luna_max = [
        model
        for model in openai.models
        if model.id == "gpt-5.6-luna" and model.effort == "max"
    ]

    assert {model.role for model in luna_max} == {
        router.Role.DEVELOPER,
        router.Role.REVIEWER,
    }

    developer = next(model for model in luna_max if model.role is router.Role.DEVELOPER)
    reviewer = next(model for model in luna_max if model.role is router.Role.REVIEWER)

    assert developer.experimental is True
    assert developer.experiment_share_percent == 10
    assert developer.reviewer_family_allowlist == ("anthropic",)
    assert 'model_reasoning_effort="max"' in developer.command
    assert reviewer.experimental is False
    assert reviewer.quality < 97
    assert 'model_reasoning_effort="max"' in reviewer.command


def test_luna_max_developer_can_win_its_experiment_slot(tmp_path: Path) -> None:
    router = load_router()
    raw = json.loads(CONFIG.read_text())
    raw["providers"] = [
        provider
        for provider in raw["providers"]
        if provider["id"] in {"openai", "anthropic"}
    ]
    for provider in raw["providers"]:
        if provider["id"] == "openai":
            provider["models"] = [
                model
                for model in provider["models"]
                if model["id"] == "gpt-5.6-luna"
                and model["role"] == "developer"
                and model["effort"] == "max"
            ]
        else:
            provider["models"] = [
                model for model in provider["models"] if model["role"] == "reviewer"
            ]
    config_path = tmp_path / "providers.json"
    config_path.write_text(json.dumps(raw))
    config = router.RoutingConfig.model_validate_json(config_path.read_text())
    luna_max = next(
        model
        for provider in config.providers
        for model in provider.models
        if model.id == "gpt-5.6-luna"
    )
    experiment_key = next(
        f"luna-max-{index}"
        for index in range(1_000)
        if router.experiment_bucket(luna_max, f"luna-max-{index}")
        < luna_max.experiment_share_percent
    )
    now_ms = 1_785_700_000_000
    quota_json = json.dumps(
        {
            "generatedAt": now_ms,
            "reports": [
                {
                    "provider": "openai",
                    "quota": {
                        "weeklyPercent": 10,
                        "weeklyResetAt": now_ms + 5 * 86_400_000,
                    },
                },
                {
                    "provider": "anthropic",
                    "quota": {
                        "weeklyPercent": 10,
                        "weeklyResetAt": now_ms + 5 * 86_400_000,
                    },
                },
            ],
        }
    )

    decision = router.select_pair(
        router.SelectionRequest(
            config_path=config_path,
            quota_json=quota_json,
            task_size=router.TaskSize.HEAVY,
            unavailable_providers=frozenset(),
            now_ms=now_ms,
            experiment_key=experiment_key,
        )
    )

    assert decision.developer.model == "gpt-5.6-luna"
    assert decision.developer.effort == "max"
    assert decision.reviewer.family == "anthropic"
    assert "experiment_share=10" in decision.reasons


def test_luna_max_reviewer_is_a_real_fallback_candidate(tmp_path: Path) -> None:
    router = load_router()
    raw = json.loads(CONFIG.read_text())
    raw["providers"] = [
        provider
        for provider in raw["providers"]
        if provider["id"] in {"zai", "openai"}
    ]
    for provider in raw["providers"]:
        if provider["id"] == "zai":
            provider["models"] = [
                model for model in provider["models"] if model["role"] == "developer"
            ]
        else:
            provider["models"] = [
                model
                for model in provider["models"]
                if model["id"] == "gpt-5.6-luna"
                and model["role"] == "reviewer"
                and model["effort"] == "max"
            ]
    config_path = tmp_path / "providers.json"
    config_path.write_text(json.dumps(raw))
    now_ms = 1_785_700_000_000
    quota_json = json.dumps(
        {
            "generatedAt": now_ms,
            "reports": [
                {
                    "provider": "zai",
                    "quota": {},
                },
                {
                    "provider": "openai",
                    "quota": {
                        "weeklyPercent": 10,
                        "weeklyResetAt": now_ms + 5 * 86_400_000,
                    },
                },
            ],
        }
    )

    decision = router.select_pair(
        router.SelectionRequest(
            config_path=config_path,
            quota_json=quota_json,
            task_size=router.TaskSize.HEAVY,
            unavailable_providers=frozenset(),
            now_ms=now_ms,
        )
    )

    assert decision.developer.model == "zai/glm-5.2"
    assert decision.reviewer.model == "gpt-5.6-luna"
    assert decision.reviewer.effort == "max"
