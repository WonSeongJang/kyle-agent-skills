# 프로젝트 감독 어댑터 계약

## Why

슈퍼감독이 특정 앱 명령에 묶이지 않으려면 모든 하네스가 같은 최소 상태와 제어 표면을 제공해야 한다.

## 역할 신분과 현재 주소

- 공식 신분은 `project+board+role+stable pane+run_id`다. Run은 우편함이고 pane은 자리다.
- handle은 신분·권한·수명 판정의 기준이 아닌 임시 라우팅 메타데이터다. 저장소에 `last_seen_handle` 캐시가 있어도 대상 선택에 쓰지 않는다.
- 전송이나 wake 직전에 role roster가 stable pane으로 current handle을 다시 찾아 한 번만 쓴다. 후보가 0개 또는 2개 이상이거나 pane 검증에 실패하면 title·옛 handle·캐시 fallback 없이 실패 닫힘한다.
- 생성 경로는 stable pane을 확인한 뒤에만 roster를 기록한다. pane을 못 찾으면 생성 자체는 성공할 수 있지만 명시 경고를 남기고 roster 기록은 건너뛴다.
- 신분의 수명은 역할마다 다르다. 작업자·검수자는 카드 단위 수명이고, 감독·relay·companion은 판이 살아 있는 동안 상주한다.
- 카드가 끝난 작업자·검수자 신분은 지우지 않고 `retired`로 settle 한다. retired 기록은 role·stable pane·run_id·`last_seen_handle`을 이력으로 보존하되 active 후보 해석에서는 제외되므로, 다음 작업이 옛 handle을 신분으로 잘못 쓰지 못한다.
- 세션 닫기 전 4단계를 전부 통과해야 retired 전환이 저장된다. (1) 그 신분의 active 후보가 정확히 1개 (2) 대상 task가 completed (3) dirty 변경을 증거 파일·체크포인트 커밋으로 옮겼다는 명시 확인 (4) 같은 Run의 공식 완료 보고 기록. 하나라도 빠지면 경고와 중단 사유를 구조화해 돌려주고 상태를 바꾸지 않으며, 이 fail-closed는 어떤 편지도 잃게 하지 않고 실제 터미널 종료를 자동 실행하지도 않는다. 어댑터별 실제 명령은 `orca-conductor`에만 둔다.

## 보고 계약 (2026-08-02 kyle 결정, 2026-08-03 구조화 — 이 절이 원본)

이 절이 상위 보고 계약의 원본이다. orca-conductor 등 다른 문서는 여기로 짧은 링크만 두고 내용을 복제하지 않는다.

- 작업자는 완료를 받으면 반드시 현재 Run에 `worker_done`으로 보고한다.
- 프로젝트 감독은 그 결과를 슈퍼 감독의 공식 Run으로 다시 상위 보고한다.
- 중요한 완료는 중계기 답장만으로 끝내지 않는다.
- PASS면 다음 카드, FAIL면 수정 카드, 질문이면 decision gate로 바로 이어간다.
- 상위 보고 누락은 중계기가 먼저 감지해서 깨운다.
- Run Delivery는 FIFO다. companion은 같은 Delivery의 유효 편지 처리와 모든 필요한 text-plus-Enter wake가 성공한 뒤에만 ack하며, 실패하면 ack하지 않아 같은 Delivery가 다시 온다.

### 구조화 상위 보고 형식

- 상위 보고는 `type=status` 편지에 payload `taskId`, `dispatchId`, `upperReport=true`, `outcome`, `nextAction`을 모두 채운다. 이 다섯 가지가 갖춰진 것만 구조화 상위 보고다.
- 구조화 상위 보고는 companion이 같은 `taskId+dispatchId`에 대해 정확히 한 번만 감독을 깨운다. 재읽기·중복 편지는 다시 깨우지 않는다.
- `upperReport`가 없는 일반 `status`는 깨우지 않지만 읽음 처리(ack)해 FIFO를 전진한다 — 오래된 status 한 통이 뒤의 중요 편지를 막지 못한다.
- 식별자가 빠진 lifecycle 편지(worker_done·escalation·decision_gate·구조화 status)는 카드 상태에 적용하지 않는다. companion은 `MALFORMED_LIFECYCLE_REPORT` 진단을 정확히 한 번 깨우고 그 편지만 격리한 채 같은 Delivery의 유효 편지를 계속 처리한 뒤 ack한다. 복구 재시도를 반복하지 말고, 본 쪽 작업자에게 식별자를 채운 재보고를 지시한다.

