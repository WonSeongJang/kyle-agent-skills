# result-CONSOLIDATE-COPIES — skills-repo-migration-1

## Why

저장소 정본과 이름이 겹치는 외부 REAL 독립 복사본 21곳(.codex 11, .agents 10)을 처리해, 모든 도구 소비 경로가 저장소 정본 한 곳을 읽도록 통일한다. 원본 복사본은 삭제하지 않고 `.staging/independent-skill-copies/`에 보존 이동하고, 원래 자리에 정본을 가리키는 절대경로 심볼릭 링크를 만든다.

## 측정 기준

- 측정 일시: 2026-08-12 (KST)
- 커밋 직전 HEAD: `7275e2e` (SPECIAL-06 이행 후)
- 브랜치: `refs/heads/main`
- 작업 방식: (1) 복사본 vs 정본 파일 목록·내용 해시 비교 기록 → (2) 백업 mv(충돌 시 중단) → (3) 원래 자리 절대경로 `ln -s` → (4) 사후 검증, 실패 시 `unlink` + 보존본 원위치 mv로 원상복구.

## 21곳 동일/차이 요약

비교 방식: 파일 목록 정렬 MD5 + 파일별 MD5 정렬 MD5. 21곳 전부 **IDENTICAL**(정본과 완전 동일).

### .codex 11곳 (전부 IDENTICAL)

| 스킬 | 파일 수 | copy_hash | canon_hash | 판정 |
|---|---|---|---|---|
| agents-sdk | 20 | 3bb23ff8533e | 3bb23ff8533e | IDENTICAL |
| cloudflare | 321 | 26fe06b23045 | 26fe06b23045 | IDENTICAL |
| cloudflare-email-service | 6 | 28626d842e95 | 28626d842e95 | IDENTICAL |
| durable-objects | 4 | 78906d3027ea | 78906d3027ea | IDENTICAL |
| sandbox-sdk | 3 | 8aa3a753b15c | 8aa3a753b15c | IDENTICAL |
| turnstile-spin | 32 | ce9fb5540712 | ce9fb5540712 | IDENTICAL |
| vercel-react-best-practices | 49 | c361d11d701a | c361d11d701a | IDENTICAL |
| web-design-guidelines | 1 | 3d6aa5a4d840 | 3d6aa5a4d840 | IDENTICAL |
| web-perf | 1 | 4f20e8b16b77 | 4f20e8b16b77 | IDENTICAL |
| workers-best-practices | 3 | 5a072f6c0935 | 5a072f6c0935 | IDENTICAL |
| wrangler | 1 | 76e84c314099 | 76e84c314099 | IDENTICAL |

### .agents 10곳 (전부 IDENTICAL)

| 스킬 | 파일 수 | copy_hash | canon_hash | 판정 |
|---|---|---|---|---|
| agents-sdk | 20 | 3bb23ff8533e | 3bb23ff8533e | IDENTICAL |
| aside-browser | 1 | 3da99e809693 | 3da99e809693 | IDENTICAL |
| cloudflare | 321 | 26fe06b23045 | 26fe06b23045 | IDENTICAL |
| cloudflare-email-service | 6 | 28626d842e95 | 28626d842e95 | IDENTICAL |
| durable-objects | 4 | 78906d3027ea | 78906d3027ea | IDENTICAL |
| sandbox-sdk | 3 | 8aa3a753b15c | 8aa3a753b15c | IDENTICAL |
| turnstile-spin | 32 | ce9fb5540712 | ce9fb5540712 | IDENTICAL |
| web-perf | 1 | 4f20e8b16b77 | 4f20e8b16b77 | IDENTICAL |
| workers-best-practices | 3 | 5a072f6c0935 | 5a072f6c0935 | IDENTICAL |
| wrangler | 1 | 76e84c314099 | 76e84c314099 | IDENTICAL |

## 전/후 경로 및 백업 위치

### .codex 11곳

