---
name: briefing
description: kyle의 전체 활동을 브리핑 형식으로 정리한다. ~/Dev 저장소들의 최근 git 활동을 모아 개인/회사로 나누고, 개인 쓰레드·SNS 공백과 다음 액션 후보까지 짚는다. kyle이 "요새 뭐했지", "최근 작업 파악해줘", "전반적인 활동 정리", "브리핑해줘", "/briefing"이라고 하거나, 자기 활동 현황·프로젝트 근황을 궁금해하는 모든 경우에 사용한다. 특정 저장소 하나의 상태만 묻는 경우는 해당 없음.
---

# Kyle 활동 브리핑

## Why

kyle은 개인 프로젝트 여러 개와 회사 일을 병행한다. 저장소가 흩어져 있어 "요새 내가 뭘 하고 있지"를 한눈에 보기 어렵고, 특히 **만들기만 하고 밖으로 알리지 않는 상태(SNS/쓰레드 공백)** 를 스스로 놓치기 쉽다. 이 스킬은 흩어진 활동을 브리핑 한 편으로 모아주고, 공백과 연결고리를 짚어준다.

## 조회 기간

- 기본 14일.
- 인자로 기간이 오면 그걸 쓴다 (예: `/briefing 7d`, `/briefing 한달`).
- 날짜 지정도 가능:
  - 구간: `/briefing 07-11~07-16` 또는 `/briefing 2026-07-11~2026-07-16`
  - 시작일만: `/briefing 07-11부터` → 그 날부터 오늘까지
  - git 조회는 `--since="YYYY-MM-DD 00:00"` (구간 끝이 오늘이 아니면 `--until="YYYY-MM-DD 23:59"`)로 맞춘다. 연도 생략 시 올해로 해석하되, 미래 날짜가 되면 작년으로 본다.
- 직전 브리핑과 기간이 일부 겹치면, 출력 첫머리에 겹치는 날짜 범위를 한 줄로 명시한다.

## 절차

### 1. 결정론적 활동 증거 묶음 생성

브리핑을 쓰기 전에 반드시 수집기를 한 번 실행한다. 날짜는 브리핑 요청 범위에 맞춘다.

```bash
EVIDENCE_PATH="$(uv run --python 3.12 ~/.claude/skills/briefing/scripts/collect-evidence.py \
  --from YYYY-MM-DD \
  --to YYYY-MM-DD)"
```

- 출력 JSON 하나를 먼저 읽고 커밋, 등록된 작업공간(worktree)의 미커밋 변경, TODO, 완료 기록, 일지, 방향, 발행·성과, 사용자 검증, 이전 브리핑을 판단한다.
- 결과는 `~/.local/state/kyle-briefing/evidence/`에 권한 `0600`으로 저장된다. 저장소에 복사하거나 커밋하지 않는다.
- `warnings`가 비어 있지 않으면 브리핑에 영향이 있는지 확인한다. 꼭 필요한 자료가 경고 때문에 빠졌을 때만 해당 저장소를 직접 보완 조사한다.
- JSON에 이미 있는 Git·문서 자료를 다시 전수 탐색하지 않는다. 이 묶음이 브리핑의 단일 기준이다.
- 방향 판단이 필요하면 요청 기간과 별개로 현재 ISO 주차(월요일~오늘)의 evidence를 만들고 `build-weekly-compass.py --evidence <주간 evidence>`를 실행한다. 생성된 나침반의 `observation_signals`는 관찰 사실로만 표현한다.
- 나침반의 `warning_mode`가 `active`이고 `automatic_warnings`가 있을 때만 이를 자동 경고로 표현한다. 활성 정책 파일이 없거나 검증되지 않으면 실행기는 계속 `observation`을 유지한다.
- `check-warning-readiness.py`의 결과는 `~/.local/state/kyle-briefing/activation-readiness.json`에 저장된다. `waiting-for-operational-weeks`는 완료 주차 부족, `waiting-for-reviews`는 사람 검토 부족, `ready-to-activate`는 수동 활성화 가능을 뜻한다. 이 점검기는 정책을 만들거나 경고를 켜지 않는다.
- 월요일 자동화만 직전 월요일~일요일 전체 주차를 `--operational`로 생성한다. 과거 자료를 다시 돌린 backfill과 진행 중 주차는 관찰 주차 수에 넣지 않는다.
- 기간 안 커밋 또는 미커밋 변경이 있는 저장소를 활동 대상으로 삼는다. 커밋 수는 머지 커밋 제외 기준이다.
- 커밋이 가장 많은 상위 2개(필요하면 3개) 저장소는 `commits[].subject`, `commits[].paths`, `worktrees[].changes`, 기록 문서를 함께 읽고 "무엇이 바뀌었는지"를 문장으로 요약한다.

