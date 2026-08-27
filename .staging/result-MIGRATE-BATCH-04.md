# result-MIGRATE-BATCH-04 — skills-repo-migration-1

## Why

`~/.claude/skills`의 네 번째 배치 실물 스킬 디렉터리 10개를 저장소 정본(`kyle-agent-skills/skills/`)으로 옮겨 Git 추적 대상으로 만들고, 원위치는 절대경로 심볼릭 링크로 둬서 기존 도구 경로가 깨지지 않게 한다.

## 이행 배치(10개)

nanobanana2-image-gen, on-page-seo-auditor, performance-reporter, postgres-safe-verification, rank-tracker, react-best-practices, repo-rules-bootstrap, rottie-conductor, rottie-gui-qa, sandbox-sdk

## 측정 기준

- 측정 일시: 2026-08-12 (KST)
- 커밋 직전 HEAD: `ad37b19` (배치 03 이행 후)
- 브랜치: `refs/heads/main`
- 작업 방식: 각 스킬마다 사전 충돌 검사 → `mv` 실물 이동 → 절대경로 `ln -s` → 사후 검증, 실패 시 그 항목만 `unlink` + `mv`로 원상복구.
- 사전 충돌 검사 결과: 10개 전부 SRC_DIR(실물) + DST_FREE(목적지 비었음). 충돌 없음.

## 전/후 경로 매핑

| 스킬 | 이전(실물) | 이후(정본) | 원위치(심볼릭 링크) |
|---|---|---|---|
| nanobanana2-image-gen | /Users/fw_m1/.claude/skills/nanobanana2-image-gen | /Users/fw_m1/Dev/kyle-agent-skills/skills/nanobanana2-image-gen | 심볼릭 링크 → 정본 |
| on-page-seo-auditor | /Users/fw_m1/.claude/skills/on-page-seo-auditor | /Users/fw_m1/Dev/kyle-agent-skills/skills/on-page-seo-auditor | 심볼릭 링크 → 정본 |
| performance-reporter | /Users/fw_m1/.claude/skills/performance-reporter | /Users/fw_m1/Dev/kyle-agent-skills/skills/performance-reporter | 심볼릭 링크 → 정본 |
| postgres-safe-verification | /Users/fw_m1/.claude/skills/postgres-safe-verification | /Users/fw_m1/Dev/kyle-agent-skills/skills/postgres-safe-verification | 심볼릭 링크 → 정본 |
| rank-tracker | /Users/fw_m1/.claude/skills/rank-tracker | /Users/fw_m1/Dev/kyle-agent-skills/skills/rank-tracker | 심볼릭 링크 → 정본 |
| react-best-practices | /Users/fw_m1/.claude/skills/react-best-practices | /Users/fw_m1/Dev/kyle-agent-skills/skills/react-best-practices | 심볼릭 링크 → 정본 |
| repo-rules-bootstrap | /Users/fw_m1/.claude/skills/repo-rules-bootstrap | /Users/fw_m1/Dev/kyle-agent-skills/skills/repo-rules-bootstrap | 심볼릭 링크 → 정본 |
| rottie-conductor | /Users/fw_m1/.claude/skills/rottie-conductor | /Users/fw_m1/Dev/kyle-agent-skills/skills/rottie-conductor | 심볼릭 링크 → 정본 |
| rottie-gui-qa | /Users/fw_m1/.claude/skills/rottie-gui-qa | /Users/fw_m1/Dev/kyle-agent-skills/skills/rottie-gui-qa | 심볼릭 링크 → 정본 |
| sandbox-sdk | /Users/fw_m1/.claude/skills/sandbox-sdk | /Users/fw_m1/Dev/kyle-agent-skills/skills/sandbox-sdk | 심볼릭 링크 → 정본 |

## 사후 검증 (정본 + 원위치 심볼릭 링크)

10개 전부: dst_real=Y, src_link=Y, tgt_correct=Y(절대경로 정확), resolves=Y, SKILL.md 첫 줄 읽힘(`---`).

```
nanobanana2-image-gen            dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
on-page-seo-auditor              dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
performance-reporter             dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
postgres-safe-verification       dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
rank-tracker                     dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
react-best-practices             dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
repo-rules-bootstrap             dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
rottie-conductor                 dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
rottie-gui-qa                    dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
sandbox-sdk                      dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
```

## 기존 링크 전수 확인 (`.codex`/`.gjc`/`.agents`)

체인: `~/.codex|gjc|agents/skills/X` → `~/.claude/skills/X` →(새 심볼릭 링크)→ `kyle-agent-skills/skills/X`. LINK는 모두 resolves=Y, SKILL.md 첫 줄 정상.

### `.codex/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| nanobanana2-image-gen | LINK | Y | --- |
| on-page-seo-auditor | ABSENT | - | - |
| performance-reporter | ABSENT | - | - |
| postgres-safe-verification | LINK | Y | --- |
| rank-tracker | ABSENT | - | - |
| react-best-practices | ABSENT | - | - |
| repo-rules-bootstrap | LINK | Y | --- |
| rottie-conductor | LINK | Y | --- |
| rottie-gui-qa | LINK | Y | --- |
| sandbox-sdk | REAL(독립 실물, 차이 후속 과제) | - | --- |

### `.gjc/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| nanobanana2-image-gen | LINK | Y | --- |
| on-page-seo-auditor | ABSENT | - | - |
| performance-reporter | ABSENT | - | - |
| postgres-safe-verification | LINK | Y | --- |
| rank-tracker | ABSENT | - | - |
| react-best-practices | ABSENT | - | - |
| repo-rules-bootstrap | LINK | Y | --- |
| rottie-conductor | LINK | Y | --- |
| rottie-gui-qa | LINK | Y | --- |
| sandbox-sdk | ABSENT | - | - |

### `.agents/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| nanobanana2-image-gen | LINK | Y | --- |
| on-page-seo-auditor | ABSENT | - | - |
| performance-reporter | ABSENT | - | - |
| postgres-safe-verification | LINK | Y | --- |
| rank-tracker | ABSENT | - | - |
| react-best-practices | ABSENT | - | - |
| repo-rules-bootstrap | LINK | Y | --- |
| rottie-conductor | LINK | Y | --- |
| rottie-gui-qa | LINK | Y | --- |
| sandbox-sdk | REAL(독립 실물, 차이 후속 과제) | - | --- |

## 차이 후속 과제 (REAL 독립 실물)

`sandbox-sdk`가 `.codex/skills`와 `.agents/skills`에 LINK가 아니라 REAL(독립 실물 디렉터리)로 존재한다. 이번 이행으로 영향받지 않았고 자체 SKILL.md를 읽지만, 새 정본과 내용이 다를 수 있다. 이후 배치나 별도 작업에서 정본과의 동기화 검증이 필요하다.

## 작업 경계

- 수행: 지정 10개 실물 디렉터리를 정본으로 `mv`, 원위치에 절대경로 `ln -s` 생성, 결과 파일 작성, 지정 경로만 stage해 main에 원자 커밋.
- 하지 않음: `rm`, 브랜치 전환, push, `.claude/skills/.staging`·`scripts`·`registry`·`skills/orca-conductor`·나머지 스킬 수정.
- 보존한 기존 dirty 파일: `docs/TODO.md`, `docs/kyle-inbox.md`, `skills/orca-conductor/references/rally-log.md`, 추적 안 됨 `.commandcode/`.
- stage 범위: 10개 정본 디렉터리 + 본 결과 파일만.
