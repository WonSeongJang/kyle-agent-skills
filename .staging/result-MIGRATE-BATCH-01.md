# result-MIGRATE-BATCH-01 — skills-repo-migration-1

## Why

`~/.claude/skills`에 섞여 있던 실물 스킬 디렉터리들을 저장소 정본(`kyle-agent-skills/skills/`)으로 옮겨, 스킬을 Git 변경으로 추적 가능하게 만들고 원위치는 절대경로 심볼릭 링크로 둬서 기존 도구(Claude/Codex/GJC/agents)가 깨지지 않게 한다.

## 이행 배치(10개)

admin-dashboard-playbook, agents-sdk, alert-manager, aside-browser, backlink-analyzer, briefing, browser, chabun-naengchul, claude-codex-shared-setup, cloudflare

## 측정 기준

- 측정 일시: 2026-08-12 (KST)
- 커밋 직전 HEAD: `4564e9c` (백업 기준점)
- 브랜치: `refs/heads/main`
- 작업 방식: 각 스킬마다 사전 충돌 검사 → `mv` 실물 이동 → 절대경로 `ln -s` → 사후 검증, 실패 시 그 항목만 `unlink` + `mv`로 원상복구.

## 전/후 경로 매핑

각 항목의 이동:

| 스킬 | 이전(실물) | 이후(정본) | 원위치(심볼릭 링크) |
|---|---|---|---|
| admin-dashboard-playbook | /Users/fw_m1/.claude/skills/admin-dashboard-playbook | /Users/fw_m1/Dev/kyle-agent-skills/skills/admin-dashboard-playbook | 심볼릭 링크 → 정본 |
| agents-sdk | /Users/fw_m1/.claude/skills/agents-sdk | /Users/fw_m1/Dev/kyle-agent-skills/skills/agents-sdk | 심볼릭 링크 → 정본 |
| alert-manager | /Users/fw_m1/.claude/skills/alert-manager | /Users/fw_m1/Dev/kyle-agent-skills/skills/alert-manager | 심볼릭 링크 → 정본 |
| aside-browser | /Users/fw_m1/.claude/skills/aside-browser | /Users/fw_m1/Dev/kyle-agent-skills/skills/aside-browser | 심볼릭 링크 → 정본 |
| backlink-analyzer | /Users/fw_m1/.claude/skills/backlink-analyzer | /Users/fw_m1/Dev/kyle-agent-skills/skills/backlink-analyzer | 심볼릭 링크 → 정본 |
| briefing | /Users/fw_m1/.claude/skills/briefing | /Users/fw_m1/Dev/kyle-agent-skills/skills/briefing | 심볼릭 링크 → 정본 |
| browser | /Users/fw_m1/.claude/skills/browser | /Users/fw_m1/Dev/kyle-agent-skills/skills/browser | 심볼릭 링크 → 정본 |
| chabun-naengchul | /Users/fw_m1/.claude/skills/chabun-naengchul | /Users/fw_m1/Dev/kyle-agent-skills/skills/chabun-naengchul | 심볼릭 링크 → 정본 |
| claude-codex-shared-setup | /Users/fw_m1/.claude/skills/claude-codex-shared-setup | /Users/fw_m1/Dev/kyle-agent-skills/skills/claude-codex-shared-setup | 심볼릭 링크 → 정본 |
| cloudflare | /Users/fw_m1/.claude/skills/cloudflare | /Users/fw_m1/Dev/kyle-agent-skills/skills/cloudflare | 심볼릭 링크 → 정본 |

## 사후 검증 (정본 + 원위치 심볼릭 링크)

10개 전부: dst_real=Y, src_link=Y, tgt_correct=Y(절대경로 정확), resolves=Y, SKILL.md 첫 줄 읽힘(`---`, YAML 프론트매터).

## 기존 링크 전수 확인 (`.codex`/`.gjc`/`.agents`)

체인: `~/.codex|gjc|agents/skills/X` → `~/.claude/skills/X` →(새 심볼릭 링크)→ `kyle-agent-skills/skills/X`. 2단계 링크라도 최종 정본까지 resolves=Y이고 SKILL.md 첫 줄 정상 읽힘.

