# kyle-agent-skills 작업 규칙

## Why

[kyle]의 개인 스킬을 검증 가능한 Git 변경으로 관리하고, 라이브 에이전트 환경과 개발 중 변경을 분리한다.

## 안전 경계

- `main`은 Claude·Codex·GJC가 실제로 읽는 라이브 원본이다.
- 기능 수정은 `/Users/fw_m1/Dev/.worktrees/kyle-agent-skills/` 아래 별도 worktree에서만 한다.
- 기존 스킬·링크를 지우지 않는다. 교체가 필요하면 먼저 `.staging/`으로 이동한다.
- 비밀값, 세션 원문, 실행 로그, 캐시를 커밋하지 않는다.
- 관련 없는 스킬이나 파일을 함께 수정하지 않는다.
- `git add -A`와 `git add .`을 사용하지 않고 경로를 지정해 stage한다.
- push와 PR은 [kyle]이 요청한 범위에서만 한다.

## 완료 기준

- `bash scripts/validate.sh`가 종료 코드 0이어야 한다.
- 변경 파일과 테스트를 같은 커밋에 둔다.
- PR 병합 전에는 라이브 `main` 링크 대상을 바꾸지 않는다.
- `main` 반영 뒤 살아 있는 Orca 프로젝트 감독이 있으면 다음 안전한 카드 경계에서 스킬을 재독하도록 통지한다.