### 결정 관문 해결 기준

- `decision_gate` 편지의 읽음 처리(read=1)는 kyle이 인지했다는 증거가 아니다. companion·중계기·프로젝트 감독이 읽은 것은 전달 증거일 뿐이다.
- 관문은 슈퍼감독이 kyle과의 사용자 대화에 질문을 올리고 명시적인 답을 받아야 resolved다. 답이 없는 관문을 해결된 것으로 기록하지 않는다.
- 커밋 금지 관문처럼 슈퍼감독이 결정할 수 없는 항목(SKILL.md 판단 사다리의 "kyle에게 묻는 결정")은 대안 탐색을 이유로 오래 쥐고 있지 말고 즉시 kyle에게 질문한다.

## 필수 읽기 표면

각 프로젝트 어댑터는 아래를 즉시 반환해야 한다.

- `project_id`, 저장소 절대경로, 판 이름
- 프로젝트 감독 주소와 connected·writable 상태
- active·ready·blocked·completed 카드 요약
- 활성 작업자·검수자 handle, 모델, 하네스, 시작 시각
- 무거운 명령과 소유 PID, 예상 종료 조건
- 최근 worker_done·escalation·decision_gate·오류
- 마지막 검증의 입력 지문과 결과
- relay·companion 생존 상태

정상 상세 로그 전체를 슈퍼감독에게 보내지 않는다. 원문은 프로젝트 원장에 두고 snapshot은 요약과 주소만 돌려준다.

## 필수 제어 표면

어댑터는 아래 지시를 프로젝트 감독에게 전달하고 적용 여부를 읽을 수 있어야 한다.

- `PAUSE_NEW_DISPATCH`
- `STOP_EXACT_JOB`
- `REDUCE_VERIFICATION`
- `CLEAN_IDLE`
- `RESUME`
- `DECISION_GATE`

지시는 프로젝트 감독의 단일 작성자 권한을 통과한다. 슈퍼감독이 직접 카드 상태를 바꾸지 않는다.

## 도구별 연결

- Orca는 role roster로 현재 handle을 해석하고 Run 우편함으로 lifecycle을 전달한다. 실제 CLI 명령·환경변수·companion 실행 예시는 `orca-conductor`에만 둔다.
- 다른 하네스도 고정 주소를 장기 저장하지 않고, 해당 하네스의 stable identity에서 현재 입력 대상을 매 행동 직전에 검증해야 한다.
- 수명주기 권한은 언제나 실제 pane의 `taskId+dispatchId` 검증으로 판단한다. 다른 판 출력·판단·수정과 존재하지 않는 명령 추측은 금지한다.

## Rottie 연결

- 원장: `<workspace>/.rottie/orchestration/events.jsonl`
- 상태는 원장을 읽어 재구성하고 claims를 진실로 보지 않는다.
- 쓰기는 Rottie 프로토콜과 잠금 계약을 따르는 프로젝트 감독만 수행한다.
- 앱이 해당 workspace watcher를 실제로 보고 있는지 별도로 확인한다.

## Codex·Claude·자체 앱 연결

하네스가 고정 주소 전달을 지원하지 않으면 “현재 포커스된 창”을 주소로 사용하지 않는다. thread ID·terminal handle·session ID처럼 고정 식별자를 확보할 수 없으면 자동 입력을 금지하고 수동 인계를 요청한다.

## 2층 구조 원칙 — 계약은 도구 무관, 어댑터만 교체 (2026-07-27 kyle 확정)

지휘 체계는 두 층으로 나뉜다. 이 구분이 이 문서 전체의 전제다.

- **1층 지휘 계약 (어디든 들고 다닌다)**: 카드·단일 작성자·우편(검증되는 공식 통신)·결정 관문·companion(스크립트)/relay(저비용 AI) 역할 분담·fail-closed·사람 결정 관문. 어떤 하네스·런타임을 쓰든 이 계약은 그대로 유지한다.
- **2층 어댑터 (도구별로 갈아 끼운다)**: 우편 저장소(장부)와 초인종(기상)의 구현. Orca=DB+inject, 일반 터미널=tmux+파일 프로토콜, Rottie=네이티브 이벤트 push 후보.
- 한 줄: **계약은 어디든 들고 다니고, 초인종만 도구별로 갈아 끼운다. Rottie는 그중 가장 좋은 초인종+관제판 후보다.**
- 원본 비전: `~/Dev/kyle-hub/coding/2026-07-24-project-supervisor-orca-codex.md` — 특히 "예전 super-koreman과의 관계"(재사용하는 건 계약)와 "CLI 지휘자 기상 방식"(도구별 어댑터 3종) 절.

