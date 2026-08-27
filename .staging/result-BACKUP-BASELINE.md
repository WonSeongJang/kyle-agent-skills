# result-BACKUP-BASELINE — skills-repo-migration-1

## Why

스킬 저장소 이행(migration)에 앞서, 라이브 원본인 `~/.claude/skills`의 현재 상태를
읽기 전용으로 전수 기록해 두어 이행 후 어떤 항목이 변했는지 비교할 수 있는
되돌림 기준점(rollback baseline)을 만든다.

## 측정 기준 정보

- 측정 일시: 2026-08-12 12:05:51 KST
- 측정 경로: `/Users/fw_m1/.claude/skills`
- 저장소 HEAD(백업 커밋 직전): `852c42190ce852f200fada8a16012f6a5a289d8c`
- 저장소 브랜치: `refs/heads/main`
- 측정 방식: 읽기 전용(`ls -l`, `readlink`). 어떤 파일도 수정·삭제하지 않음.
- 제외 항목: `.staging/`, `.`, `..`, `.DS_Store`

## 전체 요약

- 전체 엔트리 수: 64
- 실물 디렉터리: 58
- 심볼릭 링크: 6 (전부 대상 존재, broken 없음)
- 기타 파일: 0

## 심볼릭 링크 목록(6개)

| 링크 이름 | link 문자열(원본) | 최종 도착 절대경로 | 상태 |
|---|---|---|---|
| conductor | /Users/fw_m1/Dev/kyle-agent-skills/skills/conductor | /Users/fw_m1/Dev/kyle-agent-skills/skills/conductor | OK |
| orca-cli | ../../.agents/skills/orca-cli | /Users/fw_m1/.agents/skills/orca-cli | OK |
| orca-conductor | /Users/fw_m1/Dev/kyle-agent-skills/skills/orca-conductor | /Users/fw_m1/Dev/kyle-agent-skills/skills/orca-conductor | OK |
| orchestration | ../../.agents/skills/orchestration | /Users/fw_m1/.agents/skills/orchestration | OK |
| payment-mor-core | /Users/fw_m1/.codex/skills/payment-mor-core | /Users/fw_m1/.codex/skills/payment-mor-core | OK |
| payment-mor-migration | /Users/fw_m1/.codex/skills/payment-mor-migration | /Users/fw_m1/.codex/skills/payment-mor-migration | OK |

## 실물 디렉터리 목록(58개, 이름순)

1. admin-dashboard-playbook
2. agents-sdk
3. alert-manager
4. aside-browser
5. backlink-analyzer
6. briefing
7. browser
8. chabun-naengchul
9. claude-codex-shared-setup
10. cloudflare
11. cloudflare-email-service
12. competitor-analysis
13. content-gap-analysis
14. content-quality-auditor
15. content-refresher
16. design-conductor
17. domain-authority-auditor
18. durable-objects
19. entity-optimizer
20. frontend-foundation-playbook
21. geo-content-optimizer
22. git-push
23. grill-me
24. growth-tracking-playbook
25. internal-linking-optimizer
26. keyword-research
27. marketing-funnel
28. md-visual-workflow
29. memory-management
30. meta-tags-optimizer
31. nanobanana2-image-gen
32. on-page-seo-auditor
33. performance-reporter
34. postgres-safe-verification
35. rank-tracker
36. react-best-practices
37. repo-rules-bootstrap
38. rottie-conductor
39. rottie-gui-qa
40. sandbox-sdk
41. schema-markup-generator
42. seo-content-writer
43. serp-analysis
44. supabase-multi-project-ops
45. super-conductor
46. symphony-setup
47. technical-seo-checker
48. threads-trend-check
49. turnstile-spin
50. vercel-deploy-claimable
51. vercel-react-best-practices
52. vision-click
53. web-ai
54. web-design-guidelines
55. web-perf
56. workers-best-practices
57. workflow-bootstrap
58. wrangler

## 작업 경계 (수행한 것 / 하지 않은 것)

- 수행: `~/.claude/skills` 읽기 전용 전수 조사, 본 결과 파일 작성, 지정 경로만 stage하여 main에 백업 커밋.
- 하지 않음: `rm`, `push`, 브랜치 전환, 기존 변경 파일 수정·stage.
- 보존한 기존 dirty 파일: `docs/TODO.md`, `docs/kyle-inbox.md`, `skills/orca-conductor/references/rally-log.md`, 추적 안 됨 `.commandcode/`.
- 스테이지 범위: `.staging/result-BACKUP-BASELINE.md` 단일 파일만.

## 원본 측정 전문(자동 생성)

```
DIR|admin-dashboard-playbook|-|
DIR|agents-sdk|-|
DIR|alert-manager|-|
DIR|aside-browser|-|
DIR|backlink-analyzer|-|
DIR|briefing|-|
DIR|browser|-|
DIR|chabun-naengchul|-|
DIR|claude-codex-shared-setup|-|
DIR|cloudflare|-|
DIR|cloudflare-email-service|-|
DIR|competitor-analysis|-|
SYMLINK|conductor|/Users/fw_m1/Dev/kyle-agent-skills/skills/conductor|OK
DIR|content-gap-analysis|-|
DIR|content-quality-auditor|-|
DIR|content-refresher|-|
DIR|design-conductor|-|
DIR|domain-authority-auditor|-|
DIR|durable-objects|-|
DIR|entity-optimizer|-|
DIR|frontend-foundation-playbook|-|
DIR|geo-content-optimizer|-|
DIR|git-push|-|
DIR|grill-me|-|
DIR|growth-tracking-playbook|-|
DIR|internal-linking-optimizer|-|
DIR|keyword-research|-|
DIR|marketing-funnel|-|
DIR|md-visual-workflow|-|
DIR|memory-management|-|
DIR|meta-tags-optimizer|-|
DIR|nanobanana2-image-gen|-|
DIR|on-page-seo-auditor|-|
SYMLINK|orca-cli|../../.agents/skills/orca-cli|OK
SYMLINK|orca-conductor|/Users/fw_m1/Dev/kyle-agent-skills/skills/orca-conductor|OK
SYMLINK|orchestration|../../.agents/skills/orchestration|OK
SYMLINK|payment-mor-core|/Users/fw_m1/.codex/skills/payment-mor-core|OK
SYMLINK|payment-mor-migration|/Users/fw_m1/.codex/skills/payment-mor-migration|OK
DIR|performance-reporter|-|
DIR|postgres-safe-verification|-|
DIR|rank-tracker|-|
DIR|react-best-practices|-|
DIR|repo-rules-bootstrap|-|
DIR|rottie-conductor|-|
DIR|rottie-gui-qa|-|
DIR|sandbox-sdk|-|
DIR|schema-markup-generator|-|
DIR|seo-content-writer|-|
DIR|serp-analysis|-|
DIR|supabase-multi-project-ops|-|
DIR|super-conductor|-|
DIR|symphony-setup|-|
DIR|technical-seo-checker|-|
DIR|threads-trend-check|-|
DIR|turnstile-spin|-|
DIR|vercel-deploy-claimable|-|
DIR|vercel-react-best-practices|-|
DIR|vision-click|-|
DIR|web-ai|-|
DIR|web-design-guidelines|-|
DIR|web-perf|-|
DIR|workers-best-practices|-|
DIR|workflow-bootstrap|-|
DIR|wrangler|-|
```
