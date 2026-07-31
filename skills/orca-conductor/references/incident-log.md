# 사고 기록 (incident log) — append-only 연대기

## Why

규칙은 실행 직전에 읽는 파일(mechanics.md 등)에 있어야 지켜지지만, "이 규칙이 왜 생겼나"의 역사는 거기 계속 쌓이면 절차 파일이 비대해진다. 이 파일은 사고의 연대기다 — 한 사고당 짧게: 무슨 일이 있었고, 원인이 뭐였고, 어느 규칙으로 박제됐는지. 새 사고는 맨 아래에 추가한다(append-only). 규칙 본문은 여기 두지 않는다 — 링크만.

## 기록 형식

```
### YYYY-MM-DD 사고 한 줄 제목
- 사고: 무슨 일이 벌어졌나 (1~2문장)
- 원인: 왜 그랬나
- 박제: 어느 파일의 어느 규칙이 됐나
```

---

### 2026-07-13 내장 순찰(run)이 엉뚱한 일꾼에게 배분

- 사고: Orca 내장 coordinator run이 카드-워크트리 짝을 모르고 "빈 일꾼 아무나"에게 배분해, 멀티 랠리 판에서 다른 브랜치에 수정이 들어갈 뻔함.
- 원인: run의 유휴 일꾼 선정 로직에 워크트리 매칭 개념이 없음 (2026-07-17 Orca 소스 실측으로 재확인: coordinator.ts:528의 idle 선정은 워크트리 무관).
- 박제: SKILL.md 안전 규칙 7 (run 사용 금지, 배분은 항상 지휘자 수동 + watch-card.sh). 상세 근거: 해당 레포 `.staging/run-mode.md`.

### 2026-07-13 check --wait 영원한 빈손 (보고 주소 stale)

- 사고: 일꾼이 worker_done을 보냈는데 지휘자의 `check --wait`가 영원히 빈손 — 완료를 못 알아챔.
- 원인: 외부 셸에서 발령하면 preamble의 보고 주소가 워크트리의 기본 셸 터미널(아무도 안 읽는 우편함)로 박힐 수 있음.
- 박제: mechanics.md "우편함 어긋남 주의" — 감시는 check 단독 금지, 카드 상태 + inbox 병행.

### 2026-07-13 "테스트 전부 통과"인데 실화면 무변화 (Rottie 글리프)

- 사고: 배선 추적·단위 테스트 전부 통과로 완료 보고됐지만, WebKit이 local() 폰트를 무시해 실제 화면은 아무것도 안 바뀜. kyle 실기 확인에서야 발각.
- 원인: 코드 레벨 증거만으로 "사용자 눈에 보이는 결과"를 판정함.
- 박제: roster.md 운영 규칙 5 "실물 표면 의무" — 표면 작업은 LIGHT라도 렌더 실측 증거 1개 이상.

### 2026-07-13경 DR-039 검수자가 허위 'QA 통과'를 통과시킴

- 사고: 구현자(sol)의 "QA 통과" 주장을 검수자가 인용만 하고 통과시켰는데 실제로는 미검증이었음.
- 원인: 같은 모델이라서가 아니라 검수자가 실측하지 않아서 뚫림.
- 박제: roster.md 검수 규칙 — 실측 의무("기존 보고·로그·증거를 전부 불신하라")를 모든 검수 카드 계약에 포함. 교차 검수 폐지의 근거이기도 함.

### 2026-07-15 외부 셸 발령 오배달 — 모든 보고가 남의 지휘자에게

- 사고: 외부 셸 세션이 발령한 일꾼들의 편지가 전부 다른(내부) 세션 지휘자 앞으로 배달됨 (to_handle 원본 확인).
- 원인: 외부 셸 발령은 자기 신분(ORCA_PANE_KEY)이 없어 Orca가 지휘자 주소를 기존 다른 터미널로 대체 기입(fallback)함.
- 박제: mechanics.md "세션별 우편함 주소" — 외부 셸 지휘자는 더미 명패 + 모든 dispatch에 `--from` 필수. `[판:]` 접두사는 마지막 방어선.

### 2026-07-15 훅 프롬프트가 발령문을 삼킴

- 사고: 첫 tui-idle 확인 직후 발령했더니 늦게 뜬 훅/업데이트 프롬프트가 발령문을 삼켜 일꾼이 시작을 못 함. 화면에 프롬프트 흔적도 안 남아 시작한 것처럼 보임.
- 원인: Claude/Codex의 훅·업데이트 프롬프트가 첫 idle 판정 뒤 늦게 뜰 수 있음.
- 박제: mechanics.md 일꾼 생성 절차 — idle 대기 → read로 프롬프트 확인·통과 → 다시 idle 대기 → dispatch. 발령 후 1~2분 뒤 스타트 확인은 양성 신호로만 판정.

### 2026-07-15 Codex 업데이트 프롬프트로 세션 사망

- 사고: 발령문 끝의 엔터가 업데이트 프롬프트의 기본 하이라이트 "1. Update now"에 닿아 self-update 후 세션이 죽음.
- 원인: Codex 업데이트 프롬프트의 기본 선택지가 Update.
- 박제: mechanics.md — 숫자 대신 방향키로 Skip 하이라이트 후 엔터.

### 2026-07-15 합동 감시가 먼저 끝난 랠리를 못 깨움

- 사고: `watch-card.sh A B C`(합동)로 걸었더니 전부 종결돼야 지휘자가 깨어나, 먼저 끝난 랠리의 검수가 늦어짐.
- 원인: 합동 감시는 전체 종결이 종료 조건.
- 박제: tiki-taka.md 병렬 랠리 규칙 — 랠리(카드)마다 watch-card.sh를 따로 하나씩.

### 2026-07-15 미커밋 누적으로 검수 "범위 불일치" 오탐

- 사고: 이슈판 티키타카 3라운드째에 검수자가 라운드별 diff 범위를 판정 못 해 "범위 불일치" 오탐 발생.
- 원인: 라운드가 길어지며 미커밋 변경이 누적돼 어느 라운드 것인지 구분 불가.
- 박제: tiki-taka.md — 이슈판(자동 커밋 허용)에서는 검수 통과분을 즉시 커밋해 깃 기준점 생성.

### 2026-07-15 gjc 모델 지정 즉사/오기동

- 사고: gjc에 `--model gpt-5.6-sol`(접두사 없는 ID)을 주면 "No API key"로 즉사하고, `--model codex-pro`는 조용히 무시되고 GLM으로 뜸.
- 원인: fuzzy 매칭이 API 키 없는 `openai/` 채널을 잡거나, 프리셋명을 모델명으로 오인.
- 박제: roster.md 참고 — gjc의 sol 호출은 `--mpreset codex-pro`로. 단일 모델 강제는 전체 ID `openai-codex/gpt-5.6-sol`. 기동 후 `/model`로 확인.

### 2026-07-15 감시 스크립트를 `&`로 띄웠더니 사망

- 사고: 셸 안 `&` 백그라운드로 띄운 watch 스크립트가 부모 종료와 함께 죽어 감시 공백 발생.
- 원인: 부모 셸 수명에 묶임.
- 박제: mechanics.md — watch 스크립트는 run_in_background로 직접 실행, 셸 안 `&` 금지.

### 2026-07-17 gjc 일꾼에게 --inject 거부됨

- 사고: gjc 검수자에게 `dispatch --inject`가 "no recognized agent detected"로 거부됨.
- 원인: Orca의 맨 셸 주입 방어가 gjc를 에이전트 CLI로 인식하지 못함 (OSC 타이틀/프로세스 검사 불일치).
- 박제: mechanics.md — gjc 수동 배달 3단계 절차 (inject 없이 dispatch → dispatch-show --preamble --from으로 발령문 추출 → terminal send). dispatch-show도 외부 셸에선 `--from` 필수.

