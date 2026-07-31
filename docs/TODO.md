# 작업 재개 기록

## Why

[kyle]이 가격 인하 뒤 Luna를 단순 잡일 모델이 아니라 저비용 현장 감독과 안전한 구현 작업자로 활용할 수 있게 한다.

## 현재 작업

| 브랜치 | 상태 | 목적 | 핵심 경로 |
|---|---|---|---|
| `agent/luna-effort-routing` | 구현·검증 중 | 중계기를 Luna High로 올리고 Luna XHigh를 안전한 구현 탐색 후보로 등록한다 | `skills/orca-conductor/references/mechanics.md`, `skills/orca-conductor/references/routing-providers.json` |

## 새 세션 재개 순서

저장소 또는 worktree 안에서 아래 순서로 현재 작업공간을 다시 찾는다.

```bash
git worktree list --porcelain
cd <agent/luna-effort-routing 브랜치의 worktree>
git rev-parse --show-toplevel
git branch --show-current
bash scripts/validate.sh
```

현재 브랜치가 `agent/luna-effort-routing`이 아니면 수정하지 않는다.

## 성공 기준

- 중계기와 순찰의 최신 표준 명령이 `gpt-5.6-luna` + `high`를 사용한다.
- Luna 작업자는 `xhigh`로 등록되며 `security`·`concurrency`에는 음의 성격 가산점을 가진다.
- Luna Max는 과거 내부 실패 기록 때문에 자동 기본값으로 승격하지 않는다.
- `bash scripts/validate.sh`가 종료 코드 0이다.

## 작업자 경로 계약

- 모든 파일 범위는 저장소 루트 기준 상대경로로 적는다.
- 실행 전에 `git rev-parse --show-toplevel`과 `git branch --show-current`로 작업공간을 확인한다.
- worktree 절대경로는 문서에 고정하지 않고 `git worktree list` 결과를 사용한다.
