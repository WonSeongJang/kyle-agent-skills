# result-FINAL-VERIFY-MIGRATION — skills-repo-migration-1

## Why

이행 전체 판(skills-repo-migration-1)의 최종 독립 검증을 수행해, 모든 스킬이 저장소 정본 한 곳을 가리키고 4도구가 일관되게 읽으며 보존본이 온전함을 확인한다. 새 이행이나 링크 변경은 없다.

## HEAD 및 환경

- HEAD: `b8aeeedc59486e45d35dd392e033af11778d0ccf`
- 브랜치: `refs/heads/main`
- 검증 일시: 2026-08-12 (KST)

## (1) 정본 목록·개수 대조

저장소 `skills/` 정본 디렉터리: **64개**.

registry 파일: 저장소에 별도 `registry` 파일이나 `skills.txt` 파일은 존재하지 않음(`find` 결과 해당 없음). `/skills.txt` 사용자 표면은 도구가 디렉터리를 스캔해 보고하는 개념으로, 본 검증은 각 도구별 skills 디렉터리의 실제 항목으로 실측함(아래 (2) 참조).

64개 정본 목록(이름순): admin-dashboard-playbook, agents-sdk, alert-manager, aside-browser, backlink-analyzer, briefing, browser, chabun-naengchul, claude-codex-shared-setup, cloudflare, cloudflare-email-service, competitor-analysis, conductor, content-gap-analysis, content-quality-auditor, content-refresher, design-conductor, domain-authority-auditor, durable-objects, entity-optimizer, frontend-foundation-playbook, geo-content-optimizer, git-push, grill-me, growth-tracking-playbook, internal-linking-optimizer, keyword-research, marketing-funnel, md-visual-workflow, memory-management, meta-tags-optimizer, nanobanana2-image-gen, on-page-seo-auditor, orca-cli, orca-conductor, orchestration, payment-mor-core, payment-mor-migration, performance-reporter, postgres-safe-verification, rank-tracker, react-best-practices, repo-rules-bootstrap, rottie-conductor, rottie-gui-qa, sandbox-sdk, schema-markup-generator, seo-content-writer, serp-analysis, supabase-multi-project-ops, super-conductor, symphony-setup, technical-seo-checker, threads-trend-check, turnstile-spin, vercel-deploy-claimable, vercel-react-best-practices, vision-click, web-ai, web-design-guidelines, web-perf, workers-best-practices, workflow-bootstrap, wrangler

## (2) 4도구 256항목 검증

64개 스킬 × 4도구 = 256 항목.

| 항목 | 값 |
|---|---|
| total_entries | 256 |
| LINK_OK(resolves=Y + SKILL.md 읽힘) | 162 |
| ABSENT(원래 없던 항목, 실패 아님) | 94 |
| BROKEN_LINK | 0 |
| REAL_RESIDUAL(외부 REAL 독립 복사본 잔여) | 0 |
| FAIL(resolve 실패 또는 SKILL.md 없음) | 0 |

도구별: `.claude/skills` ok=64/absent=0, `.codex/skills` ok=39/absent=25, `.gjc/skills` ok=24/absent=40, `.agents/skills` ok=35/absent=29.

### ABSENT 이름 (도구별, 원래 없던 항목)

`.codex/skills` ABSENT 25: alert-manager, aside-browser, backlink-analyzer, competitor-analysis, conductor, content-gap-analysis, content-quality-auditor, content-refresher, domain-authority-auditor, entity-optimizer, geo-content-optimizer, git-push, internal-linking-optimizer, keyword-research, memory-management, meta-tags-optimizer, on-page-seo-auditor, performance-reporter, rank-tracker, react-best-practices, schema-markup-generator, seo-content-writer, serp-analysis, technical-seo-checker, vercel-deploy-claimable

`.gjc/skills` ABSENT 40: agents-sdk, alert-manager, aside-browser, backlink-analyzer, cloudflare, cloudflare-email-service, competitor-analysis, conductor, content-gap-analysis, content-quality-auditor, content-refresher, domain-authority-auditor, durable-objects, entity-optimizer, geo-content-optimizer, git-push, internal-linking-optimizer, keyword-research, memory-management, meta-tags-optimizer, on-page-seo-auditor, orca-cli, orchestration, payment-mor-core, payment-mor-migration, performance-reporter, rank-tracker, react-best-practices, sandbox-sdk, schema-markup-generator, seo-content-writer, serp-analysis, technical-seo-checker, turnstile-spin, vercel-deploy-claimable, vercel-react-best-practices, web-design-guidelines, web-perf, workers-best-practices, wrangler