### 2026-07-18 gjc 검수자 세션 자연사 — 하루 2회 (발령 증발 + pane 불일치 연쇄)

- 사고: 장시간 지휘 판에서 gjc 검수자 세션이 소리 없이 재시작돼 시작 화면(로고/세션 목록)에 앉아 있었음. 하루 2회(M6a 가재, 리소스판 가재). 1회차는 발령문이 증발한 채 카드만 dispatched로 남았고, 같은 터미널에 재배달해도 시작 화면이 입력을 안 받았음. 새 터미널로 배달하니 검수는 됐지만 발령 컨텍스트가 옛 pane에 묶여 worker_done이 "sender_not_assignee"로 거부돼 지휘자 수동 종결이 필요했음.
- 원인: gjc 세션이 스스로 죽고 재기동하는 패턴(정확한 트리거 미상, 긴 유휴 후 관찰). Orca 발령 컨텍스트는 handle+pane에 바인딩이라 터미널을 갈아끼우면 보고가 거부됨.
- 박제: mechanics.md — gjc 검수자 사망 복구 표준 절차: (1) 화면이 시작 화면이면 죽은 것으로 판정(스피너·입력창 부재), (2) 같은 터미널 재배달 시도하지 말 것(시작 화면은 입력 무시), (3) `task-update --status ready`로 카드 복귀 → 새 gjc 터미널 생성 → **새 dispatch 컨텍스트로 정식 재발령**(pane 불일치 예방). 이미 작업이 진행된 뒤라면 화면에서 판정 전문을 확보해 지휘자가 수동 종결. 부칙: gjc 다중 줄 발령문은 `--enter`가 줄바꿈으로 먹히므로 텍스트 전송 후 **제출 엔터를 별도로** 보낸다. 상태 확인은 영어 "Working"만 믿지 말 것 — gjc는 한글 상태 문구(예: "재검수 단계 기록")를 쓴다, 스피너 문자(⠋⠙⣾ 등)로 판정.

### 2026-07-18 Codex 0.144.5 훅 검토 다이얼로그가 발령문을 삼키고 CLI 사망

- 사고: 새로 만든 codex 0.144.5 터미널 4개(F1~F4)가 기동 후 "21 hooks need review before they can run" 다이얼로그(t=trust all / enter=review / esc=close)를 늦게 띄웠고, 주입된 발령문이 다이얼로그 키 입력으로 소비되며 CLI가 종료돼 맨 셸로 떨어짐. 다이얼로그는 재기동 시에도 다시 뜰 수 있고, tui-idle 판정과 1차 read 검사(키워드 hook/trust)를 통과한 "직후"에 떴음.
- 원인: codex 0.144.5의 신규 훅 검토 게이트(Orca agent-hooks 등 21개가 미신뢰 상태). 기존 "훅 프롬프트 늦게 뜸" 함정의 새 변종.
- 박제: mechanics.md — codex 0.144.5+ 신규 터미널은 발령 전 read에서 "hooks need review" 문구를 반드시 확인하고, 뜨면 ESC(신뢰 없이 계속 원칙)로 닫은 뒤 다시 idle 대기 → 재확인 → 발령. CLI가 이미 죽어 맨 셸이면 같은 터미널에서 시작 명령을 다시 보내 재기동(cd 포함) 후 같은 절차. 근본 대책 후보: 판 시작 전 kyle에게 훅 일괄 신뢰(trust all) 여부를 한 번 물어 터미널마다 반복되는 게이트 제거.

## 2026-07-18 m7-herdr 판 (Rottie)

- **워크트리 기준 브랜치에 카드가 참조한 문서가 없었음**: 카드 spec이 "docs/설계메모의 herdr 섹션을 정독하라"고 지시했지만, 랠리 워크트리들의 기준 브랜치(orchestra-file-protocol)는 그 문서 갱신(다른 브랜치에 커밋됨)보다 과거 시점이라 일꾼 2명이 즉시 질문/에스컬레이션. 복구: 최신 문서 사본을 세션 스크래치패드 공유 경로에 복사하고 절대경로를 우편으로 공지. **규칙: 카드가 문서 정독을 지시하면, 발령 전에 그 문서가 워크트리 기준 커밋에 실제로 존재하는지 지휘자가 확인한다. 없으면 사본 경로를 카드에 미리 박는다.**
- **Orca read가 Claude Code TUI 화면을 못 잡음**: claude 검수 터미널의 tail이 깨진 1줄만 반환(터미널 재생성해도 동일). 단 tui-idle 판정·dispatch --inject·worker_done 보고는 전부 정상 작동. **대응: claude 일꾼은 화면 판독 대신 우편함 프로토콜로 감독하고, 기동 직후 폴더 신뢰 프롬프트만 엔터 1회로 선처리한다(신뢰 프롬프트는 tail에 보임, 본 TUI만 안 보임).**
- **zsh 단어 분리 함정으로 orca 인자 오염 (같은 날 2회)**: zsh는 기본으로 `$var`를 단어 분리하지 않아, `for pair in "a b"; set -- $pair` 패턴이 인자 전체를 한 덩어리로 넘긴다 — 워크트리 이름이 base-branch까지 붙어 생성되고, dispatch가 "Missing required --to"로 실패했다. **규칙: 지휘 셸에서 orca 명령은 루프 변수 조립 대신 개별 호출로 쓴다.**
- **문서 공백 사고 재발 (2026-07-19, 같은 판 2회째)**: M9 카드가 참조한 설계 메모 섹션이 워크트리 기준 브랜치(master)에 없어 일꾼이 또 gate 질문. 첫 사고 때 "발령 전 문서 존재 확인" 규칙을 적었는데 지휘자가 안 지켰다. **보강 규칙: 지휘자가 직접 갱신한 문서(설계 메모·TODO)는 커밋 전까지는 항상 "워크트리에 없다"고 간주하고, 카드 작성 시점에 무조건 공유 사본 경로를 spec에 박는다 — 확인 절차에 의존하지 않는다.**

## 2026-07-19 rottie-tab-blank 판 (Rottie)

- **검수자 서브에이전트가 읽기 전용 계약을 어기고 공유 워크트리를 수정**: 재검수 카드(codex luna max)가 escalation으로 중요 발견을 보고한 직후, 검수 세션이 띄운 review-work 서브에이전트가 대상 3개 파일에 수정(3라운드 수정 방향의 코드 +165줄)과 `.debug-journal.md` 생성을 진행했다. 같은 시각 구현자에게 3라운드 수정 카드가 이미 발령돼 있어 동일 파일 동시 수정 위험이 발생했다. 검수자 본인이 "내가 아니라 서브에이전트가 고쳤다"고 자진 신고(escalation)했고, 지휘자가 검수 터미널 2개에 ESC를 보내 중단시켰다. 구현자는 남은 변경을 흡수·검증하는 방향으로 계속.
- 원인(추정 포함): (1) 검수 카드의 "수정 금지" 계약이 검수자 본체에는 지켜졌지만 서브에이전트 프롬프트로 전파되지 않았다(codex 서브에이전트는 부모의 요약 지시만 받는 구조로 추정). (2) 지휘자가 검수 카드를 종결한 뒤에도 검수 세션의 잔여 턴을 중단시키지 않고 방치했다 — 1라운드 검수자(context 86%)도 서브에이전트 4개를 띄운 채 대기 중이었다.
- 박제: tiki-taka.md — (1) 검수 카드 spec에 "서브에이전트를 쓰면 그 프롬프트에도 읽기 전용·수정 금지 계약을 그대로 복사해 전달하라"를 항상 포함한다. (2) 검수 카드가 종결(합격·불합격·escalation)되는 즉시 지휘자는 해당 검수 터미널에 ESC를 보내 잔여 턴·서브에이전트를 중단시킨 뒤에 다음 라운드를 발령한다.