## 외부 감독의 기상(wake) 어댑터 — 하네스별 (2026-07-27 kyle 확인)

외부 감독(슈퍼감독)이 관문·치명 오류 편지를 받는 구조는 "명패 터미널(우편 주소) + 초인종(감시 스크립트)"인데, **초인종이 잠든 외부 감독을 실제로 깨우는 방법은 하네스마다 다르다**:

- **Claude Code**: run_in_background 작업이 종료·신호를 내면 하네스가 세션을 자동 재호출한다 — watch-inbox.sh를 백그라운드로 걸면 끝. (이 자동 기상은 Claude Code 한정 기능)
- **Codex 앱·CLI 등 자동 기상 없는 하네스**: 차선책 = 명패 터미널 + **크론잡류 주기 kicker**로 스크립트를 돌려, 신호 발견 시 외부 감독 입력창에 텍스트를 넣어 깨운다 (companion이 프로젝트 감독을 깨우는 방식과 동일 — Codex 앱에서 실사용한 방식).
- **Rottie**: 자체 오케스트레이션이 이 기상 기능을 네이티브로 제공할 가능성 — 이관 시 확인 후 여기 갱신.

원칙: 기상 신호 출력만 존재하는 상태를 end-to-end 기상 성공으로 간주하지 않는다. 하네스별로 "잠든 세션이 실제로 턴을 시작하는지"까지 확인해야 연결 합격이다.

## 연결 합격 기준

다음 흐름을 실제로 한 번 통과해야 연결됐다고 본다.

```text
snapshot 읽기
→ 프로젝트 감독에게 무해한 상태 조회 지시
→ 수신 확인
→ 적용 결과 읽기
→ 다른 프로젝트에 영향 없음 확인
```

## 슈퍼감독 세션 시작 의식 — 슈퍼 Run coordinator 인수 (2026-08-06 확정)

- 슈퍼감독의 공식 신분은 "슈퍼 Run(상설)의 현재 coordinator"다. 새 세션(새 pane)에서 시작하면 **가장 먼저 `orchestration run-use --id <슈퍼Run>`으로 coordinator를 인수**한다 (`--takeover-legacy`는 비-에이전트 pane에서 거부될 수 있음 — 일반 run-use가 인수 경로).
- 외부 권위 검증 표준: 프로젝트 쪽 companion·감독은 슈퍼 directive의 발신자를 "지정 super Run의 현재 coordinator_handle과 일치하는가"로 **매 검사 시점 동적 조회**해 판정한다. 고정 handle·제목·본문 패턴은 인증 근거가 아니다.
- 인수 전에 발신한 편지는 소급 인증되지 않는다 — 세션 시작 의식을 먼저 하라.
- 근거: 2026-08-06 conductor-hardening-1 P1 검수 중요 결함 "실제 super identity 미검증" — 발신 handle이 어디에도 등록되지 않은 채 운영되던 공백 발견.

### 알려진 계약 구멍 — 판 단위 보고에는 카드 ID가 없다 (2026-08-07 실사고)

구조화 상위 보고는 `taskId`+`dispatchId`를 필수로 요구한다. 그런데 **개시 선언·마감 보고처럼 판 전체를 다루는 보고에는 해당 카드가 없다.** 실제로 Rottie 통합 판의 마감 보고 첫 전송이 `dispatchId: null`로 거절됐고(부작용 없이 실패 닫힘, 장부 무변화), 감독은 직전 완료 카드의 ID를 빌려 재전송했다.

- 잠정 규칙: 판 단위 보고는 **가장 관련 있는 완료 카드의 ID를 앵커로 빌려 쓰되**, payload에 `scope: "board"`와 `anchorTask: <빌린 카드>`를 함께 넣어 그 카드의 결과 보고가 아님을 명시한다.
- 근본 해결은 장부 쪽이다 — 보고 범위를 **`card | board` 두 값**으로 구분하고, board 범위 보고는 카드 ID 없이 board 이름·Run ID로 결속한다(2026-08-07 kyle 결정으로 `run` 범위는 제외 — 판과 Run이 사실상 1:1이고 선택지가 늘면 실수가 는다). conductor-core(자체 장부) 설계에 이 구분을 넣는다.
- 이 구멍을 "null을 허용하자"로 풀지 않는다. 카드 보고에서 ID가 비면 그건 여전히 오류다(오늘 미결속 발령 사고와 같은 계열).
