#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SKILL_ROOT="$REPO_ROOT/skills/orca-conductor"

uv run --with pytest --with 'pydantic>=2.12,<3' --with 'typer>=0.16,<1' \
  pytest -q \
  "$SKILL_ROOT/scripts/tests/test_select_routing_pair.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_shadow.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_boundaries.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_exploration.py"

bash "$SKILL_ROOT/scripts/tests/test-select-routing-wrapper.sh"
bash -n "$SKILL_ROOT/scripts/select-routing-pair.sh"
jq empty \
  "$SKILL_ROOT/references/routing-providers.json" \
  "$SKILL_ROOT/references/routing-events.schema.json"

uvx ruff check \
  "$SKILL_ROOT/scripts/routing_exploration.py" \
  "$SKILL_ROOT/scripts/routing_shadow.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_boundaries.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_exploration.py" \
  "$SKILL_ROOT/scripts/tests/test_routing_shadow.py"

uv run --with basedpyright --with 'pydantic>=2.12,<3' --with 'typer>=0.16,<1' \
  basedpyright \
  "$SKILL_ROOT/scripts/routing_exploration.py" \
  "$SKILL_ROOT/scripts/routing_shadow.py"