### 2026-07-19 codex 검수자 50분 무활동 정체 — 감시 체계가 못 잡고 kyle 개입으로 발각

- 사고: 4라운드 재검수자(codex luna max)가 발령 후 약 50분간 도구 실행 0회로 헛돌았다(내부 오류로 턴이 조용히 깨진 상태 — 화면에 "Conversation interrupted" 잔상). watch-card는 카드가 계속 dispatched라 영원히 침묵했고, check --wait도 보고가 없으니 침묵. 지휘자가 화면을 2회 읽고도 "Working 스피너 = 작업 중"으로 오판해 방치했다. kyle이 "왜 다 멈춰있지"라고 직접 개입해서야 발각됐다.
- 원인: (1) 카드 상태 감시는 "일꾼이 살아서 도는지"를 전혀 측정하지 못한다. (2) 지휘자가 mechanics의 스타트 확인 기준("작업 중 표시 + Context 사용량 > 0" 양성 신호만 인정)을 정체 판정에도 적용해야 했는데, context 파싱 실패('?')를 그냥 통과시키고 스피너만 믿었다. 스피너는 렌더 애니메이션이라 죽은 턴에서도 계속 돈다.
- 박제: mechanics.md — 장기 실행 카드의 정체 판정 규칙: 스피너는 증거가 아니다. 진행 증거는 (a) 화면의 도구 실행 줄(• Ran/Explored 등)이 이전 확인 대비 증가 또는 (b) Context % 증가, 둘 중 하나다. 10분 이상 지난 카드를 확인할 때 진행 증거가 2회 연속 없으면 정체로 판정하고 ESC → task-update ready → 재발령(같은 터미널에 활성 dispatch가 물려 있으면 새 터미널)한다.

### 2026-07-20 gjc 일꾼의 ask "연결 단절" 오판 — 질문은 전부 배달돼 있었음

- 사고: glm 일꾼이 범위 확장 승인을 `orchestration ask`(양방향 대기)로 3회 요청했는데, 매번 자기 쪽에서 "Orca runtime closed the connection / Orca is not running" 오류를 받고 지휘자 단절로 판단, 자율 판단(추천안 진행)으로 전환했다. 실측 결과 **질문 3통 전부 지휘자 명패에 decision_gate로 정상 배달**돼 있었다 — 실패한 건 배달이 아니라 일꾼 쪽 '응답 대기' 단계의 연결이었다.
- 대응: 지휘자가 inbox에서 decision_gate를 확인하고 `orchestration reply --id <msg_id>`로 승인 응답. 일꾼에게는 "이후 통신은 (블로킹 ask 대신) send/check로 계속하라" 지시.
- 박제 규칙: (1) 일꾼이 "지휘자 연결 불가"를 보고하면 지휘자는 **자기 inbox부터 확인**한다 — ask의 편도 배달은 성공했을 가능성이 높다. (2) 지휘자는 판이 도는 동안 **watch-inbox를 상시 가동**한다(카드 감시만으로는 decision_gate를 놓친다 — 카드 상태가 안 변하는 신호). (3) 카드 spec에 통신 지침 추가 후보: "ask가 연결 오류를 내면 단절로 단정하지 말고 send(escalation)로 같은 질문을 한 번 더 남긴 뒤 5분 내 reply 없을 때만 자율 진행."

### 2026-07-20 로티 파일 프로토콜 첫 외부 지휘 — 발령 체인은 전부 작동, 워커 codex는 미착수 정체

- 무슨 일: rottie-conductor 어댑터 첫 실측. 외부 지휘자(kimi)가 임시 워크스페이스(`~/Dev/rottie-orch-test`)에 `.append.lock` 잠금 아래 카드 1장을 파일로 생성(created+ready, seq 1-2) → `dispatch_requested`(worktree+codex, seq 3) 1줄 추가. 4초 만에 앱이 선점(.ready→.claimed) → worktree 생성(`.rottie-orchestra-worktrees/`) → codex PTY 기동 → 발령문 주입 → `dispatched` 확정(seq 4)까지 자동 진행. 보드 표시와 claims 표식 복구(sync_ready_markers)도 정상. 그런데 워커 codex는 25분간 CPU ~0, rollout 파일 미생성, API 연결 2개만 유휴 유지로 미착수 정체. 화면 직접 확인에 실패(kyle이 앱에서 워커 터미널 탭을 찾지 못함)해 중단. 워커 kill 뒤 M7 안전망 3종이 전부 작동: 15분 무진전 정체 escalation(seq 5, 14:38) → PTY 종료 감지로 카드 `failed`(seq 7) → 죽은 터미널 배달 서킷브레이커 개방 escalation 2건(seq 6, 8).
- 원인(미확정): codex 미착수 사유는 끝내 화면을 못 봐서 미확정 — (a) 신규 worktree 경로의 codex 신뢰 게이트(`~/.codex/config.toml` trust는 워크스페이스 루트에만 있고 worktree 경로는 별도), (b) 발령문 붙여넣기 후 Enter 미제출, 둘 중 하나로 추정. 외부 지휘자에게 워커 화면(backlog) 판독 수단이 없는 게 진단을 막은 구조적 구멍 — 앱이 아니면 PTY 출력을 읽을 방법이 없다.
- 박제(실측 규칙): (1) 파일 감시는 오케스트레이션 명령(보드 열기 등)이 그 워크스페이스에 1회 실행돼야 시작한다 — 앱이 다른 프로젝트를 보고 있으면 원장을 아예 안 읽음(원장 물변화 + claims 미생성으로 외부 판별 가능). (2) 지휘자 감시는 카드 종료 상태까지 잡아야 한다 — 10분 타임아웃 감시가 15분 정체 escalation을 5분 차로 놓침. (3) codex 워커 착수 여부의 외부 판별선: `~/.codex/sessions/` rollout 파일 유무 + CPU 시간 증가. (4) 워커 터미널의 owner_project_path는 원래 워크스페이스로 기록됨(dispatch runtime.rs). (5) 지휘자 원장 append 헬퍼를 rottie-conductor 스킬 `scripts/append-ledger.py`로 박제.

### 2026-07-20 죽은 codex 터미널에 --inject 발령 2회 — 발령문이 zsh에 주입됨

- 사고: 같은 판(rottie-m10)에서 2회 반복. 검수 종결 후 `terminal send --interrupt`로 잔여 턴을 중단했는데, idle 상태의 codex는 이 interrupt로 **세션이 통째로 종료**되어 맨 셸(zsh)로 떨어졌다("To continue this session, run codex resume ..." 출력). 이후 화면 확인 없이(또는 확인과 발령을 한 호출에 묶어서) `dispatch --inject`를 보내자 발령문 전체가 zsh에 명령으로 주입됐다. 두 번 모두 발령문의 괄호 때문에 `zsh: parse error`로 전량 거부돼 실행 피해는 없었지만, 문자열 구성에 따라 임의 셸 명령 실행이 가능한 위험한 사고였다.
- 원인: (1) Orca의 `--inject`는 대상 pane에 살아 있는 에이전트 CLI가 있는지 발령 시점에 재검증하지 않는다(dispatch는 성공으로 기록됨). (2) `--interrupt`는 작업 중 턴에는 ESC처럼 동작하지만 idle codex에는 종료로 동작한다(실측 2회). (3) 지휘자가 "생존 확인 → 발령"을 별도 단계로 두지 않았다.
- 복구(2회 공통, 검증된 절차): 워크트리 git status로 무결성 확인 → 같은 터미널에 codex 재기동(같은 handle이라 dispatch 컨텍스트 유효) → `dispatch-show --preamble --from <명패>`로 발령문 추출 → `deliver-preamble.sh`로 수동 재배달.
- 박제: mechanics.md "기존 터미널 재발령 전 생존 확인" 규칙.