### `.codex/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| admin-dashboard-playbook | LINK | Y | --- |
| agents-sdk | REAL(독립 실물, 이행 무관) | - | --- |
| alert-manager | ABSENT(원래 없음) | - | - |
| aside-browser | ABSENT | - | - |
| backlink-analyzer | ABSENT | - | - |
| briefing | LINK | Y | --- |
| browser | LINK | Y | --- |
| chabun-naengchul | LINK | Y | --- |
| claude-codex-shared-setup | LINK | Y | --- |
| cloudflare | REAL(독립 실물, 이행 무관) | - | --- |

### `.gjc/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| admin-dashboard-playbook | LINK | Y | --- |
| agents-sdk | ABSENT | - | - |
| alert-manager | ABSENT | - | - |
| aside-browser | ABSENT | - | - |
| backlink-analyzer | ABSENT | - | - |
| briefing | LINK | Y | --- |
| browser | LINK | Y | --- |
| chabun-naengchul | LINK | Y | --- |
| claude-codex-shared-setup | LINK | Y | --- |
| cloudflare | ABSENT | - | - |

### `.agents/skills`

| 스킬 | 상태 | resolves | SKILL.md |
|---|---|---|---|
| admin-dashboard-playbook | LINK | Y | --- |
| agents-sdk | REAL(독립 실물, 이행 무관) | - | --- |
| alert-manager | ABSENT | - | - |
| aside-browser | REAL(독립 실물, 이행 무관) | - | --- |
| backlink-analyzer | ABSENT | - | - |
| briefing | LINK | Y | --- |
| browser | LINK | Y | --- |
| chabun-naengchul | LINK | Y | --- |
| claude-codex-shared-setup | LINK | Y | --- |
| cloudflare | REAL(독립 실물, 이행 무관) | - | --- |

## 주의 사항 (정직한 보고)

`.codex/skills`와 `.agents/skills`에 일부 항목이 LINK가 아니라 REAL(독립 실물 디렉터리)로 존재한다: `agents-sdk`, `cloudflare`, 그리고 `.agents`의 `aside-browser`. 이 REAL들은 `~/.claude/skills` 실물과 별개 파일로, 이번 이행으로 영향을 받지 않았고 자체 SKILL.md를 그대로 읽는다. 즉 새 정본과 내용이 다를 수 있다. 이후 배치에서 정본과 동기화 여부를 별도 검증해야 한다.

## 작업 경계

- 수행: 지정 10개 실물 디렉터리를 정본으로 `mv`, 원위치에 절대경로 `ln -s` 생성, 결과 파일 작성, 지정 경로만 stage해 main에 원자 커밋.
- 하지 않음: `rm`, 브랜치 전환, push, `.claude/skills/.staging`·`scripts`·`registry`·`skills/orca-conductor`·나머지 스킬 수정.
- 보존한 기존 dirty 파일: `docs/TODO.md`, `docs/kyle-inbox.md`, `skills/orca-conductor/references/rally-log.md`, 추적 안 됨 `.commandcode/`.
- stage 범위: 10개 정본 디렉터리 + 본 결과 파일만.

## 원본 측정 전문(자동 생성)

사후 검증 스크립트 결과(정본 + 원위치 심볼릭 링크):

```
admin-dashboard-playbook       dst_real=Y src_link=Y tgt_correct=Y resolves=Y | SKILL.md[1]: ---
agents-sdk                     dst_real=Y src_link=Y tgt_correct=Y resolves=Y | SKILL.md[1]: ---
alert-manager                  dst_real=Y src_link=Y tgt_correct=Y resolves=Y | SKILL.md[1]: ---
aside-browser                  dst_real=Y src_link=Y tgt_correct=Y resolves=Y | SKILL.md[1]: ---
backlink-analyzer              dst_real=Y src_link=Y tgt_correct=Y resolves=Y | SKILL.md[1]: ---
briefing                       dst_real=Y src_link=Y tgt_correct=Y resolves=Y | SKILL.md[1]: ---
browser                        dst_real=Y src_link=Y tgt_correct=Y resolves=Y | SKILL.md[1]: ---
chabun-naengchul               dst_real=Y src_link=Y tgt_correct=Y resolves=Y | SKILL.md[1]: ---
claude-codex-shared-setup      dst_real=Y src_link=Y tgt_correct=Y resolves=Y | SKILL.md[1]: ---
cloudflare                     dst_real=Y src_link=Y tgt_correct=Y resolves=Y | SKILL.md[1]: ---
```
