# 명령어 레퍼런스 (역할별 정리)

kyle이 지시할 때 쓰는 동사와 실제 명령의 대응표. 지휘자는 이 표의 명령만으로 전체 흐름을 조립한다.

## 오케스트레이션 — 카드와 발령

| kyle의 말 | 명령 | 하는 일 |
|---|---|---|
| "카드 만들어" | `orchestration task-create --spec "..."` | 주문서 한 장 작성 (의존성은 `--deps`) |
| "카드 뭐 있어?" | `orchestration task-list` | 주문서 꽂이 확인 — **모든 판의 시작점** |
| "카드 스윕" | `orchestration task-list --brief --json` | spec 160자 축약 스윕 (2026-07-27 추가 — spec 전문 필요 시만 --brief 해제) |
| "발령해" | `orchestration dispatch --task <ID> --to <핸들> --inject` | 카드 1장을 특정 일꾼에게 정식 발령 |
| "보고 기다려" | `orchestration check --wait --types worker_done,escalation,decision_gate` | 사서함 앞 대기 (단독 사용 금지 — mechanics.md 감시 규칙) |
| "확인만 (읽음 소비 없이)" | `orchestration check --peek` / `check --all` | 미확인 확인·전체 이력 — relay·순찰·외부 감독용 (2026-07-27 추가) |
| ~~"순찰"~~ | `orchestration run` — **사용 금지** | 카드-워크트리 짝을 몰라 멀티 랠리 오염 위험 (안전 규칙 7) |
| "승인/반려" | `orchestration gate-resolve --id <게이트> --resolution "..."` | 관문에 도장 찍기 |
| (지휘자 내부용) | `orchestration send / ask / reply / inbox / task-update / dispatch-show / gate-create / gate-list` | 쪽지·질문·카드 상태 수정·현황 조회 |
| ⚠️ "장부 초기화" | `orchestration reset --all` | **전체 카드·메시지 삭제. kyle 승인 후에만** |

## 일꾼 — 방과 사람

| kyle의 말 | 명령 | 하는 일 |
|---|---|---|
| "방 만들어" | `worktree create --repo <선택자> --name <이름> --no-parent` | 격리 작업 복사본 생성 |
| "일꾼 켜" | `terminal create --worktree <id> --command '<CLI+모델+강도>'` | 모델/강도 지정은 여기의 command에서 (프리셋: roster.md) |
| (지휘자 내부용) | `terminal wait --for tui-idle` / `read` / `send` | 켜짐 대기 / 화면 읽기 / 말 걸기·신뢰창 처리 |
| "현황판" | `worktree ps` | 전체 워크트리·일꾼 요약 |
| ⚠️ "방 철거" | `terminal stop` → `worktree rm --force` | **kyle 승인 후에만, 개별 실행** |

## 조립 공식

- **수동 감독** = task-create → dispatch → watch-card.sh 감시 (반복)
- 첫 명령은 항상 `task-list`(장부 확인)다.