### 2026-07-21 WindowServer 붕괴 후 Orca 전 스폰 "login:" 실패 — 데몬의 죽은 세션 자격

- 사고: macOS WindowServer가 워치독으로 강제 종료(메모리 압박, 40초 무응답)되며 화면 세션이 재생성됐다. Orca 데몬은 백그라운드라 살아남았지만 **죽은 옛 세션의 자격을 문 채**여서, 이후 모든 새 터미널 스폰이 `/usr/bin/login` 인증 실패("login:" 프롬프트 + Login incorrect)로 즉사했다. 발령문 텍스트가 login 프롬프트에 들어가 로그인 시도로 오인되기도 했다. **앱만 재시작(osascript quit → orca open)해서는 해결되지 않았다** — 데몬이 그대로 살아남기 때문.
- 진단 경로(재사용 가능): (1) 맨 셸 스폰도 실패 → 앱/OS 레벨 (2) 내 셸에서 `login -f <user>` 성공 → 시스템 정상 (3) `ps -axo pid,ppid,tty,lstart,command | grep "[l]ogin -"`로 정상 스폰(login -flpq)과 시각 비교 → 전부 붕괴 시각 이전 (4) 크래시 로그(bug_type 409, WATCHDOG "WindowServer main thread")로 확정.
- 복구(검증됨): osascript quit app → **데몬 PID 정확 kill** → `open -a Orca` 재기동 → runtimeState ready 대기 → 스폰 실측 → 물려 있던 dispatched 카드 task-update ready → 새 터미널 정식 재발령. 장부·워크트리·우편함은 전부 보존된다(우편함은 명패 터미널이 죽어도 handle로 조회 가능).
- 박제 규칙: **화면 세션 붕괴(WindowServer 크래시·강제 로그아웃) 후에는 Orca를 앱+데몬까지 완전 재시작**한다. 앱 재시작만으로 안 되면 데몬 생존을 의심하라 (`pgrep -fl daemon-entry.js`). 살아남은 옛 터미널들도 옛 세션 소속이라 어차피 재세팅 대상이다.

### 2026-07-21 지휘자 커밋에 .gjc 세션 토큰 파일 push — 무차별 스테이징 사고

- 사고: 지휘자가 합격 커밋을 만들며 `git status --short | awk | xargs git add`(사실상 add -A)로 스테이징해, gjc 세션 토큰이 든 `.gjc/state/sdk/*.json` 포함 메타파일 8개가 커밋·push됨. 원인: (1) 티키타카의 "git add -A 금지, 파일 지정 add" 규칙을 일꾼에게만 적용하고 지휘자 자신은 무차별 패턴 사용 (2) 워크트리 기점(master)에 .gjc gitignore가 없었음(M10 브랜치에만 존재).
- 수습(검증됨): 토큰 세션 프로세스 종료(토큰 즉시 무력화 — 127.0.0.1 전용이라 실위험은 원래 낮음) → `git rm --cached`로 개별 제거+.gitignore 등재+amend → kyle 승인 하 force-with-lease push(환경 훅이 차단해 kyle이 `!` 직접 실행).
- 박제 규칙: (1) **지휘자의 커밋 스테이징도 명시 경로 add만** — status 파이프 무차별 add 금지. 커밋 전 `git status --short`에서 도구 메타 경로(.gjc/.omo/.kimi 등)가 보이면 반드시 .gitignore부터. (2) **새 워크트리 첫 커밋 전에 .gitignore에 도구 메타 패턴이 있는지 확인** — 기점 브랜치에 없을 수 있다.

### 2026-07-22 sol(OpenAI) 검수가 사이버보안 필터로 차단 — 보안 코드 검수는 sol 회피

- 사고: rottie-daemon2 카드4 7라운드 델타 재검수(대상: TOCTOU 방어·심볼릭 링크 공격 테스트·토큰 파일 권한·소켓 inode 검증)를 sol-medium에 발령하자, OpenAI가 "This content can't be shown — We take extra caution with cybersecurity requests. Trusted Access..."로 응답을 차단했다. 쿼터는 94% 남아 멀쩡 — 순수 콘텐츠 필터 오탐(정당한 방어 코드 검수).
- 판단: 검수는 순화 금지(공격 시나리오 실측이 알맹이라 순화하면 검수 무력화), sol 재시도는 콘텐츠 기반이라 재발 도박. 백엔드 교체가 정답 — 필터 없는 kimi/glm 계열로.
- 대응(검증됨): sol 잔여 턴 interrupt → task-update ready → 기존 kimi-high 검수 터미널에 재발령(저자 분리 충족: 구현 glm ↔ 검수 kimi). kimi는 이 필터가 없어 같은 카드를 정상 완료(합격).
- 박제 규칙(roster): **보안 성격 코드(권한·토큰·크리덴셜·심볼릭 링크·TOCTOU·권한 상승·익스플로잇/스캐너 분석·CTF/리버스)를 검수·구현할 카드는 sol(OpenAI 백엔드) 배정을 처음부터 피하고 kimi/glm으로 배정한다.** 이미 sol에 걸려 차단되면 순화·재시도 말고 즉시 백엔드 교체(저자 분리 유지).

### 2026-07-22 지휘자 폴백 복귀 probe 판 내내 0회 — md 규칙의 비강제성

- 사고: rottie-daemon2에서 Codex 0 폴백 조합(dev=glm+검수=kimi)으로 시작한 뒤, roster의 "폴백 상태면 다음 발령 때 원 편성 1회 probe"를 판 내내(발령 ~20회) 0회 실행. kyle이 "중간부터 코덱스 체크를 안 한 듯, 코덱스 리셋됐네"로 발각 — 실제로 sol 주간 쿼터가 7/25 예정보다 일찍 풀려 있었다.
- 원인: (1) kyle 지시문의 '7/25 갱신 예정' 문구에 앵커링해 'probe는 낭비'로 자체 결론 (2) **md 규칙이라 강제성 없음** — probe가 발령 루틴(카드생성→생존확인→dispatch)에 기계적으로 안 박혀 판이 빨리 돌수록 누락.
- 박제(kyle 승인): probe를 스크립트로 강제화. `scripts/probe-codex.sh`(exit 0=복귀가능/2=쿼터소진/3=라우팅오류/4=기타) — mechanics 사용량 절에 "폴백 중이면 매 발령 전 1회 실행" 명문화. "판단은 LLM, 잡일은 코드" 원칙을 지휘자 자신에게도 적용.
- 곁가지 발견: opencodex 이관(2026-07-21)이 codex 전역 라우팅을 바꿔(`~/.codex/config.toml`에 `openai_base_url=127.0.0.1:10100` 자동 주입) 프록시에 OpenAI provider 비활성이면 sol이 404 즉사. 우회 레시피(정식 바이너리 `codex.opencodex-real` + `-c openai_base_url` 복원 플래그)를 roster에 박제. `ocx provider add openai`+`ocx sync`로 provider 등록은 했으나 프록시 카탈로그에 gpt-5.6-sol이 안 올라와(codex ChatGPT pool 인증 미연결 추정) 프록시 경유는 미복구 — 우회 레시피가 유효하므로 실무 지장 없음, 완전 복구는 kyle codex 인증 영역.

