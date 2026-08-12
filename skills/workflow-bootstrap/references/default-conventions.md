# Workflow Core 기본 규칙

## 기본 철학

- 코어는 기본값을 이미 알고 있어야 한다.
- 프로젝트에 설정이 없으면 기본값으로 바로 작동해야 한다.
- 프로젝트가 다른 경우에만 `workflow.yml`에서 일부만 override 한다.

## 기본 경로 규칙

- workflow 루트: `workflow/`
- 태스크 저장소: `workflow/tasks/`
- daily 로그 루트: `docs/daily/`
- 기본 가이드 탐색 순서:
  1. `AGENTS.md`
  2. `CLAUDE.md`
  3. `WORKFLOW.md`

## 기본 브랜치 정책

기본 탐지 순서:

1. `main`
2. `dev`
3. 현재 branch

기본값:

- branch prefix: `task/`
- merge mode: `--no-ff`
- 머지 후 worktree 정리: 사용
- 머지 후 브랜치 삭제: 사용

## 기본 daily 규칙

- `docs/daily/YYYY-MM-DD/` 아래에 기록
- 기본 tool 파일:
  - `codex.md`
  - `claude.md`
  - `kimi.md`
  - `opencode.md`
- 파일이 없으면 자동 생성
- 헤더가 없으면 기본 헤더 자동 생성

## 기본 리뷰 verdict 규칙

아래 단어를 우선 찾는다.

- `APPROVE`
- `REJECT`
- `HUMAN`

없으면 보수적으로 `HUMAN`으로 본다.

## 기본 충돌 자동 해결 규칙

기본 combine 대상:

- `docs/daily/**/*.md`
- `workflow/tasks/**/*.md`

그 외 충돌은 수동 해결 대상으로 남긴다.

## 기본 agent 실행 정책

에이전트 실행 플래그는 코어 기본값을 그대로 가져간다.

예시:

- Kimi: `--quiet --yolo -p`
- Claude: `--print --dangerously-skip-permissions --chrome -p`
- Codex: `exec --dangerously-bypass-approvals-and-sandbox`

프로젝트별 override 는 필요할 때만 추가한다.
