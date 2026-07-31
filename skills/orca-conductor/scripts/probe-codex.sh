#!/bin/bash
# probe-codex.sh — ChatGPT/Codex 쿼터·라우팅 probe (폴백 복귀 판정용, 2026-07-22 kyle 승인 박제)
#
# 사용: probe-codex.sh [모델]          # 기본 gpt-5.6-sol
# exit: 0=정상(원 편성 복귀 가능) / 2=쿼터 소진(폴백 유지) / 3=라우팅 오류(opencodex 주입 — base_url 우회 필요) / 4=기타 실패
#
# 배경(실측 2026-07-22, rottie-daemon2 판):
# - opencodex가 codex 명령을 shim으로 바꾸고 ~/.codex/config.toml에 openai_base_url=127.0.0.1:10100을 자동 주입한다.
#   프록시에 OpenAI provider가 비활성이면 sol 호출이 404 "No enabled canonical OpenAI provider"로 죽는다.
# - 우회 레시피: 정식 바이너리(codex.opencodex-real) + -c openai_base_url 복원 플래그. 이 스크립트가 그 조합을 쓴다.

MODEL="${1:-gpt-5.6-sol}"
PROMPT="쿼터 probe다. '확인' 한 단어만 출력하라."

# 정식 바이너리 우선 (opencodex shim 우회), 없으면 codex 그대로
BIN=""
for CAND in "$HOME"/.nvm/versions/node/*/bin/codex.opencodex-real; do
  [ -x "$CAND" ] && BIN="$CAND" && break
done
[ -z "$BIN" ] && BIN="$(command -v codex.opencodex-real || command -v codex)"
[ -z "$BIN" ] && { echo "PROBE_RESULT=fail (codex 바이너리 없음)"; exit 4; }

# macOS에 timeout이 없을 수 있어 perl로 시한(90초) 처리
OUT="$(perl -e 'alarm 90; exec @ARGV' "$BIN" exec \
  --model "$MODEL" \
  -c model_reasoning_effort="low" \
  -c openai_base_url="https://chatgpt.com/backend-api/codex" \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  "$PROMPT" 2>&1)"
RC=$?

if echo "$OUT" | grep -qiE "429|too many requests|rate limit|usage limit|quota"; then
  echo "PROBE_RESULT=quota_exhausted"; echo "$OUT" | tail -3; exit 2
fi
if echo "$OUT" | grep -qiE "No enabled canonical OpenAI provider|404 Not Found"; then
  echo "PROBE_RESULT=routing_error (opencodex 주입 — 스크립트가 이미 우회 플래그를 썼는데도 실패)"; echo "$OUT" | tail -3; exit 3
fi
if [ $RC -eq 0 ] && echo "$OUT" | grep -q "확인"; then
  echo "PROBE_RESULT=ok"; exit 0
fi
echo "PROBE_RESULT=fail (rc=$RC)"; echo "$OUT" | tail -5; exit 4