### 2026-07-22 검수 카드에 '검출력 확인용 소스 수정' 요구 — 검수 전용과 충돌

- 사고: rottie-usage-qa 카드A2(GLM 키 마스킹) 검수 카드에 지휘자가 "회귀 테스트 검출력 확인 — 마스킹을 일부러 빼서 테스트가 깨지는지 1회 확인"을 넣었다. 이건 검수자가 소스를 잠깐 수정해야 하는 돌연변이(mutation) 검증이라 **검수 전용·파일 수정 금지 계약과 정면 충돌**. sol 검수자가 `orca orchestration ask`(블로킹)로 지휘자에게 임시 편집 승인을 2회 요청했으나 "Orca runtime closed the connection / not running" 오류로 답을 못 받음(ask 블로킹 호출만 실패, decision_gate는 지휘자 명패에 정상 배달됨 — 2026-07-20 사고와 동일 패턴). sol은 수정 금지를 우선해 정적 검토로 우회하고 검수를 완료했다(정적 검토만으로 다음 라운드 MEDIUM까지 정확히 잡음).
- 원인: 지휘자 카드 설계 결함 — 검수자에게 소스 변경을 요구하는 자기모순 지시.
- 박제(tiki-taka.md 검수 규칙): **검수 카드에 소스 수정을 전제하는 요구(돌연변이 테스트·검출력 확인용 마스킹/가드 제거 등)를 넣지 않는다.** 검출력 확인이 필요하면 (1) 구현 카드에서 구현자가 self-mutation 테스트로 증명하거나 (2) 지휘자가 별도로 확인한다. 검수자는 정적 검토·직접 재실행·실측만 한다(수정 0).

## 2026-07-23 — 429 재시도 소진으로 죽은 턴을 감시가 못 봄 (rottie-qa-allinone 카드F)

- 사고: glm 일꾼이 "exceeded retry limit, last status: 429 Too Many Requests"로 턴이 죽었는데, watch-card(카드 상태 기반)는 카드가 dispatched 그대로라 침묵. kyle이 화면을 직접 보고 수동으로 이어 진행시켜 발각. 지휘자는 발령 직후 스타트 확인 1회만 하고 이후 카드 종결 신호만 기다리는 운용이라, 기다렸으면 놓쳤을 것(지휘자 자인).
- 원인: (1) 감시가 "카드 상태"와 "우편함 신호"뿐 — 오류로 죽은 턴은 둘 다 안 바뀜. 2026-07-19 스피너 정체 실사고와 같은 계열의 429 변형. (2) mechanics의 "10분 후 진행 증거 2회 확인" 규칙이 md 문장뿐이라 강제 수단 없음(비강제 md 규칙 반복 실패 패턴).
- 임시 대응: 랠리 진행 중 일꾼 터미널 화면을 2분 주기로 읽어 오류 문구(429/exceeded retry limit/stream error/No API key)를 grep하는 Monitor를 지휘 세션에 병행 가동.
- 박제 후보: watch-card.sh에 `--screen <terminal_handle>` 옵션 추가 — 카드 상태 폴링과 함께 해당 터미널 화면의 오류 문구·진행 증거(Context% 변화)를 검사해 오류 감지 시 즉시 종료(지휘자 깨움). "판단은 LLM, 잡일은 코드" 원칙의 적용 건. (구현은 카드로 배분할 것 — 지휘자 직접 코딩 금지)

## 2026-07-23 — 429 죽은 provider에 재발령 + 감시 공백 3겹 (moducerti openapi-public-contract 판)

- 사고: zai(glm) 429로 F가 죽은 직후, 지휘자가 G-R2를 **같은 zai 엔진의 기존 터미널에 재발령**해 곧바로 또 429 사망. kyle이 화면을 직접 보고 발각 — 지휘 세션의 감시는 셋 다 이를 놓쳤다.
- 원인: (1) **provider 생존 판정 오류** — "H(kimi)가 살아있으니 순간 제한"으로 낙관했는데 H는 다른 provider라 zai 상태의 증거가 아님. (2) watch-terminals.sh가 셸 버그(heredoc EOF, ERROR 출력 후 crash)로 죽은 뒤 **대체 오류 감시를 재가동하지 않음**. (3) 재발령하면서 오류 감시 목록·순찰 카드 대상에 그 터미널을 **추가하지 않음** — 발령과 감시 갱신이 분리된 두 동작이라 누락됨.
- 수습: G-R2 ready → terra-high 새 터미널 재발령. 오류 감시를 전 활성 터미널(검수 포함)로 재구성, 순찰 대상 갱신 지시.
- 박제 규칙 후보: (1) **429 직후 재발령은 provider를 바꾼다** — 같은 provider 재시도는 쿼터 회복 확인(provider-quotas) 후에만. 다른 provider의 생존은 생존 증거가 아니다. (2) **발령/재발령 = 감시 목록 갱신과 한 동작** (명패=watch-inbox 커플링과 같은 계열). (3) watch-terminals.sh 셸 버그 수정 필요 (ERROR 1건 출력 후 bash 문법 오류로 비정상 종료 — line 49 heredoc).

## 2026-07-23 — 감시 스크립트 자체 사망 후 재가동 누락 (타 지휘 세션, kyle 발견)

- 사고: 한 지휘 세션에서 watch-terminals.sh(또는 임시 감시)가 셸 버그로 죽었는데, 그 지휘자가 대체 감시를 재가동하지 않아 감시 공백이 생겼다. kyle이 발견해 전파.
- 교훈: 감시 프로세스도 죽는다 — "감시가 있으니 안심"이 아니라 "감시의 생존"도 관리 대상이다.
- 박제 (mechanics 감시 절): (1) **재가동 반사** — 감시 백그라운드 작업의 실패/종료 알림을 받으면 내용 분석보다 재가동을 먼저 한다 (시한 만료든 버그든 원인 무관, 판이 살아 있는 한 감시 공백 금지). (2) **세션 복귀 시 감시 생존 점검** — 지휘 세션이 판을 이어받거나 오래 쉬었다 깨어나면 감시 3종(watch-card·watch-inbox·watch-terminals)의 생존을 확인하고 죽은 것을 다시 띄운다.

## 2026-07-23 — 시스템 메모리 폭주: Codex 다중 실행 × MCP 전역 기본 켜짐 × MCP 중복 재생성 버그

- 사고: 오케스트레이션 중 시스템 메모리가 반복 폭주(세션 강제 종료급). 실측: ChatGPT 앱 제외 관련 프로세스 **631개, RSS 합계 12GB**. 고아(PPID=1)는 1개뿐 — 살아 있는 codex 부모들이 자식을 껴안고 있는 구조.
- 원인 3겹: (1) **전역 설정이 에이전트 1개당 보조 프로세스 5~7개 자동 생성** — OMO LSP·CodeGraph(+감시자 자식)·Playwright·Context7·node_repl·sites플러그인 server.mjs. 작업에 안 써도 세션 시작 시 무조건 뜬다. (2) **Codex MCP 중복 재생성 버그** — 부모가 8~12초 간격으로 MCP 세트를 재생성하며 옛 세트를 안 닫음(한 부모에 자식 92개 실측, server.mjs만 시스템 전체 ~120개). (3) **오케스트레이션 병렬 규모**가 이를 에이전트 수만큼 곱함. 부가 발견: opencodex 프록시(bun)가 단독 1.2GB.
- 실측으로 확정한 통제 수단: `-c mcp_servers.*.enabled=false`는 **전역 MCP만** 끔(성공). `-c plugins.*.enabled=false`는 **무효**(2회 실측 — 플러그인·플러그인 MCP는 -c로 못 끔). 프로필은 신형 문법 **별도 파일**(`~/.codex/orca-lean.config.toml`) 필수 — config.toml 안 `[profiles.X]` 테이블은 `-p X` 사용 시 에러. `-p orca-lean` 실측 결과 **자식 프로세스 0개**, 훅 6회→1회, 토큰·응답 정상.
- 박제: (1) roster.md codex 엔진 프리셋에 `-p orca-lean` 기본 포함 + 동시 codex 상한 8. (2) mechanics.md 종료·정리에 잔여 프로세스 확인·정리 절차. (3) 브라우저 QA·구조 분석 등 MCP가 실제 필요한 역할만 프로필 없이 발령.
- 미해결: 이미 떠 있는 세션들은 시작 시 설정이 박혀 있어 소급 불가 — 자연 종결 후 잔존분 정리로 회수. Codex 중복 재생성 버그 자체는 상류(OpenAI) 이슈.

