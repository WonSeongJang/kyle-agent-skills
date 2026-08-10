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
# 감독 주기적 자가 점검 깨우기(2026-08-10 B8). 이 관문에 깨우기 시험이 없으면 "감독을 깨우는
# 유일한 장치"가 검증 없이 바뀐다 — 열한 시간 정지를 만든 구멍이 정확히 그 자리다.
# companion 분리·조회 실패 fail-closed·내 판 경로 좁히기·깨우기 죽음 신고까지 이 안에서 돈다.
bash "$SKILL_ROOT/scripts/tests/test-supervisor-waker.sh"
bash -n "$SKILL_ROOT/scripts/select-routing-pair.sh"
bash -n "$SKILL_ROOT/scripts/supervisor-waker.sh"
bash -n "$SKILL_ROOT/scripts/waker-heartbeat-path.sh"
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
