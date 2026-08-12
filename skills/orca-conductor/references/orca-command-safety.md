# orca 명령 안전 원장 — 실측 검증된 시그니처와 위험 등급

## Why

2026-08-12 실사고 직전 사례: 터미널 1개를 닫으려고 `terminal stop`을 쓰기 직전, help 실측으로 그것이 **워크트리 전체 종료**임을 발견했다(같은 워크트리의 새 감독까지 죽을 뻔). 같은 날 플래그 오기억 4건(`send --title`, `run-create --purpose`, `terminal send --submit`, `orchestration.mjs` 경로). 명령 지식이 세션 기억에만 있으면 매번 재학습하고 가끔 틀린다 — 그래서 원장으로 박는다.

## 사용 규칙

1. **위험 등급 ▲(범위 파괴)·■(상태 변경) 명령은 실행 전 이 원장을 확인한다.** 원장에 없으면 `--help`를 실측하고, 결과를 이 파일에 추가한 뒤 실행한다 (다음 세션이 재학습하지 않게).
2. 등급 기준: ●(읽기 전용 — 자유) / ■(상태 변경 — 대상 1개 명시) / ▲(범위 파괴 — 대상보다 넓게 죽음, 실행 전 범위 재확인 의무).
3. 에이전트 창구: `curl -s 'http://127.0.0.1:8787/rules.txt?doc=command-safety'`

## 터미널

| 명령 | 등급 | 검증된 시그니처 | 함정 |
|---|---|---|---|
| `orca terminal list` | ● | `--json` | handle·title·connected·writable·preview. worktreePath로 필터 가능 |
| `orca terminal read` | ● | `--terminal <handle>` (`--cursor`,`--limit`) | `--tail` 없음. `--json`의 text 필드는 비어올 수 있음 — 평문 출력이 더 안정 (2026-08-12 실측) |
| `orca terminal wait` | ● | `--terminal <h> --for tui-idle --timeout-ms <n> --json` | 부팅류 대기 시한 3분 기본 |
| `orca terminal send` | ■ | `--terminal <h> --text "..." --enter` | **`--submit` 플래그 없음 — `--enter`다** (2026-08-12 실측). omo 대상은 한 줄만 |
| `orca terminal create` | ■ | `--worktree "id:<repoId>::<path>" --title ... --command ... --json` | 응답에 handle이 안 올 수 있음 — list로 재확인 (2026-08-12 실측) |
| `orca terminal close` | ■ | `--terminal <handle>` (`--tab`) | **pane 1개만 닫는 개별 종료 — 정리 작업의 표준** |
| `orca terminal stop` | ▲ | `--worktree <selector>` | **터미널 지정 불가 — 워크트리의 터미널 전부 종료.** 개별 종료로 착각 금지 (2026-08-12 사고 직전). 같은 워크트리에 살아 있는 감독·작업자가 있으면 참사 |

## 오케스트레이션 (orchestration)

| 명령 | 등급 | 검증된 시그니처 | 함정 |
|---|---|---|---|
| `check` | ■(수령) | `--run <runId> --peek`(비파괴) / `--run <id>` + `--ack <deliveryId>` | deliveryId는 `result.deliveryId` (camelCase). 본문 원시 개행 → `json.loads(strict=False)` |
| `send` | ■ | `--from <runId> --to run:<runId> --type status --subject "..." --body "..."` | **`--title` 없음 — `--subject`다.** 교차 Run은 `--from`+`--to`만(`--run` 병용 시 run_not_found, mechanics 2절). **reply 금지**(발신 handle로 돌아가 companion이 못 집음) |
| `run-create` | ■ | `--objective "..."` | **`--purpose` 없음 — `--objective`다.** 실행 터미널을 그 Run에 바인딩하므로 **슈퍼 터미널에서 실행 금지** — 판 Run은 감독이 자기 터미널에서 만든다 (2026-08-12 재확인) |
| `run-use` | ■ | `--run <runId>` | 코디네이터 터미널 재바인딩 — 자기 신분이 바뀐다 |
| `inbox` | ● | `--limit <n>` (`--terminal <h>`) | 전 수신자 조회. 죽은 명패의 read=0 편지는 소비 수단 없음(살아있는 터미널만 check 가능, 2026-08-12 실측) |
| `gate-resolve` | ■ | 관문 1개 지정 | 읽음(read=1)은 kyle 인지가 아니다 — resolved는 사용자 명시 답만 |
| `reset` | ▲ | scope 명시 | 상태 스코프 초기화 — 슈퍼는 쓰지 않는다. 필요하면 kyle 관문 |

## 워크트리

| 명령 | 등급 | 검증된 시그니처 | 함정 |
|---|---|---|---|
| `orca worktree list` | ● | `--json` | id는 `<repoId>::<절대경로>` 형태 |
| `orca worktree create` | ■ | `--repo id:<repoId> --name <이름> --no-parent --json` | `--name`이 브랜치명이 됨 — 레포 규칙에 맞게 즉시 개명 (mechanics 1절) |
| `orca worktree remove` | ▲ | 대상 1개 | 미커밋 변경 유실 가능 — dirty 확인·백업 후. 판 종료 절차에서만 |

## 기타 CLI (오늘 실측분)

- `node .../orchestration.mjs` 경로는 **존재하지 않는다** — 오케스트레이션 CLI는 `orca orchestration ...`뿐 (2026-08-12 실측).
- 대시보드 재시작: 정확한 PID를 `ps`로 잡아 `kill <PID>` 후 재기동 — 이름 기반 pkill 금지.