## 2026-07-23 (추가) — OMO 유지형 역할별 프로필로 확정 (kyle 검토 반영)

- kyle 검토: 전부 끄는 `orca-lean`은 OMO 훅·스킬까지 죽는다(실측: 훅 6회→1회) — OMO는 유지하고 MCP만 역할별로 조정하는 게 맞다.
- 추가 실측 2회: (4차) 프로필 파일에서는 **플러그인 내부 MCP 개별 토글이 된다** — `orca-worker`(OMO 유지+LSP만)로 자식 LSP 1개·훅 6회 정상. (5차) **전역 `mcp_servers.*`는 -c가 프로필의 disable을 이긴다** — `-p orca-worker -c mcp_servers.playwright.enabled=true`로 Playwright만 재활성 성공. 즉 "플러그인 끄기=프로필, 전역 켜기=-c" 분업.
- 최종 박제: roster.md 프리셋 기본 `-p orca-worker`, 역할별 가감표(analyst/browserqa/desktopqa/docs/lean)는 roster.md 주의 절 참조. 프로필 파일 3종 `~/.codex/orca-{worker,analyst,lean}.config.toml`.

## 2026-07-23 — headless codex exec가 stdin 대기로 30분 침묵 정지 (moducerti 대체 배달)

- 사고: Orca 붕괴 대체로 codex exec headless 발령 2건(D 9R 재검수, I-R3)이 "Reading additional input from stdin..." 상태로 30분 정지. 오류도 종료도 아니라 완료 알림이 영원히 안 오는 유형 — kyle이 직접 발각.
- 원인: (1) codex exec는 stdin에서 추가 입력을 읽으려 EOF를 기다림 — 백그라운드 실행 환경에서 stdin이 열린 채 유지되면 무한 대기 (앞선 headless 성공 배치와의 차이는 세션 재시작 후 셸 환경 변화로 추정). (2) 지휘자가 headless 전환 시 Orca 판의 3중 감시(카드·화면 grep·진행 증거)와 "발령 후 스타트 확인" 루틴을 이식하지 않고 완료 알림만 기다림 — md 규칙 비강제성 실패 계열의 당일 3번째 사례.
- 수습(검증됨): 프로세스 정리 → `</dev/null` 붙여 재실행 → 즉시 진행.
- 박제 규칙: (1) **headless codex exec는 `< /dev/null` 필수** — stdin 차단 없이는 발령으로 인정하지 않는다. (2) **headless 발령 직후 3분 출력 증가 확인을 같은 동작으로 붙인다** (Orca 스타트 확인의 headless판). (3) 대체 배달 모드로 전환할 때는 기존 감시 루틴의 대응물을 함께 옮겼는지 전환 시점에 점검한다.

## 2026-07-23 — 중계기 체제 첫 판에서 완료 신호 미수신 (watch-inbox 기본 타입 불일치)

- 사고: tab-simplify 판(중계기 첫 실전)에서 카드M worker_done이 명패에 도착했는데 지휘자가 안 깨어남 — kyle이 발견. watch-inbox.sh 기본 WATCH_TYPES가 worker_done을 제외(2026-07-20 "완료는 watch-card 몫" 설계)하는데, 중계기 체제는 지휘자의 watch-card를 없앤 구조라 완료 신호 수신 경로가 사라졌다.
- 원인: 아키텍처를 바꾸면서(카드 감시 폐지) 옛 기본값의 전제를 재검토하지 않음.
- 박제: mechanics 중계기 절에 "지휘자 watch-inbox는 WATCH_TYPES=worker_done,escalation,decision_gate 필수" 명문화.

## 2026-07-23 — 중계기 상주 턴 불성립 (kyle 발견: 입력이 바로 들어감)

- 사고: 중계기 luna에게 "판 종료까지 감시 반복"을 지시했으나, luna는 각 지시 처리 후 턴을 종료하고 입력 대기로 복귀 — 12분 순찰이 실제로는 지휘자 지시가 올 때만 실행됐다. kyle이 luna 터미널에 문자를 쳐보니 즉시 입력되는 것으로 발각 (턴이 열려 있으면 대기줄에 쌓여야 정상).
- 원인: LLM 에이전트의 턴 종료 본성 — 프롬프트 지시만으로 무한 상주 불가. 설계가 본성을 거슬렀다.
- 박제: 순찰 주기는 지휘자 측 알람 kicker(토큰 0 셸 루프)가 중계기를 두드리는 구조로 변경 — mechanics (2.1).

## 2026-07-24 — Kimi 작업 중 Codex OAuth 실패를 provider 장애로 오분류

- 사고: `kimi/k3[1m]` M2 작업자가 `auth.openai.com/oauth/token` 재연결 5/5로 턴이 끝났다. relay는 `ocx ensure`로 프록시를 확인한 뒤 Kimi 장애로 보고했고, 감독은 GLM 429와 합쳐 Terra high로 재발령했다.
- 확인: Kimi는 주간 26%·5시간 98%가 남고 OAuth 로그인도 정상이었다. ocx 프록시도 정상 실행 중이었다. 오류 URL은 Kimi provider가 아니라 Kimi를 실행한 Codex CLI의 ChatGPT OAuth 갱신 경로였다. 이후 `codex login status`는 로그인 정상, `ocx doctor`는 ChatGPT 인증 API 200으로 자연 회복을 확인했다.
- 원인: 실행 도구(harness)와 실제 모델 provider를 같은 장애 단위로 취급했다. `ocx ensure`는 프록시만 복구하며, 같은 Codex 하네스의 Terra로 바꿔도 OAuth 앞단은 공유하므로 근본 우회가 아니다.
- 박제: `auth.openai.com/oauth/token`은 `codex_oauth_unavailable`로 분류한다. 살아 있는 같은 터미널에서 30초→90초→180초 간격, 최대 3회 `codex login status`·`ocx doctor` 확인 후 `이어서 진행`으로 복구한다. 3회 실패 시 자동 재시도를 멈추고 재인증 또는 Codex가 아닌 하네스 전환을 decision gate로 올린다. Kimi 인증 장애는 Kimi provider 근거가 있을 때만 판정한다.

## 2026-07-24 — Rottie QA 경로가 Codex Desktop 대화에 오입력

