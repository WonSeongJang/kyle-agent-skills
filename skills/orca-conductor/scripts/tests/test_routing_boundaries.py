from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType

import pytest
from pydantic import ValidationError

SCRIPT = Path(__file__).parents[1] / "routing_exploration.py"


def load_exploration() -> ModuleType:
    spec = importlib.util.spec_from_file_location("routing_exploration_boundaries", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_routing_decision_rejects_unknown_fields() -> None:
    exploration = load_exploration()
    model = {
        "provider": "alpha",
        "family": "alpha",
        "model": "steady",
        "effort": "medium",
        "command": "alpha",
    }
    pair = {
        "developer": model,
        "reviewer": {**model, "provider": "review", "family": "review", "model": "critic"},
        "score": 200,
        "last_resort": False,
        "same_family": False,
        "reasons": [],
    }
    raw = {**pair, "ranked_pairs": [pair], "unexpected": True}

    with pytest.raises(ValidationError):
        exploration.RoutingDecision.model_validate_json(json.dumps(raw))
