#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TASK_CLASS="other"
TASK_SIZE="HEAVY"
EXPERIMENT_KEY=""
EXPLORATION_SHARE_PERCENT="0"
RISK_ASSESSMENT_COMPLETE=false
CONFIG="$SCRIPT_DIR/../references/routing-providers.json"
ROUTER_ARGS=()
RISK_FLAGS=()
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-class)
      [[ $# -ge 2 ]] || { printf 'missing value for --task-class\n' >&2; exit 2; }
      TASK_CLASS="$2"
      shift 2
      ;;
    --task-class=*)
      TASK_CLASS="${1#*=}"
      shift
      ;;
    --task-size)
      [[ $# -ge 2 ]] || { printf 'missing value for --task-size\n' >&2; exit 2; }
      TASK_SIZE=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')
      ROUTER_ARGS+=("$1" "$2")
      shift 2
      ;;
    --task-size=*)
      TASK_SIZE=$(printf '%s' "${1#*=}" | tr '[:lower:]' '[:upper:]')
      ROUTER_ARGS+=("$1")
      shift
      ;;
    --experiment-key)
      [[ $# -ge 2 ]] || { printf 'missing value for --experiment-key\n' >&2; exit 2; }
      EXPERIMENT_KEY="$2"
      ROUTER_ARGS+=("$1" "$2")
      shift 2
      ;;
    --experiment-key=*)
      EXPERIMENT_KEY="${1#*=}"
      ROUTER_ARGS+=("$1")
      shift
      ;;
    --exploration-share-percent)
      [[ $# -ge 2 ]] || { printf 'missing value for --exploration-share-percent\n' >&2; exit 2; }
      EXPLORATION_SHARE_PERCENT="$2"
      shift 2
      ;;
    --exploration-share-percent=*)
      EXPLORATION_SHARE_PERCENT="${1#*=}"
      shift
      ;;
    --risk-flag)
      [[ $# -ge 2 ]] || { printf 'missing value for --risk-flag\n' >&2; exit 2; }
      RISK_FLAGS+=("$2")
      shift 2
      ;;
    --risk-flag=*)
      RISK_FLAGS+=("${1#*=}")
      shift
      ;;
    --risk-assessment-complete)
      RISK_ASSESSMENT_COMPLETE=true
      shift
      ;;
    --config)
      [[ $# -ge 2 ]] || { printf 'missing value for --config\n' >&2; exit 2; }
      CONFIG="$2"
      ROUTER_ARGS+=("$1" "$2")
      shift 2
      ;;
    --config=*)
      CONFIG="${1#*=}"
      ROUTER_ARGS+=("$1")
      shift
      ;;
    --help|-h)
      SHOW_HELP=true
      ROUTER_ARGS+=("$1")
      shift
      ;;
    *)
      ROUTER_ARGS+=("$1")
      shift
      ;;
  esac
done

# 라우터 실행 (stdout 보존)
STATUS=0
OUTPUT=$(uv run "$SCRIPT_DIR/select_routing_pair.py" "${ROUTER_ARGS[@]}") || STATUS=$?
if [[ $STATUS -eq 0 && "$EXPLORATION_SHARE_PERCENT" != "0" ]]; then
  EXPLORATION_ARGS=(
    --config "$CONFIG"
    --task-class "$TASK_CLASS"
    --task-size "$TASK_SIZE"
    --experiment-key "$EXPERIMENT_KEY"
    --share-percent "$EXPLORATION_SHARE_PERCENT"
  )
  if [[ ${#RISK_FLAGS[@]} -gt 0 ]]; then
    for flag in "${RISK_FLAGS[@]}"; do
      EXPLORATION_ARGS+=(--risk-flag "$flag")
    done
  fi
  if [[ "$RISK_ASSESSMENT_COMPLETE" == true ]]; then
    EXPLORATION_ARGS+=(--risk-assessment-complete)
  fi
  OUTPUT=$(printf '%s' "$OUTPUT" | uv run "$SCRIPT_DIR/routing_exploration.py" "${EXPLORATION_ARGS[@]}") || STATUS=$?
fi
printf '%s\n' "$OUTPUT"
if [[ "$SHOW_HELP" == true ]]; then
  printf 'Wrapper options: --task-class <class>, --exploration-share-percent <0..10>, --risk-flag <flag>, --risk-assessment-complete\n'
fi

# ---- 라우팅 원장 자동 기록 (2026-07-27 kyle 승인 시스템화) ----
# --experiment-key '[판]:카드' 인자에서 판/카드를 파싱해 routing_selected_auto 이벤트를 append.
# 실패해도 본 라우팅 결과에는 영향 없음.
if [[ $STATUS -eq 0 ]]; then
  BOARD=$(printf '%s' "$EXPERIMENT_KEY" | sed -n 's/^\[\{0,1\}\([^]:]*\)\]\{0,1\}:.*/\1/p')
  CARD=$(printf '%s' "$EXPERIMENT_KEY" | sed -n 's/^[^:]*:\(.*\)/\1/p')
  LEDGER_PAYLOAD="$OUTPUT"
  if [[ "$OUTPUT" == \{* ]]; then
    SHADOW_STATUS=0
    LEDGER_PAYLOAD=$(printf '%s' "$OUTPUT" | uv run "$SCRIPT_DIR/routing_shadow.py" --config "$CONFIG" --task-class "$TASK_CLASS") || SHADOW_STATUS=$?
    if [[ $SHADOW_STATUS -ne 0 ]]; then LEDGER_PAYLOAD="$OUTPUT"; fi
  fi
  "$SCRIPT_DIR/routing-ledger-append.sh" "routing_selected_auto" "${BOARD:-unknown}" "${CARD:-unknown}" "$LEDGER_PAYLOAD" || true
fi

exit $STATUS