- 사고: M2-R2 실제 화면 QA 중 작업자가 폴더 선택기를 자동화하며 `tell (first process whose frontmost is true) to keystroke ...`를 사용했다. 그 순간 Codex Desktop이 맨 앞 앱이 되어 `/Users/fw_m1/orca/workspaces/Rottie/daemon3-sync` 경로가 kyle의 현재 대화 입력창에 들어갔고, 사용자의 한글 입력과 섞여 전송됐다.
- 원인: 특정 Rottie QA process를 대상으로 시작한 뒤 편의를 위해 “현재 맨 앞 프로세스” fallback으로 넓혔다. 앱 활성화와 실제 키 입력 사이에 포커스가 바뀔 수 있는데 process name·PID·frontmost를 입력 직전에 원자적으로 재검증하지 않았다.
- 영향: 저장소·카드 변경은 없었지만 사용자의 다른 앱에 임의 경로·명령이 입력될 수 있는 안전 사고다. 세션 간 메시지 누출이나 inbox bridge 문제는 아니었다.
- 박제: `rottie-gui-qa`에 외부 키보드 입력 안전 계약을 추가했다. 임의 frontmost 대상은 금지하며, QA 시작 때 기록한 process name·PID와 입력 직전 frontmost를 모두 확인한다. 불일치·식별 불가는 입력 없이 실패 처리한다. Orca 카드에도 같은 계약을 명시한다.

## 2026-07-27 — 프로젝트 감독이 companion 종료를 기다려 판 정체

- 사고: `[판:openapi-fix]` 신임 프로젝트 감독(codex sol-low)이 임명 직후 `conductor-companion.sh`(WATCH_DEADLINE_MIN=720분 상주 감시)를 백그라운드 터미널로 띄운 것까지는 맞았으나, codex의 "Waiting for background terminal" 기능으로 **그 종료를 기다리며 턴을 블로킹**했다. companion은 판 수명 동안 끝나지 않으므로 최대 12시간 정체 궤도였다. kyle이 화면에서 발견, 외부 감독이 ESC 인터럽트로 대기만 끊고 교정 지시로 복구 (companion은 계속 생존 — 감시 공백 없음).
- 원인: "run_in_background로 띄운다"는 규칙이 Claude 하네스 용어라, codex 하네스 감독이 "백그라운드로 띄우되 완료를 기다리는" 자기 하네스 기능으로 번역했다. "종료를 기다리지 말라"가 명문화돼 있지 않았다. 2026-07-23 "상주 턴 불성립" 사고의 거울상 — 그때는 감시자가 안 깨어 있는 문제, 이번엔 지휘자가 감시자를 너무 기다린 문제.
- 토큰 영향: 대기 중 추론 정지라 소모는 거의 0 (실측: weekly 99% left). 피해는 토큰이 아니라 판 정체.
- 박제: SKILL.md 진입 루프 2와 mechanics.md companion 절에 "감시 스크립트 fire-and-forget — 종료 대기 금지" 명문화. 감독 임명장 표준 문구에도 같은 줄 포함.

## 2026-07-27 — 검수자가 검수 대상 워크트리 안에 evidence 파일 생성 (우연 발견)

- 사고: `[판:openapi-fix]` #77 HEAVY 1라운드 검수자(sol-medium)가 읽기 전용 계약을 어기고 워크트리 안 `.omo/evidence/manual-qa-77/*`를 생성, supertest 스크립트도 새로 작성하다 TypeError. 전용 감지 센서는 없었고, 중계기가 다른 사유(검수자가 찾은 Date→{} 제품 결함)로 escalation한 덕에 깨어난 감독이 화면에서 위반을 덤으로 발견해 교정 status로 복구(파일은 보존, 이후 생성 금지, TypeError는 제품 결함과 분리).
- 원인: 검수 카드의 "수정 금지"가 "근거 파일을 어디 남길지"를 정하지 않아, 검수자가 워크트리 안 생성을 허용으로 해석.
- 박제: tiki-taka.md에 "검수 evidence 장소 지정 — 워크트리 밖만" 규칙 추가 (kyle 승인 2026-07-27). 금지가 아니라 장소 지정인 이유: 근거 자체는 검수 품질에 필요, 문제는 diff 오염뿐.

## 2026-07-27 — dispatch-safe 스타트 판정 거짓 NOT_STARTED 2건

- 사고: (1) super-audit 조사자(kimi)와 (2) openapi-fix #79 작업자(Claude)가 실제로 정상 작업 중인데 dispatch-safe.sh가 NOT_STARTED(exit 4)를 반복 보고. 자동 재발령 금지 규칙 덕에 이중 발령 사고는 없었으나 감독이 매번 수동 판정에 시간을 씀.
- 원인: 판정식이 ACTIVE+Context% 동시 요구인데 Context 신호가 구조적으로 안 잡히는 화면 2종 — Claude Code는 "Context N%" 상태바 자체가 없음(codex 전용 가정), codex도 좁은 pane에서 "Context…"로 잘려 숫자 소실.
- 박제: dispatch-safe.sh에 active-progress 폴백 추가 — 서로 다른 poll에서 내용이 다른 ACTIVE 2회 = STARTED (같은 내용 반복은 잔상 가드 유지). 회귀 테스트 5c/5d 추가, 9/9 통과. NOT_STARTED 후속 판정은 중계기 luna 위임 가능(kyle 제안). mechanics.md 스타트 판정 계약 갱신.

## 2026-07-27 — #79 랠리 파이프라인 무음 공백 (kyle 육안 발견)

- 사고: #79 4라운드 구현 카드 completed 후 후속 재검수 카드가 발령되지 않은 채 정지. 감독이 #80 결함 escalation·worker_done 유실 복구를 처리하는 동안 다른 랠리의 다음 발령을 흘림. 오류 0·활성 터미널 0이라 watch-card(카드는 전부 종결)·정체 순찰(활성 없음)·오류 감시 어디에도 안 걸리는 완전 무음 — kyle이 브리핑 대조로 발견, 외부 감독 지시로 복구.
- 원인: "다음 카드가 있어야 할 자리에 없음"을 보는 감시가 없었다. 기존 감시는 전부 "있는 것의 이상"만 본다.
- 박제: 중계기 순찰에 랠리 파이프라인 공백 감지 추가 — 구현 completed + 후속 검수 15분 부재 = `pipeline_gap` escalation 1회, 의도된 대기(관문·배치·상한)는 억제 (mechanics 중계기 3.1).

## 2026-07-28 — "worker_done 런타임 타임아웃"의 진상: macOS timeout 부재 (오보고 연쇄)

- 사고: 작업자 3회가 `timeout 45 orca orchestration send --type worker_done ...`으로 발송 → macOS에 GNU timeout이 없어 `zsh: command not found: timeout` 즉사. 작업자·중계기가 이를 "Orca runtime timeout"으로 보고했고, 슈퍼감독도 검증 없이 "앱 응답 지연"으로 kyle에게 설명 — kyle의 "orca 앱 문제야?" 질문에 세션 기록을 실측해서야 진상 확인 (timed out/ETIMEDOUT 실제 오류 0건).
- 교훈 2개: (1) 리눅스 습관 명령(timeout)은 macOS에서 조용히 어긋난다 (2) 오류의 "이름"은 보고자가 붙인 해석일 수 있다 — 원문 확인 전에 이름을 믿지 말 것.
- 박제: mechanics worker_done 절 정정 (timeout 래퍼 금지 + 오류 원문 보고 의무).

## 2026-07-28 — 복구 국면에서 미등록 엔진(opencode) 임의 편성

- 사고: 운영 배포 최종 독립 검수 편성 중 기존 검수 터미널 2개 발령이 DISPATCH_FAILED → 감독이 생존 확인·라우터 재실행 없이 roster 미등록 opencode CLI를 임의 생성해 검수자로 사용. 내부 모델은 GLM 5.2 max(이미 등록된 provider)라 실익 0, 절차만 위반. kyle이 GUI에서 발견, 감독 직문으로 전말 확인(등록 엔진 불가 근거 없음·규칙 인지 상태에서의 위반 자인).
- 원인: 복구가 급한 국면에서 절차 생략 — 발령 실패의 실제 원인(죽은 터미널 재사용)을 진단하지 않고 도구 우회로 해결.
- 판정: 검수 결과(PASS)는 증거 기반이라 유지, 편성 과정 비준수 기록. opencode 터미널 종료 지시.
- 박제: mechanics "복구 국면에도 편성 규칙은 그대로다" — DISPATCH_FAILED 복구 시에도 라우터+roster 필수, 미등록 CLI 생성 금지.

