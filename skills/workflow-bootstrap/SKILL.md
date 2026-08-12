---
name: workflow-bootstrap
description: Install or normalize a reusable multi-agent workflow core in any git repository. Use when the user wants to reuse the CosmeticSaaS-style Kimi/Claude/Codex workflow in another project, asks to scaffold a workflow orchestrator, wants default daily logs and guide files auto-bootstrapped when missing, or wants project-specific overrides kept minimal while core defaults stay shared. Trigger on requests like "이 workflow 다른 프로젝트에도 쓰게 해줘", "워크플로우 스킬처럼 만들어줘", "오케스트레이터 설치해줘", "다른 레포에도 같은 개발 플로우 붙여줘", or "CLAUDE.md 공통 규칙도 같이 일반화해줘".
---

# Workflow Bootstrap

## 사람용 요약

이 스킬은 CosmeticSaaS에서 만든 `workflow/` 방식을 다른 프로젝트에서도 재사용할 수 있게 설치하거나 정리하는 스킬이다.

핵심 아이디어는 단순하다.

- 공통 엔진은 최대한 그대로 가져간다.
- 프로젝트마다 조금 다른 부분만 override 한다.
- override 파일이 없으면 코어 기본값으로 바로 동작하게 만든다.
- `docs/daily/`, `AGENTS.md`, `CLAUDE.md` 같은 기본 구조도 없으면 자동 세팅한다.

즉, "매 프로젝트마다 새로 발명"하지 않고 "기본 패키지를 꽂고 필요한 것만 조정"하는 방식이다.

## 이 스킬이 만드는 구조

기본 설치 대상은 아래 3가지다.

1. `workflow/`
   - 오케스트레이터와 공통 코어
2. `workflow/workflow.yml`
   - 선택 override 파일
3. 프로젝트 가이드 연결
   - `AGENTS.md`, `CLAUDE.md`, `docs/daily/` 같은 기본 운영 규칙 연결
4. `assets/workflow-core/`
   - 다른 프로젝트에 바로 복사할 수 있는 공통 코어 스타터 템플릿

원칙:

- 설정이 없으면 코어 기본값을 사용한다.
- 프로젝트가 특별하면 `workflow.yml`에서 일부만 override 한다.
- `CLAUDE.md` 전체를 통째로 덮어쓰지 않고, 공통 운영 블록만 옮긴다.

## Quick Start

1. 먼저 `references/default-conventions.md`를 읽는다.
2. 현재 저장소 구조를 확인한다:

```bash
pwd
git rev-parse --show-toplevel
ls -ld AGENTS.md CLAUDE.md docs docs/daily workflow 2>/dev/null
git branch --show-current
git branch --list main dev
```

3. 아래를 판단한다.
   - `workflow/`가 이미 있는가
   - `docs/daily/`가 있는가
   - `AGENTS.md` 또는 `CLAUDE.md`가 있는가
   - 기본 브랜치는 `main`, `dev`, 기타 중 무엇인가
4. 없으면 코어 기본값으로 생성한다.
5. 다르면 `workflow.yml`에 override 를 추가한다.
6. `CLAUDE.md`에는 공통 운영 규칙만 추가하거나 병합한다.
7. 최종적으로 `references/apply-checklist.md` 기준으로 검증한다.

## 설치 모드

### 1) 새 프로젝트 부트스트랩

이 모드는 `workflow/`가 아직 없거나, 다른 프로젝트에 처음 붙일 때 사용한다.

수행 내용:

- `workflow/` 골격 배치
- `workflow.yml` 기본값 생성
- `docs/daily/`가 없으면 생성
- `AGENTS.md` / `CLAUDE.md` 탐색
- 공통 운영 블록을 기존 가이드에 병합

### 2) 기존 workflow 정규화

이 모드는 이미 workflow 비슷한 게 있지만 구조가 제각각일 때 사용한다.

수행 내용:

- 현재 `workflow/`와 기존 스크립트 비교
- 공통 코어와 프로젝트 고정값 분리
- 기본값은 코어로 되돌리고, 예외만 `workflow.yml`로 이동
- runtime 산출물과 코어 파일 분리

## 공통 코어로 보는 것

아래는 기본적으로 공통으로 가져간다.

- orchestrator CLI
- task state/store
- agent executor
- step runner
- worktree manager
- artifact/log manager
- 기본 daily 템플릿
- 기본 guide 탐색 규칙
- 기본 브랜치 정책
- 기본 리뷰 verdict 파싱
- 기본 충돌 자동 해결 규칙

이 항목들은 특별한 이유가 없으면 프로젝트마다 다시 설계하지 않는다.

## 선택 override 로 보는 것

아래는 다르면 `workflow.yml`로 override 한다.

- `daily.dir`
- `daily.tools`
- `branch.base_branch`
- `branch.merge_mode`
- `guides.priority`
- `conflicts.combine_patterns`
- agent command / flags 추가 옵션

중요:

- override 는 예외만 적는다.
- 코어 기본값을 중복 복사하지 않는다.

## `CLAUDE.md` 일반화 원칙

프로젝트 가이드에서 아래를 분리해서 본다.

### 공통 운영 규칙으로 옮길 것

- Why 먼저
- 영향분석
- 문서화 필수
- worktree 기반 작업
- daily 로그 작성
- 다중 에이전트 역할 분리
- 변경 후 흐름 기준 재검토

### 프로젝트 전용으로 남길 것

- 도메인 설명
- 라우트 구조
- 모델/스키마 설명
- 디자인 레퍼런스
- 용어사전
- 프로젝트만의 배포 규칙

`CLAUDE.md`를 일반화할 때는 `assets/templates/claude-workflow-block.md`를 기준으로 병합한다.

## 기본 자동 세팅 원칙

설치 시 아래가 없으면 생성한다.

- `workflow/`
- `workflow/tasks/`
- `docs/`
- `docs/daily/`
- 오늘 날짜의 daily 디렉토리
- tool 로그 파일 (`codex.md`, `claude.md`, `kimi.md`, `opencode.md`)

기본 탐색 우선순위:

1. 명시적 `workflow.yml`
2. 기존 파일 구조 탐지
3. 코어 기본값

## 품질 기준

- 설정이 없어도 바로 돌아가야 한다.
- 기본 브랜치는 자동 탐지하되, 틀릴 가능성이 있으면 `workflow.yml`로 쉽게 override 가능해야 한다.
- `CLAUDE.md`는 통째로 교체하지 않고 공통 운영 블록만 병합해야 한다.
- runtime 데이터(`workflow/tasks/*`)는 코어 템플릿과 분리해야 한다.
- 다른 프로젝트에 적용할 때 hard-coded 절대경로를 남기지 않는다.

## References

- `references/default-conventions.md`
- `references/apply-checklist.md`
- `references/claude-generalization-guide.md`
- `assets/templates/workflow.yml`
- `assets/templates/claude-workflow-block.md`
- `assets/workflow-core/`
