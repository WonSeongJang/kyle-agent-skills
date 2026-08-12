# result-MIGRATE-BATCH-06 — skills-repo-migration-1

## Why

마지막 일반 본이행 배치로, `~/.claude/skills`에 남은 일반 실물 스킬 디렉터리 8개를 저장소 정본(`kyle-agent-skills/skills/`)으로 옮겨 Git 추적 대상으로 만들고, 원위치는 절대경로 심볼릭 링크로 둬서 기존 도구 경로가 깨지지 않게 한다. 이 배치로 `~/.claude/skills`의 `.staging` 제외 실물 디렉터리가 0이 된다.

## 이행 배치(8개)

vercel-react-best-practices, vision-click, web-ai, web-design-guidelines, web-perf, workers-best-practices, workflow-bootstrap, wrangler

## 측정 기준

- 측정 일시: 2026-08-12 (KST)
- 커밋 직전 HEAD: `793b27b` (배치 05 이행 후)
- 브랜치: `refs/heads/main`
- 작업 방식: 각 스킬마다 사전 충돌 검사 → `mv` 실물 이동 → 절대경로 `ln -s` → 사후 검증, 실패 시 그 항목만 `unlink` + `mv`로 원상복구.
- 사전 충돌 검사 결과: 8개 전부 SRC_DIR(실물) + DST_FREE(목적지 비었음). 충돌 없음.

## 전/후 경로 매핑

| 스킬 | 이전(실물) | 이후(정본) | 원위치(심볼릭 링크) |
|---|---|---|---|
| vercel-react-best-practices | /Users/fw_m1/.claude/skills/vercel-react-best-practices | /Users/fw_m1/Dev/kyle-agent-skills/skills/vercel-react-best-practices | 심볼릭 링크 → 정본 |
| vision-click | /Users/fw_m1/.claude/skills/vision-click | /Users/fw_m1/Dev/kyle-agent-skills/skills/vision-click | 심볼릭 링크 → 정본 |
| web-ai | /Users/fw_m1/.claude/skills/web-ai | /Users/fw_m1/Dev/kyle-agent-skills/skills/web-ai | 심볼릭 링크 → 정본 |
| web-design-guidelines | /Users/fw_m1/.claude/skills/web-design-guidelines | /Users/fw_m1/Dev/kyle-agent-skills/skills/web-design-guidelines | 심볼릭 링크 → 정본 |
| web-perf | /Users/fw_m1/.claude/skills/web-perf | /Users/fw_m1/Dev/kyle-agent-skills/skills/web-perf | 심볼릭 링크 → 정본 |
| workers-best-practices | /Users/fw_m1/.claude/skills/workers-best-practices | /Users/fw_m1/Dev/kyle-agent-skills/skills/workers-best-practices | 심볼릭 링크 → 정본 |
| workflow-bootstrap | /Users/fw_m1/.claude/skills/workflow-bootstrap | /Users/fw_m1/Dev/kyle-agent-skills/skills/workflow-bootstrap | 심볼릭 링크 → 정본 |
| wrangler | /Users/fw_m1/.claude/skills/wrangler | /Users/fw_m1/Dev/kyle-agent-skills/skills/wrangler | 심볼릭 링크 → 정본 |

## 사후 검증 (정본 + 원위치 심볼릭 링크)

8개 전부: dst_real=Y, src_link=Y, tgt_correct=Y(절대경로 정확), resolves=Y, SKILL.md 첫 줄 읽힘(`---`).

```
vercel-react-best-practices      dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
vision-click                     dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
web-ai                           dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
web-design-guidelines            dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
web-perf                         dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
workers-best-practices           dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
workflow-bootstrap               dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
wrangler                         dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
```

## ~/.claude/skills 실물 디렉터리 0 확인

이행 후 `~/.claude/skills`(.staging, .DS_Store 제외) 전수 결과:
- 총 항목 수: 63
- 전부 SYMLINK
- 실물(real) 디렉터리 수: **0**

63개 항목 목록(모두 SYMLINK):