### 2. 개인 / 회사 분류

이름으로 추측하지 말 것. 기준 분류표:

| 구분 | 저장소 |
|---|---|
| 회사 (시큐어넷/모두의인증) | `moducerti_vibe`, `securenet-hub`, `securenetImWeb`, `certinumber-search` |
| 개인 | 나머지 전부 — designreels 계열, `Dongkyoung`, `kidi`, `super-koreman`, `Rottie`, `harulights`, `ticksidian`, `contents-core-kyle-thread`, `contents-core-kyle`, `outboundos`, `lecture-study-pipeline`, `coursecraft`, `Stocktrend`, `challenge-core`, `grill-me-workbench`, `memory-core`, `kyle-hub`, `any` 등 |

- 처음 보는 레포가 나오면 그 레포의 `CLAUDE.md`/`README.md`로 판단하고, 문서에 표기가 없으면 `git remote get-url origin`의 계정으로 판단한다 (`ChickenBreast-ky`=개인, `SecureNetCo`=회사). 그래도 애매하면 브리핑에 "분류 미확인"으로 표시하고 kyle에게 물어본다.
- 분류가 새로 확정되면 이 SKILL.md의 분류표에 직접 추가한다 (아래 "저장" 섹션의 읽기 전용 원칙보다 이 갱신이 우선 — 분류표가 낡으면 다음 브리핑이 또 틀린다).

### 3. 기록·방향 대조

- 활성 저장소의 `documents`에서 `todo`, `phase-history`, `daily`, `validation`을 함께 읽는다. 커밋만으로 완료나 사용자 검증을 추정하지 않는다.
- `compass_contract`와 주간 나침반을 대조해 선언한 방향과 실제 집중을 판단한다. 북극성 결과는 기간 안 변경된 완료·검증 기록 또는 실제 발행 성과처럼 구조화된 증거로만 인정한다.
- "어디에 적었더라" 류 의미 검색이 필요할 때만 memory-core를 쓴다:
  `node ~/Dev/memory-core/src/cli.mjs search "질문" --preview`
  (kyle-hub·securenet-hub의 .md 문서만 검색된다는 한계를 기억할 것)

### 4. 쓰레드/SNS 상태 점검

- `publications`의 `status`, `posted_date`, `performance`를 실제 발행 기준으로 쓴다.
- `status: posted`와 유효한 `posted_date`가 함께 없으면 발행했다고 말하지 않는다. 도구 개발 커밋은 콘텐츠 소재 후보일 뿐이다.
- 이번 기간의 개인 프로젝트 활동 중 SNS 소재가 될 만한 것(공개 이벤트, 완성된 기능, 배포)을 1~3개 뽑는다.

### 5. 이전 브리핑과 비교

- `previous_briefing`이 있으면 현재 증거와 비교해 "지난 브리핑 이후 변한 것"을 한 단락으로 짚는다. 없으면 이 섹션을 생략한다.

## 출력 형식

이 구조를 따른다 (kyle이 승인한 포맷):

```markdown
# 활동 브리핑 (기간: MM/DD ~ MM/DD)

## TL;DR
(2~3문장. 가장 큰 흐름 + 눈에 띄는 공백 하나)

## 활동 지도
**개인** — 레포별 한 줄 요약, 집중도 순
**회사** — 레포별 한 줄 요약

## 집중 프로젝트 딥다이브
(커밋 최다 2개 안팎 레포: 무엇이 어떻게 바뀌었는지 문단으로)

## 쓰레드/SNS 상태
(도구·발행·소재 후보)

## 지난 브리핑 대비 변화
(이전 브리핑 있을 때만)

## 다음 액션 후보
(최대 3개, 각각 왜 지금인지 한 줄)
```

## 스타일

- 전역 규칙대로: 쉬운 말 먼저, 개발 용어는 괄호, 결론 먼저.
- 커밋 메시지를 그대로 나열하지 말고 사람이 읽을 문장으로 녹인다.
- 판단이 섞인 말(예: "SNS 공백")은 근거 데이터를 한 줄 붙인다.

## 저장

- 기본은 대화에 출력만 한다 (읽기 전용 스킬).
- kyle이 "저장해줘"라고 하면 `~/Dev/kyle-hub/briefings/YYYY-MM-DD-briefing.md`로 저장하고 커밋한다. 회사 상세 내용이 민감해 보이면 저장 전에 확인한다.
