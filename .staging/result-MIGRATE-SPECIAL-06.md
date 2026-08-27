# result-MIGRATE-SPECIAL-06 — skills-repo-migration-1

## Why

특수 6개 스킬(conductor, orca-cli, orca-conductor, orchestration, payment-mor-core, payment-mor-migration)을 모두 저장소 정본(`kyle-agent-skills/skills/`) 기준으로 통일한다. 정본이 이미 존재하는 2개는 링크 검증만 하고, 원본 실물이 외부(`~/.agents/skills`, `~/.codex/skills`)에 있는 4개는 보존 이동 후 기존 4도구 소비 경로가 저장소 정본 한 곳을 읽도록 절대경로 심볼릭 링크로 연결한다.

## 측정 기준

- 측정 일시: 2026-08-12 (KST)
- 커밋 직전 HEAD: `a22684f`
- 브랜치: `refs/heads/main`
- 작업 방식: 사전 충돌 검사 → `mv` 실물 보존 이동 → 원본 자리에 절대경로 `ln -s` → 사후 검증, 실패 시 그 항목만 `unlink` + `mv`로 원상복구.

## 항목별 처리

### 검증만(이미 정본): conductor, orca-conductor

정본(`kyle-agent-skills/skills/`)이 REAL_DIR이고 `~/.claude/skills` 링크가 정확한 절대경로로 정본을 가리킴을 확인.

| 스킬 | 정본 real | claude link | tgt_correct | resolves | SKILL.md |
|---|---|---|---|---|---|
| conductor | Y | Y | Y | Y | --- |
| orca-conductor | Y | Y | Y | Y | --- |

### 보존 이행(mv): orca-cli, orchestration, payment-mor-core, payment-mor-migration

사전 충돌 검사: 원본 REAL_DIR + 정본 DST_FREE. 충돌 없음.

| 스킬 | 이전(원본 실물) | 이후(정본) | 원본 자리(절대 심볼릭 링크) |
|---|---|---|---|
| orca-cli | /Users/fw_m1/.agents/skills/orca-cli | /Users/fw_m1/Dev/kyle-agent-skills/skills/orca-cli | /Users/fw_m1/.agents/skills/orca-cli → 정본 |
| orchestration | /Users/fw_m1/.agents/skills/orchestration | /Users/fw_m1/Dev/kyle-agent-skills/skills/orchestration | /Users/fw_m1/.agents/skills/orchestration → 정본 |
| payment-mor-core | /Users/fw_m1/.codex/skills/payment-mor-core | /Users/fw_m1/Dev/kyle-agent-skills/skills/payment-mor-core | /Users/fw_m1/.codex/skills/payment-mor-core → 정본 |
| payment-mor-migration | /Users/fw_m1/.codex/skills/payment-mor-migration | /Users/fw_m1/Dev/kyle-agent-skills/skills/payment-mor-migration | /Users/fw_m1/.codex/skills/payment-mor-migration → 정본 |

정본 검증: 4개 전부 canonical_real=Y, SKILL.md 첫 줄 읽힘(`---`).

## 4도구 소비 경로 전수 검증 (이행 후)

체인: 각 소비 경로 →(기존 또는 새 심볼릭 링크)→ 저장소 정본. LINK는 모두 resolves=Y, SKILL.md 첫 줄 정상.

### `~/.claude/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| conductor | LINK(→정본 절대경로) | Y | --- |
| orca-cli | LINK(→../../.agents/skills/orca-cli → 정본) | Y | --- |
| orca-conductor | LINK(→정본 절대경로) | Y | --- |
| orchestration | LINK(→../../.agents/skills/orchestration → 정본) | Y | --- |
| payment-mor-core | LINK(→.codex/skills/payment-mor-core → 정본) | Y | --- |
| payment-mor-migration | LINK(→.codex/skills/payment-mor-migration → 정본) | Y | --- |

### `~/.codex/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| conductor | ABSENT | - | - |
| orca-cli | LINK(→.agents/skills/orca-cli → 정본) | Y | --- |
| orca-conductor | LINK(→정본 절대경로) | Y | --- |
| orchestration | LINK(→.agents/skills/orchestration → 정본) | Y | --- |
| payment-mor-core | LINK(새, →정본 절대경로) | Y | --- |
| payment-mor-migration | LINK(새, →정본 절대경로) | Y | --- |

### `~/.gjc/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| conductor | ABSENT | - | - |
| orca-cli | ABSENT | - | - |
| orca-conductor | LINK(→정본 절대경로, 원래부터) | Y | --- |
| orchestration | ABSENT | - | - |
| payment-mor-core | ABSENT | - | - |
| payment-mor-migration | ABSENT | - | - |

### `~/.agents/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| conductor | ABSENT | - | - |
| orca-cli | LINK(새, →정본 절대경로) | Y | --- |
| orca-conductor | LINK(→.claude/skills/orca-conductor → 정본) | Y | --- |
| orchestration | LINK(새, →정본 절대경로) | Y | --- |
| payment-mor-core | ABSENT | - | - |
| payment-mor-migration | ABSENT | - | - |

## 후속 복사본 범위

이 6개 특수 스킬은 원본 실물 자체를 정본으로 옮겼거나 이미 정본이었으므로, 이번 작업으로 새로운 "정본과 다른 독립 REAL 복사본" 문제가 발생하지 않았다. 기존 독립 REAL(orca-cli/orchestration의 .agents, payment-mor-core/payment-mor-migration의 .codex)은 정본으로 흡수되어 사라졌다.

남은 외부 REAL 후속 과제(일반 배치에서 누적된 것, 본 작업 범위 아님):
- agents-sdk, cloudflare, aside-browser(batch 01)
- cloudflare-email-service, durable-objects(batch 02)
- sandbox-sdk(batch 04)
- turnstile-spin(batch 05)
- vercel-react-best-practices, web-design-guidelines, web-perf, workers-best-practices, wrangler(batch 06)

## 작업 경계

- 수행: conductor/orca-conductor 링크 검증, orca-cli/orchestration/payment-mor-core/payment-mor-migration 실물 mv + 원본 자리 절대 심볼릭 링크, 결과 파일 작성, 새 정본 4개 + 결과 파일만 stage해 main 원자 커밋.
- 하지 않음: `rm`, push, 브랜치 전환, `.staging` 삭제, `registry`·`scripts`·다른 스킬 수정.
- 보존한 기존 dirty 파일: `docs/TODO.md`, `docs/kyle-inbox.md`, 추적 안 됨 `.commandcode/`.
- stage 범위: 새 정본 4개 디렉터리(orca-cli, orchestration, payment-mor-core, payment-mor-migration) + 본 결과 파일만. conductor, orca-conductor은 이미 정본 추적 중이므로 stage에서 제외(변경 없음).