```
admin-dashboard-playbook, agents-sdk, alert-manager, aside-browser, backlink-analyzer, briefing, browser, chabun-naengchul, claude-codex-shared-setup, cloudflare, cloudflare-email-service, competitor-analysis, conductor, content-gap-analysis, content-quality-auditor, content-refresher, design-conductor, domain-authority-auditor, durable-objects, entity-optimizer, frontend-foundation-playbook, geo-content-optimizer, git-push, grill-me, growth-tracking-playbook, internal-linking-optimizer, keyword-research, marketing-funnel, md-visual-workflow, memory-management, meta-tags-optimizer, nanobanana2-image-gen, on-page-seo-auditor, orca-cli, orca-conductor, orchestration, payment-mor-core, payment-mor-migration, performance-reporter, postgres-safe-verification, rank-tracker, react-best-practices, repo-rules-bootstrap, rottie-conductor, rottie-gui-qa, sandbox-sdk, schema-markup-generator, seo-content-writer, serp-analysis, supabase-multi-project-ops, super-conductor, symphony-setup, technical-seo-checker, threads-trend-check, turnstile-spin, vercel-deploy-claimable, vercel-react-best-practices, vision-click, web-ai, web-design-guidelines, web-perf, workers-best-practices, workflow-bootstrap, wrangler
```

## 기존 링크 전수 확인 (`.codex`/`.gjc`/`.agents`)

체인: `~/.codex|gjc|agents/skills/X` → `~/.claude/skills/X` →(새 심볼릭 링크)→ `kyle-agent-skills/skills/X`. LINK는 모두 resolves=Y, SKILL.md 첫 줄 정상.

### `.codex/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| vercel-react-best-practices | REAL(독립 실물, 차이 후속 과제) | - | --- |
| vision-click | LINK | Y | --- |
| web-ai | LINK | Y | --- |
| web-design-guidelines | REAL(독립 실물, 차이 후속 과제) | - | --- |
| web-perf | REAL(독립 실물, 차이 후속 과제) | - | --- |
| workers-best-practices | REAL(독립 실물, 차이 후속 과제) | - | --- |
| workflow-bootstrap | LINK | Y | --- |
| wrangler | REAL(독립 실물, 차이 후속 과제) | - | --- |

### `.gjc/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| vercel-react-best-practices | ABSENT | - | - |
| vision-click | LINK | Y | --- |
| web-ai | LINK | Y | --- |
| web-design-guidelines | ABSENT | - | - |
| web-perf | ABSENT | - | - |
| workers-best-practices | ABSENT | - | - |
| workflow-bootstrap | LINK | Y | --- |
| wrangler | ABSENT | - | - |

### `.agents/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| vercel-react-best-practices | ABSENT | - | - |
| vision-click | LINK | Y | --- |
| web-ai | LINK | Y | --- |
| web-design-guidelines | ABSENT | - | - |
| web-perf | REAL(독립 실물, 차이 후속 과제) | - | --- |
| workers-best-practices | REAL(독립 실물, 차이 후속 과제) | - | --- |
| workflow-bootstrap | LINK | Y | --- |
| wrangler | REAL(독립 실물, 차이 후속 과제) | - | --- |

## 차이 후속 과제 (REAL 독립 실물)

이 배치의 REAL(독립 실물) 항목:
- vercel-react-best-practices: `.codex` REAL
- web-design-guidelines: `.codex` REAL
- web-perf: `.codex` REAL, `.agents` REAL
- workers-best-practices: `.codex` REAL, `.agents` REAL
- wrangler: `.codex` REAL, `.agents` REAL

이 항목들은 이번 이행으로 영향받지 않았고 자체 SKILL.md를 읽지만, 새 정본과 내용이 다를 수 있다. 이후 배치나 별도 작업에서 정본과의 동기화 검증이 필요하다.

## 작업 경계

- 수행: 지정 8개 실물 디렉터리를 정본으로 `mv`, 원위치에 절대경로 `ln -s` 생성, 결과 파일 작성, 지정 경로만 stage해 main에 원자 커밋.
- 하지 않음: `rm`, 브랜치 전환, push, `.claude/skills/.staging`·`scripts`·`registry`·`skills/orca-conductor`·나머지 스킬 수정.
- 보존한 기존 dirty 파일: `docs/TODO.md`, `docs/kyle-inbox.md`, `skills/orca-conductor/references/rally-log.md`, 추적 안 됨 `.commandcode/`.
- stage 범위: 8개 정본 디렉터리 + 본 결과 파일만.