## 2026-07-28 — opencode 사고 원인 정정: pending 카드 + 스크립트가 오류를 삼킴

- 정정: DISPATCH_FAILED 2회의 진짜 원인은 터미널 사망도 훅 업데이트도 아니라 **카드가 pending 상태**였던 것 (kyle의 훅 가설 검증 과정에서 확정 — opencode 새 터미널도 같은 카드에서 실패했고 ready 변경 후 성공). 즉 opencode 우회는 불필요했다.
- 공범: dispatch-safe.sh가 dispatch 오류 원문을 /dev/null로 버려 "task is pending"류 자기설명 오류가 숨겨짐 → 감독이 터미널 문제로 오진.
- 박제: dispatch-safe.sh가 DISPATCH_FAILED 시 오류 원문 500자 + "pending이면 ready 후 재발령" 힌트를 출력하도록 수정 (회귀 9/9). 교훈: "오류 원문 보고 의무"는 에이전트만이 아니라 **스크립트에도** 적용된다 — 도구가 삼킨 오류는 에이전트의 오진이 된다.

## 2026-07-31 — 중계기가 정체를 찾았지만 LEGACY READ-ONLY로 감독 보고 실패

- 사고: 중계기가 같은 활성 터미널의 연속 무진행 2회를 확인했지만 `escalation` 발송이 `legacy_read_only`로 거부됐고 `effectsApplied=false`였다. 화면에는 진단이 남았지만 현재 프로젝트 감독이 깨어나지 않아 판 전체가 멈췄고 kyle이 직접 발견했다.
- 원인: Orca 계약 갱신 뒤 구형 중계기 프로세스는 파일과 터미널을 읽을 수 있어도 lifecycle 변경 권한이 없는 `[LEGACY READ-ONLY]` 상태가 될 수 있다. 기존 구조는 우편함의 성공한 신호만 companion이 깨웠고, 중계기 화면에 남은 **발송 실패 자체**를 현재 감독으로 전달하는 길이 없었다.
- 박제: 중계기는 거부 즉시 구조화된 `ORCA_LEGACY_READ_ONLY_REPORT` 한 줄을 출력하고 재시도를 멈춘다. companion이 이 표식과 기존 원문 오류를 읽기 전용으로 감지해 현재 감독을 한 번만 깨운다. 자동 Run 인수는 금지하며, 현재 감독이 원래 감독의 권한 상실을 확인한 경우에만 공식 `run-use --takeover-legacy` 절차를 사용한다.

## 2026-07-31 — 첫 LEGACY READ-ONLY 보완이 다음 작업자 완료를 놓침

- 사고: 첫 보완 뒤 Todo 6 작업자의 `worker_done`이 같은 오류로 거부됐지만 감독이 다시 깨어나지 않았다. 중계기는 구조화 표식을 자기 화면이 아니라 작업자 화면에 `terminal send`했고, companion은 중계기 화면만 읽었다. 원문 폴백 중복 키도 `raw:legacy_read_only` 하나라 Todo 5 사건 뒤 Todo 6 사건을 같은 것으로 버렸다.
- 원인: 감지 위치와 사건 식별자가 실제 실패 주체인 작업자·`taskId+dispatchId`를 포함하지 않았다.
- 박제: companion이 현재 `dispatched` 작업자 화면도 읽기 전용으로 확인하고 `taskId+dispatchId`별로 깨운다. 중계기 프롬프트에는 작업자 터미널 전송 금지와 자기 응답 출력 의무를 명시하고, 서로 다른 두 dispatch가 각각 한 번 깨우는 회귀 테스트를 둔다.

## 2026-07-31 — companion nohup 재기동 직후 종료

- 증상: 기존 companion을 안전하게 종료한 뒤 `nohup`으로 새 PID를 확인했지만, 부모 셸이 끝난 직후 새 PID도 사라졌다.
- 원인: 스크립트가 `HUP`을 정상 종료 신호로 덮어써서, `nohup`의 HUP 무시 동작을 다시 취소하고 있었다.
- 박제: `HUP`은 명시적으로 무시하고, 운영자 종료용 `INT`와 `TERM`만 정상 종료한다. 회귀 테스트는 HUP 뒤 생존과 TERM 뒤 정상 종료를 함께 확인한다.

## 2026-07-31 — launchctl companion은 살아 있지만 Orca 명령을 실행하지 못함

- 증상: `launchctl submit`으로 부모 PID 1의 companion이 수분간 살아 있었지만 새 작업자의 `legacy_read_only` 완료 실패를 감지하지 못했고 stdout에는 `KICKER_FAIL`만 남았다.
- 원인: launchd의 축소된 PATH에는 `/usr/local/bin`이 없어 스크립트의 기본 `orca` 명령을 찾지 못했다. 프로세스 생존 확인만 하고 실제 `task-list/read/send` 끝단을 확인하지 않아 거짓 정상 판정이 됐다.
- 박제: launchctl 실행에는 `ORCA_BIN` 절대경로를 전달한다. 스크립트도 대표 설치 경로를 자동 탐색하고 없으면 즉시 실패한다. 기동 합격은 PID 생존이 아니라 실제 Orca 조회와 wake 성공까지다.

## 2026-07-31 — Fable 완료 뒤 터미널 화면이 BB로 붕괴해 legacy 보고를 놓침

- 증상: companion과 실제 Orca 조회·wake는 정상인데 Fable 재검토가 끝난 뒤 카드가 계속 dispatched에 남았다. `terminal read`는 실제 완료 전문 대신 `BB` 한 줄만 반환했다.
- 원인: companion의 작업자 직접 감지가 렌더된 터미널 화면만 읽었다. 동일 dispatch의 transcript에는 `worker_done` 거부 원문과 exit 1이 온전히 남아 있었지만 확인하지 않았다.
- 박제: 화면 우선 감지는 유지하고 원문이 없을 때만 dispatch별 최근 transcript를 읽는다. 화면 붕괴 fixture와 transcript 폴백 회귀 테스트를 둔다.

## 2026-07-31 — 정정: 기존 companion 자연사가 아니라 교체 과정의 명시적 종료

- 정정 대상: 같은 날 `companion nohup 재기동 직후 종료` 기록을 기존 상주 companion까지 자연사한 것처럼 확대 해석한 판단.
- 확인된 사실: 정상 상주 중이던 PID `66505`와 `78977`은 각각 업그레이드 지시에 따라 `kill -TERM`으로 명시적으로 종료됐다. 셸 종료 뒤 사라진 PID는 그 다음에 만든 짧은 `nohup` 교체 시도 `75417`, `84493`이었다.
- 판정: 기존 감독 소유 상주 방식이 저절로 죽었다는 증거는 없다. HUP 무시 변경은 방어적 보완이지만 기존 companion 중단의 확정 원인은 아니다. 이후 정체는 별개로 (1) launchctl PATH 누락과 (2) Fable 렌더 화면 `BB` 붕괴 때문에 감지가 막힌 사건이다.
- 박제: 상주 감시가 사라졌을 때는 먼저 종료 명령 기록과 PID 계보를 확인하고, 자연사로 분류하기 전에 명시적 `kill`·도구 셸 임시 자식·실제 감독 소유 프로세스를 구분한다.
