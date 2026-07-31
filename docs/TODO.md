# 작업 재개 기록

## Why

[kyle]의 Orca 판에서 구형 중계기의 보고 권한이 사라져도 감지 결과가 묻히지 않고 현재 프로젝트 감독이 복구 판단을 이어받게 한다.

## 현재 작업

| 브랜치 | 상태 | 목적 | 핵심 경로 |
|---|---|---|---|
| `agent/relay-legacy-fallback` | 보완 구현·검증 중 | 중계기와 현재 dispatched 작업자의 `[LEGACY READ-ONLY]` 보고 실패를 task+dispatch별로 감지하고 현재 감독을 한 번만 깨운다 | `skills/orca-conductor/scripts/conductor-companion.sh`, `skills/orca-conductor/references/mechanics.md` |

## 새 세션 재개 순서

저장소 또는 worktree 안에서 아래 순서로 현재 작업공간을 다시 찾는다.

```bash
git worktree list --porcelain
cd <agent/luna-effort-routing 브랜치의 worktree>
git rev-parse --show-toplevel
git branch --show-current
bash scripts/validate.sh
```

현재 브랜치가 `agent/relay-legacy-fallback`이 아니면 수정하지 않는다.

## 성공 기준

- 중계기가 lifecycle 보고에서 `[LEGACY READ-ONLY]`를 받으면 같은 명령을 재시도하지 않고 구조화된 표식을 남긴다.
- companion은 구조화된 표식 또는 기존 `legacy_read_only` 오류를 감지해 현재 프로젝트 감독을 한 번만 깨운다.
- companion은 실행 기록(run)을 자동 인수하거나 카드·dispatch 상태를 직접 바꾸지 않는다.
- 같은 표식이 화면에 남아 있어도 중복 기상이 발생하지 않는다.
- 서로 다른 task+dispatch에서 같은 원문 오류가 나면 각각 한 번씩 기상한다.
- 중계기가 표식을 작업자 화면에 보내지 않아도 companion이 작업자 화면의 거부 원문을 직접 감지한다.
- launchctl처럼 PATH가 축소된 환경에서도 실제 Orca 실행 파일을 찾아 `task-list/read/send` 끝단이 동작한다.
- `bash scripts/validate.sh`가 종료 코드 0이다.

## 작업자 경로 계약

- 모든 파일 범위는 저장소 루트 기준 상대경로로 적는다.
- 실행 전에 `git rev-parse --show-toplevel`과 `git branch --show-current`로 작업공간을 확인한다.
- worktree 절대경로는 문서에 고정하지 않고 `git worktree list` 결과를 사용한다.