| 스킬 | 이전(REAL 복사본) | 이후(원래 자리) | 백업 위치 |
|---|---|---|---|
| agents-sdk | /Users/fw_m1/.codex/skills/agents-sdk | 심볼릭 링크 → 정본 | /Users/fw_m1/Dev/kyle-agent-skills/.staging/independent-skill-copies/codex/agents-sdk |
| cloudflare | /Users/fw_m1/.codex/skills/cloudflare | 심볼릭 링크 → 정본 | .../independent-skill-copies/codex/cloudflare |
| cloudflare-email-service | /Users/fw_m1/.codex/skills/cloudflare-email-service | 심볼릭 링크 → 정본 | .../independent-skill-copies/codex/cloudflare-email-service |
| durable-objects | /Users/fw_m1/.codex/skills/durable-objects | 심볼릭 링크 → 정본 | .../independent-skill-copies/codex/durable-objects |
| sandbox-sdk | /Users/fw_m1/.codex/skills/sandbox-sdk | 심볼릭 링크 → 정본 | .../independent-skill-copies/codex/sandbox-sdk |
| turnstile-spin | /Users/fw_m1/.codex/skills/turnstile-spin | 심볼릭 링크 → 정본 | .../independent-skill-copies/codex/turnstile-spin |
| vercel-react-best-practices | /Users/fw_m1/.codex/skills/vercel-react-best-practices | 심볼릭 링크 → 정본 | .../independent-skill-copies/codex/vercel-react-best-practices |
| web-design-guidelines | /Users/fw_m1/.codex/skills/web-design-guidelines | 심볼릭 링크 → 정본 | .../independent-skill-copies/codex/web-design-guidelines |
| web-perf | /Users/fw_m1/.codex/skills/web-perf | 심볼릭 링크 → 정본 | .../independent-skill-copies/codex/web-perf |
| workers-best-practices | /Users/fw_m1/.codex/skills/workers-best-practices | 심볼릭 링크 → 정본 | .../independent-skill-copies/codex/workers-best-practices |
| wrangler | /Users/fw_m1/.codex/skills/wrangler | 심볼릭 링크 → 정본 | .../independent-skill-copies/codex/wrangler |

### .agents 10곳

| 스킬 | 이전(REAL 복사본) | 이후(원래 자리) | 백업 위치 |
|---|---|---|---|
| agents-sdk | /Users/fw_m1/.agents/skills/agents-sdk | 심볼릭 링크 → 정본 | .../independent-skill-copies/agents/agents-sdk |
| aside-browser | /Users/fw_m1/.agents/skills/aside-browser | 심볼릭 링크 → 정본 | .../independent-skill-copies/agents/aside-browser |
| cloudflare | /Users/fw_m1/.agents/skills/cloudflare | 심볼릭 링크 → 정본 | .../independent-skill-copies/agents/cloudflare |
| cloudflare-email-service | /Users/fw_m1/.agents/skills/cloudflare-email-service | 심볼릭 링크 → 정본 | .../independent-skill-copies/agents/cloudflare-email-service |
| durable-objects | /Users/fw_m1/.agents/skills/durable-objects | 심볼릭 링크 → 정본 | .../independent-skill-copies/agents/durable-objects |
| sandbox-sdk | /Users/fw_m1/.agents/skills/sandbox-sdk | 심볼릭 링크 → 정본 | .../independent-skill-copies/agents/sandbox-sdk |
| turnstile-spin | /Users/fw_m1/.agents/skills/turnstile-spin | 심볼릭 링크 → 정본 | .../independent-skill-copies/agents/turnstile-spin |
| web-perf | /Users/fw_m1/.agents/skills/web-perf | 심볼릭 링크 → 정본 | .../independent-skill-copies/agents/web-perf |
| workers-best-practices | /Users/fw_m1/.agents/skills/workers-best-practices | 심볼릭 링크 → 정본 | .../independent-skill-copies/agents/workers-best-practices |
| wrangler | /Users/fw_m1/.agents/skills/wrangler | 심볼릭 링크 → 정본 | .../independent-skill-copies/agents/wrangler |

## 4도구 전수 검증

64개 스킬 × 4도구 = 256개 항목 검사.

- total_entries: 256
- LINK_OK(resolves=Y + SKILL.md 읽힘): 162
- ABSENT(원래 없던 항목): 94
- REAL_RESIDUAL(잔여 독립 실물): **0**
- FAIL(resolve 실패 또는 SKILL.md 없음): 0

모든 존재 항목이 저장소 정본으로 resolve되고 SKILL.md 첫 줄을 정상 읽는다. 외부 REAL 독립 복사본 잔여 수 = 0.

## 작업 경계

- 수행: 21곳 복사본 vs 정본 해시 비교 기록, 백업 mv(보존), 원래 자리 절대 심볼릭 링크 생성, 4도구 256개 항목 전수 검증, 결과 파일 작성, 결과 파일만 stage해 main 원자 커밋.
- 하지 않음: `rm`(복사본 삭제 대신 백업 보존), push, 브랜치 전환, 정본 내용 수정, `registry`·`scripts`·다른 스킬 수정.
- 보존한 기존 dirty 파일: `docs/TODO.md`, `docs/kyle-inbox.md`, 추적 안 됨 `.commandcode/`.
- stage 범위: 본 결과 파일만(백업 디렉터리는 .staging 하위라 gitignore, 결과 파일만 `-f` stage).
- 백업 충돌: 사전 확인 결과 백업 디렉터리가 없어 충돌 없음. 21곳 전부 정상 mv.
