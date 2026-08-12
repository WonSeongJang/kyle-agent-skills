# result-MIGRATE-BATCH-03 — skills-repo-migration-1

## Why

`~/.claude/skills`의 세 번째 배치 실물 스킬 디렉터리 10개를 저장소 정본(`kyle-agent-skills/skills/`)으로 옮겨 Git 추적 대상으로 만들고, 원위치는 절대경로 심볼릭 링크로 둬서 기존 도구 경로가 깨지지 않게 한다.

## 이행 배치(10개)

geo-content-optimizer, git-push, grill-me, growth-tracking-playbook, internal-linking-optimizer, keyword-research, marketing-funnel, md-visual-workflow, memory-management, meta-tags-optimizer

## 측정 기준

- 측정 일시: 2026-08-12 (KST)
- 커밋 직전 HEAD: `cdef914` (배치 02 이행 후)
- 브랜치: `refs/heads/main`
- 작업 방식: 각 스킬마다 사전 충돌 검사 → `mv` 실물 이동 → 절대경로 `ln -s` → 사후 검증, 실패 시 그 항목만 `unlink` + `mv`로 원상복구.
- 사전 충돌 검사 결과: 10개 전부 SRC_DIR(실물) + DST_FREE(목적지 비었음). 충돌 없음.

## 전/후 경로 매핑

| 스킬 | 이전(실물) | 이후(정본) | 원위치(심볼릭 링크) |
|---|---|---|---|
| geo-content-optimizer | /Users/fw_m1/.claude/skills/geo-content-optimizer | /Users/fw_m1/Dev/kyle-agent-skills/skills/geo-content-optimizer | 심볼릭 링크 → 정본 |
| git-push | /Users/fw_m1/.claude/skills/git-push | /Users/fw_m1/Dev/kyle-agent-skills/skills/git-push | 심볼릭 링크 → 정본 |
| grill-me | /Users/fw_m1/.claude/skills/grill-me | /Users/fw_m1/Dev/kyle-agent-skills/skills/grill-me | 심볼릭 링크 → 정본 |
| growth-tracking-playbook | /Users/fw_m1/.claude/skills/growth-tracking-playbook | /Users/fw_m1/Dev/kyle-agent-skills/skills/growth-tracking-playbook | 심볼릭 링크 → 정본 |
| internal-linking-optimizer | /Users/fw_m1/.claude/skills/internal-linking-optimizer | /Users/fw_m1/Dev/kyle-agent-skills/skills/internal-linking-optimizer | 심볼릭 링크 → 정본 |
| keyword-research | /Users/fw_m1/.claude/skills/keyword-research | /Users/fw_m1/Dev/kyle-agent-skills/skills/keyword-research | 심볼릭 링크 → 정본 |
| marketing-funnel | /Users/fw_m1/.claude/skills/marketing-funnel | /Users/fw_m1/Dev/kyle-agent-skills/skills/marketing-funnel | 심볼릭 링크 → 정본 |
| md-visual-workflow | /Users/fw_m1/.claude/skills/md-visual-workflow | /Users/fw_m1/Dev/kyle-agent-skills/skills/md-visual-workflow | 심볼릭 링크 → 정본 |
| memory-management | /Users/fw_m1/.claude/skills/memory-management | /Users/fw_m1/Dev/kyle-agent-skills/skills/memory-management | 심볼릭 링크 → 정본 |
| meta-tags-optimizer | /Users/fw_m1/.claude/skills/meta-tags-optimizer | /Users/fw_m1/Dev/kyle-agent-skills/skills/meta-tags-optimizer | 심볼릭 링크 → 정본 |

## 사후 검증 (정본 + 원위치 심볼릭 링크)

10개 전부: dst_real=Y, src_link=Y, tgt_correct=Y(절대경로 정확), resolves=Y, SKILL.md 첫 줄 읽힘(`---`).

```
geo-content-optimizer            dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
git-push                         dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
grill-me                         dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
growth-tracking-playbook         dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
internal-linking-optimizer       dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
keyword-research                 dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
marketing-funnel                 dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
md-visual-workflow               dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
memory-management                dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
meta-tags-optimizer              dst_real=Y src_link=Y tgt_correct=Y resolves=Y | ---
```

## 기존 링크 전수 확인 (`.codex`/`.gjc`/`.agents`)

체인: `~/.codex|gjc|agents/skills/X` → `~/.claude/skills/X` →(새 심볼릭 링크)→ `kyle-agent-skills/skills/X`. LINK는 모두 resolves=Y, SKILL.md 첫 줄 정상.

### `.codex/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| geo-content-optimizer | ABSENT | - | - |
| git-push | ABSENT | - | - |
| grill-me | LINK | Y | --- |
| growth-tracking-playbook | LINK | Y | --- |
| internal-linking-optimizer | ABSENT | - | - |
| keyword-research | ABSENT | - | - |
| marketing-funnel | LINK | Y | --- |
| md-visual-workflow | LINK | Y | --- |
| memory-management | ABSENT | - | - |
| meta-tags-optimizer | ABSENT | - | - |

### `.gjc/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| geo-content-optimizer | ABSENT | - | - |
| git-push | ABSENT | - | - |
| grill-me | LINK | Y | --- |
| growth-tracking-playbook | LINK | Y | --- |
| internal-linking-optimizer | ABSENT | - | - |
| keyword-research | ABSENT | - | - |
| marketing-funnel | LINK | Y | --- |
| md-visual-workflow | LINK | Y | --- |
| memory-management | ABSENT | - | - |
| meta-tags-optimizer | ABSENT | - | - |

### `.agents/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| geo-content-optimizer | ABSENT | - | - |
| git-push | ABSENT | - | - |
| grill-me | LINK | Y | --- |
| growth-tracking-playbook | LINK | Y | --- |
| internal-linking-optimizer | ABSENT | - | - |
| keyword-research | ABSENT | - | - |
| marketing-funnel | ABSENT | - | - |
| md-visual-workflow | LINK | Y | --- |
| memory-management | ABSENT | - | - |
| meta-tags-optimizer | ABSENT | - | - |

## 차이 후속 과제 (REAL 독립 실물)

이 배치 10개 중 `.codex`/`.gjc`/`.agents`에 REAL(독립 실물)로 존재하는 항목은 없다. LINK 또는 ABSENT만 있으며, LINK는 모두 새 정본까지 정상 해석된다. 후속 과제 없음(이 배치 한정).

## 작업 경계

- 수행: 지정 10개 실물 디렉터리를 정본으로 `mv`, 원위치에 절대경로 `ln -s` 생성, 결과 파일 작성, 지정 경로만 stage해 main에 원자 커밋.
- 하지 않음: `rm`, 브랜치 전환, push, `.claude/skills/.staging`·`scripts`·`registry`·`skills/orca-conductor`·나머지 스킬 수정.
- 보존한 기존 dirty 파일: `docs/TODO.md`, `docs/kyle-inbox.md`, `skills/orca-conductor/references/rally-log.md`, 추적 안 됨 `.commandcode/`.
- stage 범위: 10개 정본 디렉터리 + 본 결과 파일만.
