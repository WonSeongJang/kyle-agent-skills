#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TASK_CLASS="other"
CONFIG="$SCRIPT_DIR/../references/routing-providers.json"
ROUTER_ARGS=()
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
printf '%s\n' "$OUTPUT"
if [[ "$SHOW_HELP" == true ]]; then
  printf 'Wrapper option: --task-class [targeted_implementation|frontend|architecture|research|security|concurrency|bugfix|docs_config|qa|other] (shadow only)\n'
fi

# ---- 라우팅 원장 자동 기록 (2026-07-27 kyle 승인 시스템화) ----
# --experiment-key '[판]:카드' 인자에서 판/카드를 파싱해 routing_selected_auto 이벤트를 append.
# 실패해도 본 라우팅 결과에는 영향 없음.
if [[ $STATUS -eq 0 ]]; then
  EXP_KEY=""
  prev=""
  for a in "${ROUTER_ARGS[@]}"; do
    if [[ "$prev" == "--experiment-key" ]]; then EXP_KEY="$a"; fi
    if [[ "$a" == --experiment-key=* ]]; then EXP_KEY="${a#*=}"; fi
    prev="$a"
  done
  BOARD=$(printf '%s' "$EXP_KEY" | sed -n 's/^\[\{0,1\}\([^]:]*\)\]\{0,1\}:.*/\1/p')
  CARD=$(printf '%s' "$EXP_KEY" | sed -n 's/^[^:]*:\(.*\)/\1/p')
  LEDGER_PAYLOAD="$OUTPUT"
  if [[ "$OUTPUT" == \{* ]]; then
    SHADOW_STATUS=0
    LEDGER_PAYLOAD=$(printf '%s' "$OUTPUT" | uv run "$SCRIPT_DIR/routing_shadow.py" --config "$CONFIG" --task-class "$TASK_CLASS") || SHADOW_STATUS=$?
    if [[ $SHADOW_STATUS -ne 0 ]]; then LEDGER_PAYLOAD="$OUTPUT"; fi
  fi
  "$SCRIPT_DIR/routing-ledger-append.sh" "routing_selected_auto" "${BOARD:-unknown}" "${CARD:-unknown}" "$LEDGER_PAYLOAD" || true
fi

exit $STATUS