`.agents/skills` ABSENT 29: alert-manager, backlink-analyzer, competitor-analysis, conductor, content-gap-analysis, content-quality-auditor, content-refresher, domain-authority-auditor, entity-optimizer, geo-content-optimizer, git-push, internal-linking-optimizer, keyword-research, marketing-funnel, memory-management, meta-tags-optimizer, on-page-seo-auditor, payment-mor-core, payment-mor-migration, performance-reporter, rank-tracker, react-best-practices, schema-markup-generator, seo-content-writer, serp-analysis, technical-seo-checker, vercel-deploy-claimable, vercel-react-best-practices, web-design-guidelines

## (3) 보존본 21곳 재검사

`.staging/independent-skill-copies/` 하위 보존본 21곳이 모두 존재하고 현재 정본과 내용 해시가 동일함.

### codex 11곳 (전부 IDENTICAL)

agents-sdk(3bb23ff8533e), cloudflare(26fe06b23045), cloudflare-email-service(28626d842e95), durable-objects(78906d3027ea), sandbox-sdk(8aa3a753b15c), turnstile-spin(ce9fb5540712), vercel-react-best-practices(c361d11d701a), web-design-guidelines(3d6aa5a4d840), web-perf(4f20e8b16b77), workers-best-practices(5a072f6c0935), wrangler(76e84c314099)

### agents 10곳 (전부 IDENTICAL)

agents-sdk(3bb23ff8533e), aside-browser(3da99e809693), cloudflare(26fe06b23045), cloudflare-email-service(28626d842e95), durable-objects(78906d3027ea), sandbox-sdk(8aa3a753b15c), turnstile-spin(ce9fb5540712), web-perf(4f20e8b16b77), workers-best-practices(5a072f6c0935), wrangler(76e84c314099)

총 보존본: identical=21, differ=0.

## (4) validate.sh 결과 — **FAILED (exit 1)**

- 기대값: exit code 0
- 실측값: exit code 1
- 실패 7개: 전부 `skills/orca-conductor/scripts/tests/test_select_routing_pair.py`

실패 목록:
1. test_kimi_sol_when_glm_is_unavailable (기대 provider=kimi, 실측 openai)
2. test_luna_takes_over_when_kimi_is_exhausted_and_terra_is_disabled (기대 model=gpt-5.6-luna, 실측 gpt-5.6-terra)
3. test_opus_experiment_is_closed_outside_twenty_percent_slot (기대 model=gpt-5.6-luna, 실측 gpt-5.6-terra)
4. test_experiment_bucket_is_independent_per_effort (기대 experimental entries=3, 실측 6)
5. test_disabled_model_stays_registered_but_is_never_routed (기대 terra enabled=False, 실측 True)
6. test_glm_and_kimi_max_developer_experiments_require_strong_reviewer (기대 experimental=True, 실측 False)
7. test_opus_experiment_respects_anthropic_quota_exhaustion (기대 model=gpt-5.6-luna, 실측 gpt-5.6-terra)

CONFIG 경로: `skills/orca-conductor/references/routing-providers.json` (테스트 11행 참조)

### 원인 분석 (이행과 무관함)

- `git diff 4564e9c HEAD -- skills/orca-conductor/references/routing-providers.json skills/orca-conductor/scripts/tests/test_select_routing_pair.py` 결과 빈 출력 = 두 파일이 이행 시작점(백업 기준점 4564e9c)부터 현재 HEAD(b8aeeed)까지 변경 없음.
- 즉 실패는 라우팅 CONFIG와 테스트 기대값 사이의 기존 불일치로, 이행/검증 작업과 무관함.
- 첫 152 테스트는 passed, 추가 라우팅 라운드에서 7 failed / 33 passed.

## (5) git 상태·dirty 보존

- worktree 변경: `docs/TODO.md`(M), `docs/kyle-inbox.md`(M), `.commandcode/`(??). 기존 dirty 3종 보존됨.
- 이번 검증 턴에서 다른 파일 건드리지 않음(결과 파일은 본 커밋에만 추가).

## 종합 판정

이행 자체 검증((1)(2)(3)(5))은 전부 통과: 정본 64개 일치, 4도구 256항목 REAL_RESIDUAL=0/BROKEN=0/FAIL=0, 보존본 21곳 IDENTICAL, dirty 보존.

(4) validate.sh exit 1은 이행과 무관한 기존 라우팅 테스트 불일치이나, 작업 카드가 "종료 코드 0을 확인"을 요구했으므로 해당 조건은 충족되지 않았다. 수정은 금지되어 있으므로 실측값 그대로 보고한다.
