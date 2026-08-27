# result-MIGRATE-BATCH-05 — skills-repo-migration-1

## Why

`~/.claude/skills`의 다섯 번째 배치 실물 스킬 디렉터리 10개를 저장소 정본(`kyle-agent-skills/skills/`)으로 옮겨 Git 추적 대상으로 만들고, 원위치는 절대경로 심볼릭 링크로 둬서 기존 도구 경로가 깨지지 않게 한다.

## 이행 배치(10개)

schema-markup-generator, seo-content-writer, serp-analysis, supabase-multi-project-ops, super-conductor, symphony-setup, technical-seo-checker, threads-trend-check, turnstile-spin, vercel-deploy-claimable

## 측정 기준

- 측정 일시: 2026-08-12 (KST)
- 커밋 직전 HEAD: `34ed65c` (배치 04 이행 후)
- 브랜치: `refs/heads/main`
- 작업 방식: 각 스킬마다 사전 충돌 검사 → `mv` 실물 이동 → 절대경로 `ln -s` → 사후 검증, 실패 시 그 항목만 `unlink` + `mv`로 원상복구.
- 사전 충돌 검사 결과: 10개 전부 SRC_DIR(실물) + DST_FREE(목적지 비었음). 충돌 없음.

## 전/후 경로 매핑

| 스킬 | 이전(실물) | 이후(정본) | 원위치(심볼릭 링크) |
|---|---|---|---|
| schema-markup-generator | /Users/fw_m1/.claude/skills/schema-markup-generator | /Users/fw_m1/Dev/kyle-agent-skills/skills/schema-markup-generator | 심볼릭 링크 → 정본 |
| seo-content-writer | /Users/fw_m1/.claude/skills/seo-content-writer | /Users/fw_m1/Dev/kyle-agent-skills/skills/seo-content-writer | 심볼릭 링크 → 정본 |
| serp-analysis | /Users/fw_m1/.claude/skills/serp-analysis | /Users/fw_m1/Dev/kyle-agent-skills/skills/serp-analysis | 심볼릭 링크 → 정본 |
| supabase-multi-project-ops | /Users/fw_m1/.claude/skills/supabase-multi-project-ops | /Users/fw_m1/Dev/kyle-agent-skills/skills/supabase-multi-project-ops | 심볼릭 링크 → 정본 |
| super-conductor | /Users/fw_m1/.claude/skills/super-conductor | /Users/fw_m1/Dev/kyle-agent-skills/skills/super-conductor | 심볼릭 링크 → 정본 |
| symphony-setup | /Users/fw_m1/.claude/skills/symphony-setup | /Users/fw_m1/Dev/kyle-agent-skills/skills/symphony-setup | 심볼릭 링크 → 정본 |
| technical-seo-checker | /Users/fw_m1/.claude/skills/technical-seo-checker | /Users/fw_m1/Dev/kyle-agent-skills/skills/technical-seo-checker | 심볼릭 링크 → 정본 |
| threads-trend-check | /Users/fw_m1/.claude/skills/threads-trend-check | /Users/fw_m1/Dev/kyle-agent-skills/skills/threads-trend-check | 심볼릭 링크 → 정본 |
| turnstile-spin | /Users/fw_m1/.claude/skills/turnstile-spin | /Users/fw_m1/Dev/kyle-agent-skills/skills/turnstile-spin | 심볼릭 링크 → 정본 |
| vercel-deploy-claimable | /Users/fw_m1/.claude/skills/vercel-deploy-claimable | /Users/fw_m1/Dev/kyle-agent-skills/skills/vercel-deploy-claimable | 심볼릭 링크 → 정본 |

## 사후 검증 (정본 + 원위치 심볼릭 링크)

10개 전부: dst_real=Y, src_link=Y, tgt_correct=Y(절대경로 정확), resolves=Y, SKILL.md 첫 줄 읽힘(`---`).

```
schema-markup-generator          dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
seo-content-writer               dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
serp-analysis                    dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
supabase-multi-project-ops       dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
super-conductor                  dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
symphony-setup                   dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
technical-seo-checker            dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
threads-trend-check              dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
turnstile-spin                   dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
vercel-deploy-claimable          dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
```

## 기존 링크 전수 확인 (`.codex`/`.gjc`/`.agents`)

체인: `~/.codex|gjc|agents/skills/X` → `~/.claude/skills/X` →(새 심볼릭 링크)→ `kyle-agent-skills/skills/X`. LINK는 모두 resolves=Y, SKILL.md 첫 줄 정상.

### `.codex/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| schema-markup-generator | ABSENT | - | - |
| seo-content-writer | ABSENT | - | - |
| serp-analysis | ABSENT | - | - |
| supabase-multi-project-ops | LINK | Y | --- |
| super-conductor | LINK | Y | --- |
| symphony-setup | LINK | Y | --- |
| technical-seo-checker | ABSENT | - | - |
| threads-trend-check | LINK | Y | --- |
| turnstile-spin | REAL(독립 실물, 차이 후속 과제) | - | --- |
| vercel-deploy-claimable | ABSENT | - | - |

### `.gjc/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| schema-markup-generator | ABSENT | - | - |
| seo-content-writer | ABSENT | - | - |
| serp-analysis | ABSENT | - | - |
| supabase-multi-project-ops | LINK | Y | --- |
| super-conductor | LINK | Y | --- |
| symphony-setup | LINK | Y | --- |
| technical-seo-checker | ABSENT | - | - |
| threads-trend-check | LINK | Y | --- |
| turnstile-spin | ABSENT | - | - |
| vercel-deploy-claimable | ABSENT | - | - |

### `.agents/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| schema-markup-generator | ABSENT | - | - |
| seo-content-writer | ABSENT | - | - |
| serp-analysis | ABSENT | - | - |
| supabase-multi-project-ops | LINK | Y | --- |
| super-conductor | LINK | Y | --- |
| symphony-setup | LINK | Y | --- |
| technical-seo-checker | ABSENT | - | - |
| threads-trend-check | LINK | Y | --- |
| turnstile-spin | REAL(독립 실물, 차이 후속 과제) | - | --- |
| vercel-deploy-claimable | ABSENT | - | - |

## 차이 후속 과제 (REAL 독립 실물)

`turnstile-spin`이 `.codex/skills`와 `.agents/skills`에 LINK가 아니라 REAL(독립 실물 디렉터리)로 존재한다. 이번 이행으로 영향받지 않았고 자체 SKILL.md를 읽지만, 새 정본과 내용이 다를 수 있다. 이후 배치나 별도 작업에서 정본과의 동기화 검증이 필요하다.

## 작업 경계

- 수행: 지정 10개 실물 디렉터리를 정본으로 `mv`, 원위치에 절대경로 `ln -s` 생성, 결과 파일 작성, 지정 경로만 stage해 main에 원자 커밋.
- 하지 않음: `rm`, 브랜치 전환, push, `.claude/skills/.staging`·`scripts`·`registry`·`skills/orca-conductor`·나머지 스킬 수정.
- 보존한 기존 dirty 파일: `docs/TODO.md`, `docs/kyle-inbox.md`, `skills/orca-conductor/references/rally-log.md`, 추적 안 됨 `.commandcode/`.
- stage 범위: 10개 정본 디렉터리 + 본 결과 파일만.
