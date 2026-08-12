# result-MIGRATE-BATCH-02 — skills-repo-migration-1

## Why

`~/.claude/skills`의 두 번째 배치 실물 스킬 디렉터리 10개를 저장소 정본(`kyle-agent-skills/skills/`)으로 옮겨 Git 추적 대상으로 만들고, 원위치는 절대경로 심볼릭 링크로 둬서 기존 도구 경로가 깨지지 않게 한다.

## 이행 배치(10개)

cloudflare-email-service, competitor-analysis, content-gap-analysis, content-quality-auditor, content-refresher, design-conductor, domain-authority-auditor, durable-objects, entity-optimizer, frontend-foundation-playbook

## 측정 기준

- 측정 일시: 2026-08-12 (KST)
- 커밋 직전 HEAD: `ab1d188` (배치 01 이행 후)
- 브랜치: `refs/heads/main`
- 작업 방식: 각 스킬마다 사전 충돌 검사 → `mv` 실물 이동 → 절대경로 `ln -s` → 사후 검증, 실패 시 그 항목만 `unlink` + `mv`로 원상복구.
- 사전 충돌 검사 결과: 10개 전부 SRC_DIR(실물) + DST_FREE(목적지 비었음). 충돌 없음.

## 전/후 경로 매핑

| 스킬 | 이전(실물) | 이후(정본) | 원위치(심볼릭 링크) |
|---|---|---|---|
| cloudflare-email-service | /Users/fw_m1/.claude/skills/cloudflare-email-service | /Users/fw_m1/Dev/kyle-agent-skills/skills/cloudflare-email-service | 심볼릭 링크 → 정본 |
| competitor-analysis | /Users/fw_m1/.claude/skills/competitor-analysis | /Users/fw_m1/Dev/kyle-agent-skills/skills/competitor-analysis | 심볼릭 링크 → 정본 |
| content-gap-analysis | /Users/fw_m1/.claude/skills/content-gap-analysis | /Users/fw_m1/Dev/kyle-agent-skills/skills/content-gap-analysis | 심볼릭 링크 → 정본 |
| content-quality-auditor | /Users/fw_m1/.claude/skills/content-quality-auditor | /Users/fw_m1/Dev/kyle-agent-skills/skills/content-quality-auditor | 심볼릭 링크 → 정본 |
| content-refresher | /Users/fw_m1/.claude/skills/content-refresher | /Users/fw_m1/Dev/kyle-agent-skills/skills/content-refresher | 심볼릭 링크 → 정본 |
| design-conductor | /Users/fw_m1/.claude/skills/design-conductor | /Users/fw_m1/Dev/kyle-agent-skills/skills/design-conductor | 심볼릭 링크 → 정본 |
| domain-authority-auditor | /Users/fw_m1/.claude/skills/domain-authority-auditor | /Users/fw_m1/Dev/kyle-agent-skills/skills/domain-authority-auditor | 심볼릭 링크 → 정본 |
| durable-objects | /Users/fw_m1/.claude/skills/durable-objects | /Users/fw_m1/Dev/kyle-agent-skills/skills/durable-objects | 심볼릭 링크 → 정본 |
| entity-optimizer | /Users/fw_m1/.claude/skills/entity-optimizer | /Users/fw_m1/Dev/kyle-agent-skills/skills/entity-optimizer | 심볼릭 링크 → 정본 |
| frontend-foundation-playbook | /Users/fw_m1/.claude/skills/frontend-foundation-playbook | /Users/fw_m1/Dev/kyle-agent-skills/skills/frontend-foundation-playbook | 심볼릭 링크 → 정본 |

## 사후 검증 (정본 + 원위치 심볼릭 링크)

10개 전부: dst_real=Y, src_link=Y, tgt_correct=Y(절대경로 정확), resolves=Y, SKILL.md 첫 줄 읽힘(`---`).

```
cloudflare-email-service         dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
competitor-analysis              dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
content-gap-analysis             dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
content-quality-auditor          dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
content-refresher               dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
design-conductor                 dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
domain-authority-auditor         dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
durable-objects                  dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
entity-optimizer                 dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
frontend-foundation-playbook     dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
```

## 기존 링크 전수 확인 (`.codex`/`.gjc`/`.agents`)

체인: `~/.codex|gjc|agents/skills/X` → `~/.claude/skills/X` →(새 심볼릭 링크)→ `kyle-agent-skills/skills/X`. LINK는 모두 resolves=Y, SKILL.md 첫 줄 정상.

### `.codex/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| cloudflare-email-service | REAL(독립 실물, 차이 후속 과제) | - | --- |
| competitor-analysis | ABSENT | - | - |
| content-gap-analysis | ABSENT | - | - |
| content-quality-auditor | ABSENT | - | - |
| content-refresher | ABSENT | - | - |
| design-conductor | LINK | Y | --- |
| domain-authority-auditor | ABSENT | - | - |
| durable-objects | REAL(독립 실물, 차이 후속 과제) | - | --- |
| entity-optimizer | ABSENT | - | - |
| frontend-foundation-playbook | LINK | Y | --- |

### `.gjc/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| cloudflare-email-service | ABSENT | - | - |
| competitor-analysis | ABSENT | - | - |
| content-gap-analysis | ABSENT | - | - |
| content-quality-auditor | ABSENT | - | - |
| content-refresher | ABSENT | - | - |
| design-conductor | LINK | Y | --- |
| domain-authority-auditor | ABSENT | - | - |
| durable-objects | ABSENT | - | - |
| entity-optimizer | ABSENT | - | - |
| frontend-foundation-playbook | LINK | Y | --- |

### `.agents/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| cloudflare-email-service | REAL(독립 실물, 차이 후속 과제) | - | --- |
| competitor-analysis | ABSENT | - | - |
| content-gap-analysis | ABSENT | - | - |
| content-quality-auditor | ABSENT | - | - |
| content-refresher | ABSENT | - | - |
| design-conductor | LINK | Y | --- |
| domain-authority-auditor | ABSENT | - | - |
| durable-objects | REAL(독립 실물, 차이 후속 과제) | - | --- |
| entity-optimizer | ABSENT | - | - |
| frontend-foundation-playbook | LINK | Y | --- |

## 차이 후속 과제 (REAL 독립 실물)

`.codex/skills`와 `.agents/skills`에 아래 항목이 LINK가 아니라 REAL(독립 실물 디렉터리)로 존재한다. 이번 이행으로 영향받지 않았고 자체 SKILL.md를 읽지만, 새 정본과 내용이 다를 수 있다.

- cloudflare-email-service: `.codex`, `.agents` 모두 REAL
- durable-objects: `.codex`, `.agents` 모두 REAL

이후 배치나 별도 작업에서 정본과의 동기화(내용 일치 여부) 검증이 필요하다.

## 작업 경계

- 수행: 지정 10개 실물 디렉터리를 정본으로 `mv`, 원위치에 절대경로 `ln -s` 생성, 결과 파일 작성, 지정 경로만 stage해 main에 원자 커밋.
- 하지 않음: `rm`, 브랜치 전환, push, `.claude/skills/.staging`·`scripts`·`registry`·`skills/orca-conductor`·나머지 스킬 수정.
- 보존한 기존 dirty 파일: `docs/TODO.md`, `docs/kyle-inbox.md`, `skills/orca-conductor/references/rally-log.md`, 추적 안 됨 `.commandcode/`.
- stage 범위: 10개 정본 디렉터리 + 본 결과 파일만.
