# R-OMO-1 정밀 조사: omo 강제 장치의 코드·세션 근거 (정정판 v2)

## Why

kyle이 omo의 실제 강제 장치를 우리 작업 흐름(Orca + conductor + waker/companion)에 근거 있게 이식할 수 있도록, 문구가 아닌 코드와 세션 증거를 연결한다. 특히 "의도 관문과 턴 규율을 코드로 강제하는 지점"을 정확히 잡아, 우리 `[턴 종료]` 선언의 부재·형식 오류를 waker가 기계 판정하는 구체 설계안의 출발점으로 삼는다.

## 정정 이력 (v1 -> v2)

v1(원조사 task_90ee354ffbce)은 CODE_FAIL 판정을 받았다(검수 result-R-R-OMO-1.md). 근본 원인: 조사 범위가 omo bundle + 낡은 로컬 src에 한정됐고, 설치된 senpi dist의 builtin 확장·중첩 의존성을 보지 않아 4개 실물을 "부재"로 오보했다. v2는 조사 범위를 senpi dist 전체로 넓혀 4개 부재 주장을 전면 폐기하고, 삼표면 원칙과 관점7을 재작성했다.

폐기된 v1 주장(모두 거짓): (1) Intent Gate 부재 (2) loop-guard:notice 부재 (3) senpi.hooks.stop-state 부재 (4) codemode 완전부재.

유지되는 검증된 사실: beta.5/senpi 2026.8.11-2, ultrawork 정규식·input 훅·주입 로직, omo-senpi:wake 200ms 배치와 우선순위 맵, 21개 스킬, 작업 상태 7개·거주 상태 5개, terminal transition 원칙.

## 조사 범위와 방법 (v2, 넓힘)

- 작업 worktree: `/Users/fw_m1/orca/workspaces/kyle-agent-skills/omo-deep-analysis-1-r1` (branch `ChickenBreast-ky/omo-deep-analysis-1-r1`).
- 읽기 대상 (원본 수정 금지):
  1. omo-ai beta.5: `/Users/fw_m1/.nvm/versions/node/v24.18.0/lib/node_modules/omo-ai/` (plugin/extensions/omo.js, plugin/skills/*)
  2. **설치된 senpi dist 전체**: `omo-ai/node_modules/@code-yeongyu/senpi/dist/` (v1이 놓친 핵심 영역)
  3. senpi builtin 등록 목록: `senpi/dist/core/extensions/builtin/index.js`
  4. senpi 중첩 의존성: `senpi/node_modules/@code-yeongyu/senpi-codemode/`
  5. 로컬 oh-my-openagent 소스: 보조 근거로만(HEAD 1ec03deb5, origin/dev 대비 크게 뒤처진 체크아웃 — git rev-list --count HEAD..origin/dev = 597(2026-08-11 실측; 변동 수치이므로 '현재 크게 뒤처진 보조 소스'로 취급))
  6. 세션 JSONL: 비밀·원문 복제 없이 존재·횟수·provider/model/timestamp만 사용
- 도구: rg(ripgrep 15.2.0), python3(json 검증), jq.

## 버전

| 항목 | 값 | 근거 |
|---|---|---|
| omo-ai | 5.0.0-0.beta.5 | `omo-ai/package.json` |
| senpi | 2026.8.11-2 | `omo-ai/node_modules/@code-yeongyu/senpi/package.json` |
| 임명장(agent-runners.json) beta.2 | 2026-08-10 09:47:04 | 라이브 main 원본 |
| 임명장 beta.5 보강 | 2026-08-11 | 본 작업 append |

---

## 관점 1. Intent Gate 실물 / 발동 / 선언문 / 임명장 10절과 차이

### 실물과 위치 (v1 정정: 부재 주장 폐기)

**Intent Gate는 실재한다.** senpi core builtin 동적 프롬프트의 일부다.

- `senpi/dist/core/dynamic-prompt/intent-gate.js:9` `buildIntentGate(config)` 함수.
- 이 함수는 `## Intent Gate (EVERY message)` 섹션(`intent-gate.js:10`)을 만들고, 매 턴 첫 줄에 라우팅 줄을 **required**로 요구한다(`:14`): `> I read this as [intent] - [plan].`
- 라우팅 표(Research/Implementation/Investigation/Evaluation/Fix/Open-ended) `:20-27`, Turn-Local Intent Reset `:36-37`, Context-Completion Gate `:39-40`.
- 조립: `dynamic-prompt/build.js:4`(import), `:41`(`buildIntentGate({tools})` 호출). `dynamic-prompt/index.js:4` re-export.
- 사용: `agent-session.js`가 `basePrompt = loaderSystemPrompt ?? buildDynamicSystemPrompt(...)`로 사용(즉 loaderSystemPrompt가 없으면 intent-gate가 포함된 동적 프롬프트가 base).
- 활성 증거: 라이브 세션 JSONL에서 "I read this as" 라우팅 줄이 다수 관측(예: 한 세션 28회; 라이브 임명장 96행 evidence에도 "omo-senpi:wake 10회, loop-guard:notice, senpi.hooks.stop-state도 함께 찍혔다"로 beta.2 시점부터 기록됨).

### 발동 조건

Intent Gate는 "발동 조건"이 아니라 **기본 동적 프롬프트와 주요 preset에 포함되는 상주 섹션**이다(F-R-OMO-3 정정: "항상" 단정을 우회 조건 반영으로 한정). 정확한 조건: `agent-session.js:1871`의 `basePrompt = loaderSystemPrompt ?? buildDynamicSystemPrompt(...)` — `loaderSystemPrompt`가 없을 때(기본 동적 프롬프트 경로) intent-gate가 포함되고, 주요 코어 preset(claude-opus-5 등)도 자체 `## Intent Gate` 절을 갖는다. loader system prompt가 주입되면 동적 intent-gate 경로를 우회할 수 있다. 모델이 매 턴 라우팅 줄을 출력하도록 요구하되, 요구(프롬프트)일 뿐 기계 검증은 아니다(관점 7 참조).

### 선언문 형식

- 라우팅 줄: `> I read this as [intent] - [plan].`(`intent-gate.js:14`).
- 모든 주요 코어 preset(claude-opus-5, claude-fable-5, gpt-5.6, grok-4.5, kimi-k3)이 이 라우팅 줄에 **바인딩 중지조건**을 추가한다(관점 7 상세). 예: `> I read this as [intent] - [plan]. I'll stop when [the exact, observable condition that ends this turn].`

### 임명장 10절(우리 conductor)과의 차이

| 차원 | omo Intent Gate | 우리 임명장(10절) |
|---|---|---|
| 성격 | base 프롬프트에 상주(코드 생성) | 카드/프롬프트 텍스트로 모델에게 지시 |
| 라우팅 줄 | 매 턴 첫 줄 required(프롬프트) | 임명장 본문에 안내 |
| 중지조건 | 코어 preset이 바인딩 선언으로 요구 | `[턴 종료]` 토큰을 문구로 요구 |
| 기계 검증 | 없음(요구만) | 없음(요구만) |

결론(관점 1): Intent Gate는 omo가 모델에게 매 턴 의도·계획·중지조건을 선언하도록 **프롬프트층에서 요구**하는 장치다. ultrawork의 `input` 훅(정규식 강제 주입)과는 별개의, 더 근본적인 턴-규율 장치다.

---

## 관점 2. 강제 주입 customType — 언제 발동하고 무엇을 막는가

v1이 "부재"라고 한 2개(loop-guard:notice, senpi.hooks.stop-state)가 모두 senpi core builtin에 실재한다. 총 4개(+omo-ultrawork:directive, omo-senpi:wake)를 file:line로 정리한다.

### (A) omo-ultrawork:directive — omo 확장, 실재

- 위치: omo bundle(`plugin/extensions/omo.js`); 소스 `omo-senpi/src/components/ultrawork/index.ts`.
- 발동: `input` 이벤트 핸들러, 정규식 `/(?:ultrawork|ulw(?!-))/i`(`ultrawork/index.ts:7`, negative lookahead로 `ulw-plan` 등 스킬 이름 오타 방지), idle 입력 시 `armUltrawork`(`:109-118`).
- 막는 것: ultrawork 트리거 입력이 규칙 없이 처리되는 것. 약 31KB directive를 숨은 custom 메시지(`display:false`)로 문맥에 강제 주입. 큐 입력엔 transform으로 append(`:110-112`).
- 우리 companion/waker와 비교: companion은 모델 출력을 감시·재촉하지만 입력에 규칙을 주입하지 않는다. omo는 입력 단에서 선제 주입.

### (B) omo-senpi:wake — omo 확장, batched-wake (실재)

- 위치: omo bundle `omo.js`(minified 식별자 `$y`의 `#g` 메서드; `IdleInjectionCoordinator`는 소스명이며 bundle 문자열이 아님 — v1 MINOR 정정 #10). 상수 `Je = "omo-senpi:wake"`.
- 발동: IdleInjectionCoordinator가 200ms 배치 창(`scheduleFlush: (_)=>void setTimeout(_,200)`, compose `$1()`) 안에 몰린 알림을 flush.
- 소스별 우선순위 맵 `w1`: `task-completion(0) > team-message(1) > team-liveness(2) > boulder-continuation(3) > ulw-continuation(4)`.
- 막는 것: N개 알림이 N번 steer(턴 깨움)을 만들어 부모 턴을 파편화. 한 번의 `omo-senpi:wake` content로 합쳐 1회 주입.
- 우리 waker와 비교: 가장 직접적으로 이식 가치가 있는 장치. 다수 worker의 완료·heartbeat·escalation이 개별 턴을 깨우면 coordinator가 파편화된다.

### (C) loop-guard:notice — senpi core builtin (v1 정정: 부재 주장 폐기)

- 위치: `senpi/dist/core/extensions/builtin/loop-guard/notice.js:1` `LOOP_GUARD_NOTICE_CUSTOM_TYPE = "loop-guard:notice"`.
- 감지 3종(`notice.js:2-40`, `buildLoopGuardReminder`):
  - `identical`(`:4-14`): 같은 도구 같은 인자 연속 호출. "이미 받은 결과 재사용, 모니터 도구로 전환, 또는 멈추고 블로커 보고" 권고.
  - `similar`(`:16-26`): bigram 유사도로 근사 중복 감지. "진짜 배치 작업인지 게으른 루프인지 주의 검사".
  - `cycle`(`:28-38`): 도구 호출 순환 패턴 감지(period·count).
- 발동: `loop-guard/index.js:18` `tool_execution_start` 이벤트에서 tracker 기록 + `detectLoop`. 감지 시 `pi.sendMessage({customType: LOOP_GUARD_NOTICE_CUSTOM_TYPE, ..., display: true}, {triggerTurn:false, deliverAs:"steer"})`(`:23-28`). `registerMessageRenderer`로 렌더러 등록(`:12`).
- 활성 등록: `builtin/index.js:79` `{ id: "loop-guard", factory: loopGuardExtension }`.
- **v1 오보 정정**: v1은 이것을 "senpi/omo-ai에 없음"이라 했고, 대신 omo-opencode의 `KIMI_TOOL_LOOP_GUARD`(정적 프롬프트 텍스트 블록)를 실물로 제시했다. 그것은 별개의 더 약한 장치다. 진짜 loop-guard:notice는 이 런타임 builtin이며, 라이브 임명장 96행 evidence에도 명시되어 있었다.
- 우리와 비교: 우리가 겪는 "worker가 같은 검사를 반복" 문제에 직접 해당. 런타임 감지라 정적 프롬프트보다 강하다. 이식 가치 높음.

### (D) senpi.hooks.stop-state — senpi core builtin (v1 정정: 부재 주장 폐기)

- 위치: `senpi/dist/core/extensions/builtin/hooks/stop-adapter.js:3` `STOP_STATE_CUSTOM_TYPE = "senpi.hooks.stop-state"` (정확히 그 이름).
- 추가 customType: `senpi.hooks.stop-diagnostics`(`:4`), `senpi.hooks.stop-output`(`:5`).
- Stop 훅 어댑터 구성:
  - `buildStopHookInput(event, ctx)`(`:7-18`): Stop 이벤트 입력 조립. `stopReason`, `transcript_path` 전달.
  - `createStopTurnTracker()`(`:19-35`): turnKey 추적(`turnIndex:leafId`).
  - `applyStopHookResult(pi, ctx, result, turnKey)`(`:36-78`): 결과 적용. **재진입 제한 `STOP_REENTRY_LIMIT=8`**(`:6`, `:39`). block 시 `pi.sendUserMessage(followUp, {deliverAs:"followUp"})`(`:76`).
  - `latestStopState`(`:86-97`): 세션 entries에서 STOP_STATE_CUSTOM_TYPE 최신 조회.
- 활성 등록: `builtin/index.js:46` `{ id: "hooks", factory: hooksExtension }`. `hooks/index.js:7`이 stop-adapter를 import해 사용.
- **v1 오보 정정**: v1은 이것을 "코드에 없음, agent_end/senpi.n의 느슨한 표현 추정"이라 했다. 실제로는 정확히 `senpi.hooks.stop-state`라는 상수값이 존재한다. v1이 stopState/hooks.stop-state를 senpi dist 전체가 아닌 좁은 범위에서 grep한 것이 원인.
- 우리와 비교: 이것이 omo의 **lifecycle층 턴-종료 규율**이다(관점 7의 핵심).

### (E) 전체 customType 실측 지도 (beta.5, 3출처 통합)

v1은 omo bundle만 grep했다. v2는 (1)omo 확장 bundle (2)senpi core builtin 확장 (3)senpi 중첩 의존성 세 출처를 통합.

| 출처 | customType | 용도 |
|---|---|---|
| omo 확장 | omo-ultrawork:directive | 강제 directive 주입(관점 2-A) |
| omo 확장 | omo-senpi:wake | batched-wake(200ms, 관점 2-B) |
| omo 확장 | senpi-task.completion | 작업 완료 알림 |
| omo 확장 | senpi-task:team-message | 팀 메시지 배달 |
| omo 확장 | senpi-task.team-member-liveness | 멤버 생존 알림 |
| omo 확장 | omo-senpi:ulw-continuation | ulw-loop 자동 이어받기 |
| omo 확장 | omo-senpi:start-work-continuation | boulder 이어받기 |
| omo 확장 | senpi-task.usage | 사용량 안내(세션당 1회) |
| **senpi core builtin** | **loop-guard:notice** | **런타임 루프 감지(관점 2-C)** |
| **senpi core builtin** | **senpi.hooks.stop-state** | **Stop 훅 상태(관점 2-D)** |
| **senpi core builtin** | senpi.hooks.stop-diagnostics | Stop 진단 |
| **senpi core builtin** | senpi.hooks.stop-output | Stop 출력 |

---

## 관점 3. 21종 스킬 Triggers 문구와 실제 발동 구조

(v1 내용 유지 — 검수 PASS. 요약만.)

omo 스킬 21개는 description의 자연어 트리거로 **모델이 라우팅**한다(우리 "카드에 발동 낱말" 방식과 상이). 핵심 패턴:
1. "MUST USE ..."/"Triggers: ..." 인용문으로 모델 라우팅 유도.
2. ulw-plan/ulw-research는 "ACTIVATES ONLY on explicit user request" 자기발동 금지 가드.
3. **코드 강제는 ultrawork뿐** — `input` 훅 정규식 발동(관점 2-A). 나머지 20개는 전부 description(문구) 기반.

전수 분류는 v1 표 유지. 이식 시사점: "ACTIVATES ONLY..." 문구 패턴은 우리 카드에 "dispatch된 범위에서만, 자의적 확장 금지"를 박는 데 참고.

---

## 관점 4. senpi-task 상태 전이와 우리 판·카드/Dispatch 대응표

### 상태 (코드 근거 + v1 IMPORTANT 정정 #8)

- 작업 상태 7: `pending`/`running`/`completed`/`error`/`cancelled`/`interrupted`/`lost`.
- 거주 상태 5: `resident`/`evicted`/`disposed`/`persisted_only`/`rpc_detached`.
- **완료 알림 종료 상태 정정(v1 오류 수정)**: `completion-bridge.ts:10-15` `TERMINAL_STATUSES`는 **5개**(completed/error/cancelled/interrupted/lost)다. v1이 "3개(completed/error/lost)"라고 한 것은 오류. `isTerminalApplied`(`:55-59`)가 `applied && statusChanging && TERMINAL_STATUSES.has(status)`일 때 `notifyTerminal` 발화(`:42-43`). 주석(`:26-27`): "completion notification is driven by the STORE's terminal transition, never raw agent_end".
- **근거 신뢰도 명시(MINOR #11)**: 상태기계 '구조' 근거(completion-bridge.ts 등)는 로컬 src로, origin/dev 대비 크게 뒤처진 체크아웃(HEAD 1ec03deb5, rev-list --count HEAD..origin/dev = 597, 2026-08-11 실측)에 의존한다. 상태값 자체는 beta.5 bundle에 inline 존재하므로 값은 확정이나, 상세 전이 로직의 줄 근거는 낡은 소스 기준.

### 우리 판·카드/Dispatch 대응표 (추정)

| senpi-task | 우리 conductor 대응 |
|---|---|
| TaskRecord | 카드(task card) |
| pending | dispatch 대기/큐 |
| running | worker 실행 중(heartbeat) |
| completed | worker_done(outcome=succeeded) |
| error | worker_done(failed)/escalation |
| cancelled/interrupted | coordinator 중단 |
| lost | 응답 없는 worker |
| team(member) | 판(worktree) |
| lead session | coordinator 터미널 |
| agent_end/Stop 훅 | [턴 종료] 선언(문구) — omo는 코드 훅 |

핵심 차이: senpi-task는 STORE(파일 원장)의 terminal transition으로 구동(코드). 우리는 worker_done 메시지로 구동. omo가 더 강고(메시지 유실에도 파일 원장이 회복 근원).

---

## 관점 5. codemode eval 커널 — 이득·손실·안전 경계 (v1 정정: 완전부재 주장 폐기)

### 실물 (v1 오보 정정)

**codemode는 실재한다.** senpi의 중첩 의존성에 있다.

- 패키지: `omo-ai/node_modules/@code-yeongyu/senpi/node_modules/@code-yeongyu/senpi-codemode@2026.8.11-2`.
- 설명: "Source-only senpi extension package for codemode evaluation tools".
- 커널 4종: `src/kernels/{py, js, jl(julia), rb(ruby)}` + `shared`. 각 언어 eval 커널.
- 구조: `src/{bridge, bridges, completion, config, extension, interpreters, kernels, output, prompt, timeouts, tool}` + `host-sdk.ts` + `index.ts`.
- 활성 등록: `senpi/dist/core/resource-loader.js:44` `{ builtinId: "codemode", packageName: "@code-yeongyu/senpi-codemode" }`, `:49-50` resolvePackage. `goal/prompt.js:59,63`이 senpi-codemode를 wake 소스로 참조.
- **v1 오보 정정**: v1이 "현재 설치에서 완전 부재(패키지·dist·문서 어디에도 없음)"라 한 것은 거짓. v1이 최상위 `@code-yeongyu/senpi`(존재 안 함)만 찾고 중첩 의존성을 안 봤기 때문이다.

### 이득·손실·안전 경계 (이제 코드로 검증 가능)

- 이득: 코드 검증을 "테스트 파일 작성+실행" 대신 인터랙티브 eval로 즉시 회신 -> 빠른 RED/GREEN. py/js/jl/rb 다언어.
- 손실/위험: eval 커널이 **전체 시스템 권한으로 임의 코드 실행(py/js/jl/rb)** -> 신뢰하지 않는 입력이 섞이면 RCE. RCE 면 실재(추정 아님, 커널 존재로 확정).
- 우리 안전 경계 충돌: AGENTS.md "기계 전체에 영향을 주는 부하를 만들지 않는다", "연결 기기에서 승인 없이 설치·설정 변경 금지". eval 커널 이식은 임의 코드 실행면이 생기므로 **비이식 권장 유지**(방향은 v1과 같으나 근거가 "부재/실측불가"에서 "실재+RCE면"으로 정정).

### 남은 불확실성 (분리)

- 패키지·builtin 등록은 확정이나, **사용자 config 기반 on/off** 여부는 별도 확인 필요. 부재 주장이 거짓인 것에는 영향 없음.

---

## 관점 6. 이식 후보와 비이식 목록 (삼표면 명시 — v1 CRITICAL #5 정정)

### 삼표면 원칙

각 이식 후보는 세 표면에 각각 어디에 놓이는지 명시한다. (1) **원본 파일**(omo/senpi 코드) (2) **사람 화면**(kyle이 보는 TUI/터미널/문서) (3) **에이전트 창구**(모델이 받는 프롬프트/카드/메시지). 현재 우리 환경에 없는 표면은 "구현 필요"로 표시.

### 이식 후보 (삼표면 포함)

| # | 무엇 | 원본 파일(omo) | 사람 화면(우리) | 에이전트 창구(우리) | 비용 |
|---|---|---|---|---|---|
| 1 | **batched-wake(omo-senpi:wake)** | `omo-ai/plugin/extensions/omo.js`(설치 절대경로 `/Users/fw_m1/.nvm/versions/node/v24.18.0/lib/node_modules/omo-ai/plugin/extensions/omo.js`, minified `$y.#g`, 소스명 IdleInjectionCoordinator) | `skills/orca-conductor/scripts/supervisor-waker.sh` stdout(구현 예정: 200ms 배치 창에서 합쳐진 알림을 "1회 합쳐 깨움 N건" 한 줄로 출력) | coordinator/supervisor terminal handle로 합친 payload 1회 **제출** — **구현 예정** `skills/orca-conductor/scripts/send-steer.sh`가 packaged Orca CLI `orca terminal send --terminal <supervisor_handle> --text <batched_payload> --enter --json` 호출(F-R-OMO-5: `--enter` 필수 — 없으면 payload를 입력만 하고 제출 안 함, 런타임 `\r` suffix). 실행 중 메시지 전송; 새 카드 발령 아님 | 중 |
| 2 | **[턴 종료] 기계 판정(2계층)** | 원본 규칙: `senpi/dist/core/extensions/builtin/hooks/stop-adapter.js:3`(senpi.hooks.stop-state), `senpi/dist/core/dynamic-prompt/intent-gate.js:14`(라우팅+중지조건 선언 요구) | `skills/orca-conductor/scripts/supervisor-waker.sh` 판정 결과(구현 예정: worker_done/idle + 토큰 정규식 교차 판정을 stdout 한 줄로) | `skills/orca-conductor/references/appointment-template.md`(임명장)에 "매 턴 의도-계획-중지조건 선언" 문구 삽입(이미 쓰기 허용 카드에서 가능) | 중 |
| 3 | **loop-guard:notice 런타임 감지** | `senpi/dist/core/extensions/builtin/loop-guard/notice.js:1-40` + `loop-guard/index.js:18-28`(tracker·detectLoop) | `skills/orca-conductor/scripts/supervisor-waker.sh` 루프 경고(구현 예정: 동일 도구/인자 반복을 정규식으로 감지해 경고 줄 출력) | active worker terminal handle로 loop-reminder payload 전달. **정상 follow-up**(루프 감지 알림) — **구현 예정** `send-steer.sh`가 `orca terminal send --terminal <worker_handle> --text <loop_reminder> --enter --json` 호출(`--enter` 필수). **즉시 중단이 필요할 때만 별도 두 단계**(F-R-OMO-5): (a)`orca terminal send --terminal <worker_handle> --interrupt --json`(Ctrl-C `\x03`, 전달 방식 아님)으로 중단, (b)TUI가 입력 가능해진 뒤 별도 `orca terminal send --terminal <worker_handle> --text <loop_reminder> --enter --json`으로 후속 제출. 한 호출에 `--text`+`--interrupt` 섞지 않는다 | 중 |
| 4 | **KIMI_TOOL_LOOP_GUARD 정적 블록** | `~/Dev/oh-my-openagent/packages/omo-opencode/src/agents/kimi-tool-loop-guard.ts`(전문) | `skills/orca-conductor/references/appointment-template.md`에 블록 텍스트 표시(카드에 포함 시 화면에 보임) | 동일 파일(임명장)의 카드 프롬프트에 `<tool_loop_guard>` 블록 포함 — worker가 받는 프롬프트 입력 위치 | 저 |
| 5 | **terminal-transition 원장 구동** | 원본 원칙: `omo-senpi/src/components/task/completion-bridge.ts:10-15`(TERMINAL_STATUSES 5개, 로컬 보조 src) | `http://127.0.0.1:8787/status.txt`(board-dashboard.py 서빙 상태 탭) — **구현 예정**: worker_done terminal transition을 파일 원장 `.orca/runtime/<board>/terminal-transitions.jsonl`(저장소 상대경로, board=현재 판 이름)에 append. board-dashboard.py가 이 파일을 읽어 `/status.txt`에 노출 | `http://127.0.0.1:8787/status.txt`(동일 endpoint — 에이전트는 curl로 상태 원장을 읽어 판정, 메시지 유실 시에도 파일 원장이 회복 근원) | 고 |
| 6 | **intent-gate 라우팅 줄 패턴** | `senpi/dist/core/dynamic-prompt/intent-gate.js:14`(`> I read this as [intent] - [plan].`) | `skills/orca-conductor/references/appointment-template.md`에 패턴 표시 | 동일 파일(임명장)의 카드/프롬프트에 "의도-계획-중지조건" 선언 요구 문구 — worker 프롬프트 입력 위치 | 저 |
| 7 | **"ACTIVATES ONLY..." 자기발동 금지 문구** | `omo-ai/plugin/skills/ulw-plan/SKILL.md`·`ulw-research/SKILL.md`의 description(`"ACTIVATES ONLY on explicit user request"`) | `skills/orca-conductor/references/appointment-template.md`에 문구 표시 | 동일 파일(임명장)의 카드 description에 "dispatch된 범위에서만, 자의적 확장 금지" 문구 — worker가 받는 카드 프롬프트 | 저 |

**삼표면 경로 총칭**: 원본 파일은 omo/senpi 설치본 경로(또는 우리 references/*.md). 사람 화면은 `board-dashboard.py`(포트 8787)가 서빙하는 웹 탭 또는 스크립트 stdout. 에이전트 창구는 (a)`curl http://127.0.0.1:8787/<endpoint>` (b)임명장 `skills/orca-conductor/references/appointment-template.md`의 카드 프롬프트 (c)실행 중 메시지 전송. **(c)의 두 경로를 분리한다(D-F-R-OMO-4 정정, 2026-08-11)**:

- **새 카드 발령**: `skills/orca-conductor/scripts/dispatch-safe.sh` — 실제 호출 `orca orchestration dispatch --task <id> --to <handle> --from <handle> --inject`(dispatch-safe.sh:86 실측). preamble 주입용이지 실행 중 임의 메시지 전송이 아니다.
- **실행 중 follow-up/steer(정상 메시지 제출)**: **구현 예정** `skills/orca-conductor/scripts/send-steer.sh` — packaged Orca CLI `orca terminal send --terminal <handle> --text <payload> --enter --json` 래핑(F-R-OMO-5: `--enter` 무조건 필수, 도움말 "Append Enter after sending text"·런타임 `\r` suffix 실측). 받는 handle 종류: 후보1=coordinator/supervisor handle, 후보3=active worker handle.
- **즉시 중단(후보3 전용, 별도 의미)**: `--interrupt`는 메시지 전달 방식이 아니라 Ctrl-C(`\x03`, 런타임 suffix 실측)다. 정상 메시지 명령에 `[--interrupt]`를 붙이지 않는다. 중단이 필요하면 두 단계로 분리 — (a)`orca terminal send --terminal <worker_handle> --interrupt --json` 중단, (b)TUI 입력 가능 후 별도 `--text <loop_reminder> --enter --json` 제출. 한 호출에 `--text`+`--interrupt` 섞지 않는다. 실제 구현은 별도 카드.
- send-steer.sh는 아직 없는 예정 파일이다(생성 금지). 후보5 상태 원장은 `.orca/runtime/<board>/terminal-transitions.jsonl`(board-dashboard.py가 읽어 /status.txt 노출, 예정).

"구현 예정" 표시는 현재 그 표면이 없고 별도 구현 카드에서 만들 경로임을 뜻한다. `dispatch-safe.sh`를 임의 메시지/steer 경로로 쓰면 안 된다(역할 모순).

### 비이식 목록 (이유)

- **ultrawork directive 본문(31KB)**: senpi 전용 도구명·용어. 우리 프롬프트 톤 충돌. 금지 토큰 7개 검증도 senpi 도구명 기준.
- **ULTRAWORK MODE ENABLED! 토큰 검증 로직**: omo에 검증 코드가 없음(좁은 사실, v1 IMPORTANT #7 유지). 이식할 실물 없음.
- **codemode eval 커널**: 실재하나 RCE 면(임의 코드 실행). AGENTS.md 안전 경계 충돌. 비이식.
- **senpi-task 전체 상태기계**: 파일 원장·RPC 러너 등 무거운 인프라. 원장 아이디어(#5)만 차용.
- **ultrawork 숨은 custom 메시지(display:false) 주입**: senpi 메시징 API 전용. 우리 터미널/카드 구조에 직접 대응 없음.

---

## 관점 7 (최우선). 의도 관문·턴 규율 코드 강제 지점 + [턴 종료] 판정 설계 (v1 전면 재작성)

### v1의 붕괴된 전제

v1은 "omo는 선언 토큰을 파싱해 턴 규율을 강제하지 않는다", "stop hook은 없고 agent_end뿐", "omo에 토큰 검증 실물이 없으니 우리가 새로 2계층을 만든다"는 전제로 관점 7을 세웠다. 검수가 이 전제들을 모두 거짓으로 판정했다(Intent Gate 실재, senpi.hooks.stop-state 실재). v2는 전제를 바로잡고 **omo의 기존 2계층을 먼저 정확히 매핑**한 뒤, 우리 신규 설계를 그 위에서 구분한다.

### omo/senpi의 기존 2계층 턴-종료 규율 (정확한 매핑)

**1계층 — 프롬프트층(바인딩 중지 선언)**

- intent-gate 라우팅 줄(`intent-gate.js:14`): `> I read this as [intent] - [plan].`
- 코어 preset들이 이 줄에 **바인딩 중지조건**을 추가:
  - claude-opus-5.js: `I'll stop when [the exact, observable condition that ends this turn].` + `Once declared it is binding: work until it holds; the moment it holds, ... deliver the final message, and stop. Stopping is mandatory and immediate.`
  - claude-fable-5.js: 동일 패턴.
  - gpt-5.6.js: `STOPPING IS MANDATORY AND IMMEDIATE` + Stop Goal 섹션.
  - grok-4.5.js, kimi-k3.js: 동일("declared stop condition is BINDING").
- 성격: 모델에게 **매 턴 관측 가능한 중지조건을 선언하라고 요구**(프롬프트). 검증 코드는 없다(요구만). ultrawork의 `ULTRAWORK MODE ENABLED!` 토큰 검증 부재(v1 좁은 사실, IMPORTANT #7 유지)와 혼동 주의 — intent-gate는 별개의 더 근본적인 라우팅 선언 요구다.

**2계층 — lifecycle층(Stop 훅)**

- `senpi.hooks.stop-state` Stop 훅 어댑터(`stop-adapter.js:3`). Stop 이벤트에서 `buildStopHookInput`으로 `stopReason`·`transcript_path` 전달.
- 재진입 제한 `STOP_REENTRY_LIMIT=8`(`:6`). block 시 `sendUserMessage(followUp, {deliverAs:"followUp"})`(`:76`)로 턴 재개.
- completion-bridge terminal transition: STORE의 terminal transition(5 상태)이 notifyTerminal 발화(`completion-bridge.ts:42-43,55-59`).

**omo 2계층 요약**: 프롬프트가 중지조건을 "요구"하고(선언), lifecycle 훅이 Stop 시점을 "포착"한다(상태). 선언과 포착이 분리돼 있다.

### 우리 환경과의 차이 — 무엇이 있고 없는가

| 표면 | omo | 우리(Orca + conductor) | 갭 |
|---|---|---|---|
| 중지조건 요구(프롬프트) | intent-gate + 코어 preset | 카드에 [턴 종료] 토큰 요구(문구) | 우리는 중지 '조건'이 아니라 '토큰'만 요구 |
| Stop 시점 포착(lifecycle) | senpi.hooks.stop-state Stop 훅 | worker_done 메시지(확정) + 터미널 idle(추정) | lifecycle 훅 직접 노출 미확인 |
| 루프 감지 | loop-guard:notice 런타임 | 없음 | 구현 필요 |
| 완료 판정 근거 | STORE terminal transition | worker_done 메시지 | 메시지 유실 시 회복 약함 |

### 우리 [턴 종료] 판정 설계안 (omo 실물 위에서, 신규 부분만)

v1이 "omo엔 없으니 새로 만든다"고 한 것과 달리, v2는 **omo의 2계층(선언 요구 + lifecycle 포착)을 먼저 빌리고**, 우리 환경에 없는 부분만 보강한다.

**A. 프롬프트층 — omo의 intent-gate 라우팅 줄 패턴 차용(이식 후보 #6)**

- 카드/프롬프트에 worker가 매 턴 "의도 - 계획 - 중지조건(관측 가능)"을 선언하도록 요구. omo의 `> I read this as [intent] - [plan]. I'll stop when [condition].` 패턴을 우리 카드 언어로 번역.
- 단, 이것은 **요구(프롬프트)**이지 기계 검증이 아님을 명시(omo도 마찬가지).

**B. lifecycle층 — worker_done을 주 신호로, idle을 보조(이식 후보 #2)**

- waker가 종료를 판정하는 1순위 근거는 `worker_done` 메시지(Orca CLI 확정 신호). 이것은 omo의 Stop 훅 + terminal transition에 해당.
- 보조 lifecycle 신호: 터미널 idle(프롬프트 복귀/정해진 시간 무 입력).
- 판정: worker_done 있음 = 종료 확정(토큰 부재와 무관). worker_done 없고 idle = "선언 없이 멈춤" -> waker 보고/재촉.

**C. 보조 토큰 검증 — [턴 종료] 관대한 매처(우리 신규, omo에 대응물 없음)**

- omo는 선언 토큰을 기계 검증하지 않는다(좁은 사실). 우리는 **추가로** 토큰 파싱을 만들 수 있다(omo가 안 하는 부분).
- idle 시점 최근 출력에 `[턴 종료]` 또는 허용 변형(전각/공백/영문)이 있는지 정규식 매칭.
- 판정표:

| worker_done | 토큰 | 판정 | waker 행동 |
|---|---|---|---|
| 있음 | 있음 | 정상 종료 | 보고 |
| 있음 | 없음 | 정상 종료(토큰 생략) | 보고, 경고 로그 |
| 없음 | 있음 | "선언만 하고 끝내지 않음" | waker 재활성화 확인 |
| 없음 | 없음 | idle면 "방치"/비-idle이면 "진행 중" | idle 재촉, 진행 중 대기 |
| 없음 | 형식 오류 | "형식 오류" | escalation(보고) |

**D. omo에서 빼올 구체 장치 (신규 설계에 통합)**

1. **batched-wake(omo-senpi:wake, 이식 후보 #1)**: 다수 worker의 idle/완료가 몰릴 때 waker가 한 번에 1회 coordinator 턴을 깨운다(200ms 배치 + 소스 우선순위 w1 맵). bundle `$y.#g`.
2. **terminal-transition 구동(이식 후보 #5)**: 판정 근거를 "메시지"가 아니라 "확정된 상태(worker_done 또는 idle)"로.
3. **loop-guard:notice(이식 후보 #3)**: 런타임 루프 감지로 worker 반복 검사 억제.
4. **arming 상태(재판정 방지)**: 한 턴의 종료 판정은 1회만(omo `markArmed`/STOP_REENTRY_LIMIT에 해당).

### 명시적 비이식 (이 설계안에서도)

- omo의 숨은 custom 메시지(display:false) 주입은 senpi API 전용.
- omo의 `ULTRAWORK MODE ENABLED!` 토큰 검증은 애초에 코드가 없으므로 빼올 게 없다. 우리 토큰 파싱(C)은 순수 신규.

### 남은 불확실성 (관점 7)

- Orca CLI가 `agent_end`/Stop에 해당하는 lifecycle 이벤트를 waker에게 직접 노출하는지 미확인(현재 check/heartbeat/worker_done 기반 추정).
- "idle"의 기계 판정 기준(프롬프트 정규식? 무 입력 N초?)은 별도 실측 필요.

---

## 파일:줄 근거 목록 (정정 후 전체)

| 주장 | 근거 |
|---|---|
| Intent Gate 실재 | `senpi/dist/core/dynamic-prompt/intent-gate.js:9,10,14`; 조립 `build.js:4,41`; 사용 agent-session.js basePrompt |
| intent-gate 라우팅 표/Reset/Completion Gate | `intent-gate.js:20-27,36-37,39-40` |
| loop-guard:notice 실재 | `senpi/dist/core/extensions/builtin/loop-guard/notice.js:1`; 감지 `:2-40`; 발동 `loop-guard/index.js:18,23-28`; 등록 `builtin/index.js:79` |
| senpi.hooks.stop-state 실재 | `senpi/dist/core/extensions/builtin/hooks/stop-adapter.js:3`; STOP_REENTRY_LIMIT `:6`; block followUp `:76`; 등록 `builtin/index.js:46`; 사용 `hooks/index.js:7` |
| codemode 실재 | `senpi/node_modules/@code-yeongyu/senpi-codemode`(py/js/jl/rb); 등록 `resource-loader.js:44,49-50`; 참조 `goal/prompt.js:59,63` |
| prompt-preset 바인딩 중지선언 | claude-opus-5.js, claude-fable-5.js, gpt-5.6.js, grok-4.5.js, kimi-k3.js의 라우팅 줄 |
| ultrawork input 훅 | `omo-senpi/src/components/ultrawork/index.ts:7,24-31,37-86`(로컬 src, origin/dev 대비 크게 뒤처짐 — rev-list=597, 2026-08-11) |
| ultrawork 주입(idle/queued) | `ultrawork/index.ts:109-118` / `:110-112` |
| ultrawork arming(beta.5) | bundle `omo.js` ~line 2258 `vT`/`vfn`/`Symbol.for("omo.ultrawork.arming")` |
| ULTRAWORK 토큰 검증 부재(좁은 사실 유지) | bundle grep: 본문 1722·2228줄 텍스트만, 검사 코드 0건 |
| omo-senpi:wake batched | bundle `omo.js:2` `$y.#g`(소스명 IdleInjectionCoordinator, minified->$y), `Je`, `w1` 맵, 200ms setTimeout |
| TERMINAL_STATUSES 5개 | `completion-bridge.ts:10-15`(로컬 src, origin/dev 대비 크게 뒤처짐 — rev-list=597, 2026-08-11); isTerminalApplied `:55-59` |
| terminal transition 원칙 | `completion-bridge.ts:26-27` 주석 |
| 작업상태 7 / 거주상태 5 | beta.5 bundle inline |
| 21개 스킬 | `plugin/skills/*/SKILL.md` |
| senpi 버전 | `omo-ai/node_modules/@code-yeongyu/senpi/package.json` 2026.8.11-2 |
| 라이브 임명장 beta.2 기록 | 라이브 main `agent-runners.json:96`(loop-guard:notice, senpi.hooks.stop-state 명시) |

## 변경 파일

- `docs/research/2026-08-11-omo-deep-analysis.md`(본 파일, v2 전면 재작성)
- `skills/conductor/references/agent-runners.json`(omo 절에 `deep_analysis_2026_08_11_beta5` 신규 키 append; 기존 beta.2 이력 보존)
- `.staging/result-F-R-OMO-1.md`(정정 요약)

## 남은 불확실성

1. **codemode 사용자 config on/off**: 등록은 확정이나 사용자 설정 기반 활성 여부 미확인(부재 주장이 거짓인 것엔 영향 없음).
2. **intent-gate 우회 경로**: omo 확장이 loaderSystemPrompt를 주입해 intent-gate를 우회하는 경로가 있는지 런타임 트레이스 외 100% 단정 불가(세션 JSONL 증거로 활성 판정은 충분).
3. **로컬 src 낡음**: 상태기계 구조 근거(completion-bridge.ts 등)는 크게 뒤처진 체크아웃(rev-list=597, 2026-08-11)에 의존. 값은 bundle inline으로 확정.
4. **Orca CLI lifecycle 노출**: waker가 agent_end/Stop 해당 신호를 직접 받는지 별도 실측 필요(관점 7).

## 실행한 확인 명령 (모두 읽기 전용, 산출물 작성 전)

- `git rev-parse --show-toplevel && git branch --show-current && git status --short`
- `find senpi/dist -name intent-gate.js/notice.js/stop-adapter.js`(4개 실물 위치)
- `cat -n intent-gate.js`(Intent Gate 전문 + 라우팅 줄)
- `cat -n loop-guard/notice.js`(3종 감지) + `cat -n loop-guard/index.js`(발동)
- `cat -n hooks/stop-adapter.js`(STOP_STATE_CUSTOM_TYPE, 재진입 제한) + `cat -n hooks/index.js`(활성)
- `rg builtin/index.js`(등록 목록 — loop-guard:79, hooks:46)
- `cat senpi-codemode/package.json` + `ls src/kernels`(py/js/jl/rb)
- `rg resource-loader.js/goal/prompt.js`(codemode 등록)
- `rg prompt-preset/* binding stop`(코어 preset 바인딩 중지선언)
- `rg dynamic-prompt/build.js index.js`(intent-gate 조립)
- `sed -n completion-bridge.ts`(TERMINAL_STATUSES 5개)
- `rg 라이브 main agent-runners.json omo`(beta.2 이행 + 96행 evidence)
- python3 json 검증(jq empty 통과)

(원본 수정·omo 실행 실험·커밋·push 없음. 4개 실물 파일은 읽기 전용 cat.)


---

## 관점 8. 문서 길이·구조 기준 조사 (R-OMO-2, 2026-08-11 추가)

### Why (이 절의 목적)

kyle의 스킬·표준 문서(mechanics.md 32,413자 등)가 너무 커져 읽기와 적용이 느려지는 것을 막기 위해, omo/senpi가 실제로 쓰는 문서 크기·구조 규칙을 코드·문서·실측 근거로 정리하고 우리 문서 리팩터링 기준을 제안한다.

### Q1. 명시적 줄 수·문자 수·바이트 상한이 있는가

결론: frontmatter 필드에만 있다. SKILL.md 본문(body) 길이 상한은 없다.

명시적 상한 — 성격별 분리(F-R-OMO-3 정정, 2026-08-11):

| 필드 | 상한 | 성격 | 근거 |
|---|---|---|---|
| name | 64자 | **코드 강제**(초과 시 진단 push, 경고 후 로드) | skills.js:9 MAX_NAME_LENGTH=64, 검증 validateName skills.js:61-75 |
| description | 1024자 | **코드 강제**(초과 시 진단 push, 경고 후 로드) | skills.js:11 MAX_DESCRIPTION_LENGTH=1024, 검증 validateDescription skills.js:80-87 |
| description 누락 | — | **코드 강제**(skill 미로드) | skills.js + docs skills.md:215 |
| compatibility | 500자 | **문서·명세 권고**(skills.js에 검사 0건) | docs/skills.md:151 표만, skills.js에 compatibility 문자열 0건 |

정정 비고(F-R-OMO-3): 이전 판에서 compatibility 500을 "코드 강제"로 같이 묶은 것은 오류다. skills.js 전수 rg compatibility = 0건. 코드가 실제로 검사하는 상한은 name/description뿐이다.

본문(body) 길이 상한: 없음. 검색 범위 — senpi/dist/core/skills.js(386줄) 전수에서 body|content_length|bodyLength|too long|truncat|warn.*size 0건. docs skills.md(260줄)에도 본문 길이 상한 언급 0건. 즉 omo는 SKILL.md 본문이 48,205자(ulw-research)여도 로드한다.

### Q2. SKILL.md frontmatter·필수 절·description·Triggers·references/scripts 분리 규칙

규칙 창구: senpi/docs/skills.md(260줄) + skills.js 코드. Agent Skills spec(https://agentskills.io/specification) 준용.

frontmatter 필수(skills.md:143-153 표, 코드 검증):

| 필드 | 필수 | 비고 |
|---|---|---|
| name | 예 | 64자, [a-z0-9-], 선행/후행/연속 하이픈 금지. 디렉토리명 일치는 senpi가 요구 안 함(skills.md:147) |
| description | 예 | 1024자. 이것만 항상 문맥에 상주 |
| license/compatibility/metadata | 아니오 | 선택 |
| allowed-tools | 아니오 | spec 필드지만 senpi 미구현, 무시 |
| disable-model-invocation | 아니오 | true면 system prompt에서 숨김, /skill:name 로만 |

필수 절: 공식적으로 없다. skills.md 예시는 "# Title" + 임의 절(Setup/Usage 등). "Triggers" 절은 omo의 관습(대부분의 스킬 description 안에 "Triggers: ..." 키워드를 박음)이지 규칙 아님(관점 3 참조).

분리 규칙(progressive disclosure, 핵심):

- skills.md:72: "This is progressive disclosure: only descriptions are always in context, full instructions load on-demand."
- skills.md:103: references/ = "Detailed docs loaded on-demand".
- skills.md:101: scripts/ = "Helper scripts".
- skills.md:265(skills.js): "When a skill file references a relative path, resolve it against the skill directory".

즉 분리는 구조적 권고(원본-표면 분리)이지 코드 강제가 아니다. loader는 SKILL.md만 찾고(skills.js:137 entry.name !== "SKILL.md" 체크), references/scripts는 상대경로 링크로 모델이 읽을 때 비용 발생.

### Q3. 21개 SKILL.md 실측 (줄/문자/바이트)

원자료: 각 plugin/skills/<name>/SKILL.md. 측정 명령: python3 len(txt)(chars), os.path.getsize(bytes), txt.count('\n')+1(lines).

| 통계 | lines | chars |
|---|---|---|
| 최소 | 67 (ulw-loop) | 5,570 (git-master) |
| 중앙값 | 244 | 17,517 |
| p90 | 547 | 30,860 |
| 최대 | 771 (refactor) | 48,205 (ulw-research) |

상위 5개(chars): ulw-research(48,205) · programming(38,792) · ultrawork(30,860) · hyperplan(27,383) · visual-qa(27,161).

대조: 우리 mechanics.md는 32,157자(wc -m, chars) / 57,207 bytes. omo 최대(ulw-research 48,205자)보다 작고, p90(30,860)과 비슷한 수준이다. 단 omo는 description(<=1024자)만 항상 로드하고 본문은 on-demand인 반면, 우리 mechanics.md는 규칙 창구(curl)에서 삼표면 원칙상 원본을 통째로 내보내므로 에이전트 curl 토큰 비용이 곧장 본문 전체 크기다.

### Q3a. 21개 전체 측정표 (F-R-OMO-2 정정, 2026-08-11 추가)

R-OMO-2 원본 Q3는 요약 통계와 chars 상위5만 기록했다. kyle이 추정 없이 다시 셀 수 있도록, 21개 파일 전수(lines/chars/bytes)와 세 통계량의 계산 규칙을 이 절에 보충한다.

**측정 루트·개수**: `/Users/fw_m1/.nvm/versions/node/v24.18.0/lib/node_modules/omo-ai/plugin/skills/<name>/SKILL.md` — 21개(루트의 각 하위 디렉토리마다 SKILL.md 1개).

**측정 규칙(재현용 python3)**:
- `lines = txt.count('\n') + 1` — **논리적 줄 수**(마지막 줄까지 포함). 주의: 21개 SKILL.md는 모두 파일 끝 개행이 있으므로 `wc -l`(개행 문자 수)은 이 값보다 1 작다. 본 보고서의 모든 lines 값은 논리적 줄 수 기준이다(`wc -l` 기준 통계는 이 절 끝의 대조표 참조)
- `chars = len(txt)` (파이썬 str 문자 수; wc -m 과 동일)
- `bytes = os.path.getsize(f)` (파일 바이트 수; wc -c 와 동일; UTF-8 다바이트 문자로 chars < bytes)

**p90 정의**: nearest-rank 방식. N=21일 때 rank = ceil(0.9 × 21) = ceil(18.9) = 19, 즉 오름차순 정렬 시 19번째 값(1-based). 참고로 numpy 선형 보간((N-1)×0.9 = 18.0, 0-based 인덱스 18 = 19번째)도 같은 값을 낸다 — N=21·p=90에서는 두 방식이 일치.

**21개 전수 표 (chars 오름차순)**:

| # | 스킬(SKILL.md) | lines | chars | bytes |
|---|---|---:|---:|---:|
| 1 | git-master | 105 | 5,570 | 5,570 |
| 2 | lsp-setup | 140 | 6,283 | 6,317 |
| 3 | give-me-tips | 103 | 6,491 | 6,491 |
| 4 | ulw-loop | 67 | 7,001 | 7,009 |
| 5 | data-scientist | 244 | 10,530 | 10,608 |
| 6 | ultimate-browsing | 141 | 10,706 | 10,752 |
| 7 | coding-agent-sessions | 133 | 11,410 | 11,414 |
| 8 | init-deep | 305 | 11,722 | 11,770 |
| 9 | debugging | 118 | 12,306 | 12,440 |
| 10 | ast-grep | 273 | 12,422 | 12,517 |
| 11 | ulw-plan | 136 | 17,517 | 17,525 |
| 12 | frontend | 148 | 19,013 | 19,125 |
| 13 | start-work | 233 | 21,173 | 21,221 |
| 14 | remove-ai-slops | 353 | 23,288 | 23,463 |
| 15 | review-work | 565 | 24,387 | 24,393 |
| 16 | refactor | 771 | 26,398 | 26,510 |
| 17 | visual-qa | 350 | 27,161 | 27,269 |
| 18 | hyperplan | 461 | 27,383 | 27,511 |
| 19 | ultrawork | 547 | 30,860 | 31,050 |
| 20 | programming | 398 | 38,792 | 38,926 |
| 21 | ulw-research | 408 | 48,205 | 48,523 |

**세 통계량(각각 lines/chars/bytes)**:

| 통계 | lines | chars | bytes |
|---|---:|---:|---:|
| 최소 | 67 (ulw-loop) | 5,570 (git-master) | 5,570 (git-master) |
| 중앙값(11번째) | 244 (data-scientist) | 17,517 (ulw-plan) | 17,525 (ulw-plan) |
| p90(nearest-rank, 19번째) | 547 (ultrawork) | 30,860 (ultrawork) | 31,050 (ultrawork) |
| 최대 | 771 (refactor) | 48,205 (ulw-research) | 48,523 (ulw-research) |

**chars 상위 5**: ulw-research(48,205) · programming(38,792) · ultrawork(30,860) · hyperplan(27,383) · visual-qa(27,161).

**bytes 상위 5**: ulw-research(48,523) · programming(38,926) · ultrawork(31,050) · hyperplan(27,511) · visual-qa(27,269). (chars 순위와 동일 — 다바이트 문자 비율이 스킬 간 크게 다르지 않음.)

**기존 Q3/Q6 대조(모순 점검)**:
- Q3 요약(lines min 67 / median 244 / p90 547 / max 771; chars min 5,570 / median 17,517 / p90 30,860 / max 48,205) — 전수 표와 완전 일치. 모순 없음.
- Q3 chars 상위5(ulw-research·programming·ultrawork·hyperplan·visual-qa) — 동일. 모순 없음.
- Q6(mechanics.md 32,157자, ultrawork 30,860, ulw-research 48,205) — 본 표와 일치. 모순 없음.
- 단 R-OMO-2 원본은 bytes 컬럼과 p90 계산 규칙(nearest-rank)을 명시하지 않았다 — 이것이 이번 정정이 채운 빈칸이다(숫자 오류가 아니라 명세 누락).

**재현 명령**:
```
python3 -c "
import os
SP='/Users/fw_m1/.nvm/versions/node/v24.18.0/lib/node_modules/omo-ai/plugin/skills'
for d in sorted(os.listdir(SP)):
    f=os.path.join(SP,d,'SKILL.md')
    if os.path.isfile(f):
        t=open(f,encoding='utf-8').read()
        print(f'{d:<24}{t.count(chr(10))+1:>6}{len(t):>9}{os.path.getsize(f):>9}')
"
```

### Q3b. wc -l 대조 (F-R-OMO-3 정정, 2026-08-11 추가)

R-R-OMO-2 IMPORTANT 1: 본 보고서 lines는 논리적 줄 수(`count(newline)+1`)인데 이전 판이 "wc -l과 동일"이라 한 것은 21개 모두 끝 개행이 있어 틀렸다(`wc -l`=개행 수). 같은 단위로 재현 가능하도록 wc -l 통계를 별도로 둔다.

**wc -l 기준 통계**(21개 모두 endswith('\n')=True이므로 wc -l = 논리적 줄 수 - 1):

| 통계 | lines (논리적, 본문 기준) | wc -l (개행 수) |
|---|---:|---:|
| 최소 | 67 (ulw-loop) | 66 |
| 중앙값 | 244 (data-scientist) | 243 |
| p90 nearest-rank(19번째) | 547 (ultrawork) | 546 |
| 최대 | 771 (refactor) | 770 |

샘플 검증(git-master/ulw-loop/refactor/ulw-research/ultrawork): `count(nl)+1` = 105/67/771/408/547, `wc -l` = 104/66/770/407/546 — 모두 1 차이. 본문 전체의 lines 값은 **논리적 줄 수** 기준으로 유지하고, 셸 재현 시에는 wc -l이 1 작음을 감안할 것.

재현:
```
python3 -c "
import os,subprocess
SP='/Users/fw_m1/.nvm/versions/node/v24.18.0/lib/node_modules/omo-ai/plugin/skills'
for d in sorted(os.listdir(SP)):
    f=os.path.join(SP,d,'SKILL.md')
    if os.path.isfile(f):
        t=open(f,encoding='utf-8').read()
        wcl=int(subprocess.check_output(f"wc -l < '{f}'",shell=True).strip())
        print(f'{d:<24} logic={t.count(chr(10))+1:>5} wc-l={wcl:>5}')
"
```

### Q4. 큰 문서의 references/scripts 분리 패턴

결론: omo는 길이가 길다고 자동 분리하지 않는다. 분리는 선택적이고 목적별다.

실측(21개):

- 큰데도 SKILL.md만(분리 없음): ultrawork(30,860자, 선언문 전문을 한 파일에), hyperplan(27,383자), review-work(24,387자), refactor(26,398자), remove-ai-slops(23,288자), start-work(21,173자).
- references/scripts로 분리(F-R-OMO-3 정정: 단위 명시 — 아래는 **최상위 항목 수**(`ls` 기준). 재귀 파일 수는 괄호 안 별도):
  - programming(7 ref + 4 scripts; 재귀 53 ref + 20 scripts), frontend(4 ref + 1 script; 재귀 168 ref + 1 script), visual-qa(1 ref + 10 scripts; 재귀 1 + 10), lsp-setup(20 ref + 4 scripts; 재귀 20 + 4), ast-grep(7 ref + 1 script; 재귀 7 + 1), ulw-plan(3 ref + 1 script), ulw-research(1 ref).
  - 단위가 섞이면 독립 재현이 안 된다 — 최상위 항목 수(ls)와 재귀 파일 수(find -type f)를 분리 표기. frontend references는 최상위 4개이나 하위 언어별 README가 재귀로 168파일.
- 작아도 분리: lsp-setup(11,722자인데 references 20 files) — 언어별 README 분리가 목적.

패턴:
1. 선언문/규칙 전문은 한 파일(ultrawork directive, hyperplan, refactor). 모델이 한 번에 로드해야 규칙이 단절 없이 적용되기 때문. 분리하면 "앞부분만 로드" 실패 모드가 생긴다.
2. 언어/도구별 세부 지침은 references로(lsp-setup 20 files, programming 7 ref). 본문은 라우팅/개요만, 세부는 on-demand.
3. 실행 가능한 도구는 scripts로(visual-qa 10 scripts, data-scientist 3, ultimate-browsing 4).

즉 omo의 분리 기준은 "줄 수"가 아니라 "언제 로드되어야 하는가"(항상 vs on-demand)와 "실행 가능한가 vs 텍스트인가"다.

### Q5. 길이 제한이 코드 강제인지 문구 권고인지

| 제한 | 성격 | 근거 |
|---|---|---|
| name 64자 | 코드 강제(초과 시 진단 push, 경고 후 로드) | skills.js:9,63-64 |
| description 1024자 | 코드 강제(동일) | skills.js:11,85-86 |
| description 누락 | 코드 강제(미로드) | skills.js + docs :215 |
| compatibility 500자 | **문서·명세 권고**(skills.js 검사 0건) | docs skills.md:151 표만 |
| 본문 길이 | 없음(강제도 권고도 아님) | grep 0건 |
| references/scripts 분리 | 문구 권고(progressive disclosure 원칙, 코드 미검사) | docs :72,103 |

(F-R-OMO-3 정정): 이전 판은 compatibility 행을 빼고 본문 길이로 바로 넘어갔다. Q1 표와 일치시켜 compatibility 500을 문서 권고로 명시한다.

핵심: omo는 "언제 로드되는가"(description=항상, 본문=on-demand)로 비용을 통제하지, "몇 줄이냐"로 통제하지 않는다.

### Q6. mechanics.md(32,413자)와 omo 분포 비교 (동일 단위)

규칙 창구(rules.txt)는 mechanics.md를 32,413자로 표시한다. 이는 bytes가 아니라 창구 자체의 계산(wc -m chars=32,157, wc -c bytes=57,207). 창구의 "32,413자"는 렌더링된 텍스트 기준으로 추정(정확 단위는 별도 확인 필요, 아래 불확실성).

비교(모두 chars, wc -m 기준):

| 문서 | chars | omo 분포에서 위치 |
|---|---|---|
| mechanics.md(우리) | 32,157 | p90(30,860) 바로 위, 최대(48,205) 아래 |
| rally-log.md(우리) | 37,475 | p90 초과, 최대에 근접 |
| ultrawork(omo) | 30,860 | omo p90 |
| ulw-research(omo 최대) | 48,205 | omo 최대 |
| appointment-template(우리) | 6,175 | omo 최소(5,570) 근처 |

해석: 우리 큰 문서 3개(mechanics, rally-log, incident-log 29,904)는 omo의 p90~최대 구간에 있다. omo 기준으로 "비정상"은 아니지만, omo는 본문이 on-demand 로드라 이 크기가 description에 안 들어가는 반면, 우리는 삼표면 원칙상 규칙 창구(curl)가 원본을 통째로 내보내므로 이 크기가 곧 에이전트 토큰 비용이다. 이것이 mechanics.md 0절 "경계선 2(원본 다이어트)"가 말하는 정확한 비용 구조다.

### Q7. 우리 문서 재정리 후보 (삼표면 유지, 직접 리팩터링 안 함)

제안만. 실행은 별도 카드. 삼표면(원본 파일 + 사람 화면 + 에이전트 창구)을 유지하되, omo의 progressive disclosure를 빌린다.

| 후보 | 현재 | 제안 | 삼표면 유지 |
|---|---|---|---|
| mechanics.md 32,157자 | 원본 1파일, 창구가 통째로 curl | omo 식: 항상 로드되는 "요약+0절 삼표면 원칙"을 description급(<=1024자 권고)으로, 상세 사고 사례는 references/로 on-demand 분리 | 원본은 여러 파일로, 사람 화면(목차)은 요약만, 에이전트 창구는 ?doc=<부분>로 필요한 것만 |
| rally-log.md 37,475자 | 원본 1파일 | 시간 경과에 따른 append 로그는 날짜별로 분할 또는 아카이브(archive/) 이동 후 최신만 references에 | 원본은 분할 파일, 화면은 최신 N건, 창구는 최신만 |
| incident-log.md 29,904자 | 원본 1파일 | 사고별로 개별 파일(references/incidents/)로, 본문은 색인만 | 원본은 사고별, 화면은 색인, 창구는 ?doc=<사고명> |
| SKILL.md(conductor/orca-conductor) | 각 12,753자 | description(<=1024자)은 항상 로드, 본문 규칙은 절로, 긴 예시는 references로 | omo 표준 준용 |

비제안(분리 금지): ultrawork급 선언문(규칙이 단절 없이 적용되어야 하는 것)은 한 파일로 둔다 — omo가 ultrawork(30,860자)를 분리 않은 이유와 동일. mechanics.md 0절 삼표면 원칙 자체도 선언문 성격이라 분리 대상이 아니다(분리 대상은 0절 뒤의 사고 사례·세부 운영 규칙).

### Q8. 규칙 창구 새 계약 (사용 확인)

목차: curl -s http://127.0.0.1:8787/rules.txt 동작 확인. 반환: mechanics.md(32,413자 표시), appointment-template, routing-providers.json, agent-runners.json 4건 목차 + 수정 시각.
전문: curl -s 'http://127.0.0.1:8787/rules.txt?doc=mechanics' 동작 확인. mechanics.md 0절 삼표면 원칙("경계선 2: 원본이 뚱뚱하면 창구도 뚱뚱하다") 확보.

이 창구가 이미 "삼표면 중 에이전트 창구" 역할을 하고 있으므로, 재정리 후보(Q7)는 이 창구와 호환되게 설계한다(원본 파일 분리 -> 화면 목차 항목 추가 -> 창구 ?doc= 로 노출).

### 관점 8 파일:줄 근거

| 주장 | 근거 |
|---|---|
| name 상한 64 | senpi/dist/core/skills.js:9 MAX_NAME_LENGTH=64 |
| description 상한 1024 | skills.js:11 MAX_DESCRIPTION_LENGTH=1024 |
| 본문 길이 상한 없음 | skills.js(386줄) grep body/limit/length 0건; docs skills.md(260줄) 0건 |
| progressive disclosure | senpi/docs/skills.md:72 |
| references on-demand | skills.md:103 |
| description 누락=미로드 | skills.js + skills.md:215 |
| 21개 실측 | python3 각 SKILL.md(len/getsize) |
| 분리 패턴 | 각 skills/<name>/ 폴더 ls 실측 |
| mechanics.md 크기 | wc -m=32,157, wc -c=57,207; 창구 표시 32,413자 |
| 삼표면 원칙(0절) | 규칙 창구 ?doc=mechanics, "경계선 2 원본 다이어트" |
| 규칙 창구 동작 | curl rules.txt / ?doc=mechanics 실측 |

### 관점 8 남은 불확실성

1. 창구 "32,413자" 단위: wc -m(32,157)·wc -c(57,207)와 다름. 창구의 렌더링/개행 계산 방식 미확인. chars로 해석하면 omo p90 근처, bytes로 해석하면 omo 최대 초과 — 해석이 달라지므로 창구 계산 로직 확인이 권고됨.
2. omo SKILL.md 본문 on-demand 로드의 정확한 트리거: description 매칭 후 모델이 판단해 로드하는 것은 docs 서술이나, 런타임 트레이스로 "언제 본문이 문맥에 들어가는가"를 직접 관측하지는 않음.
3. 우리 conductor(신규) references 부재: skills/conductor/references/*.md가 이 worktree에 없다(아직 생성 전). orca-conductor 쪽에만 존재. 재정리 후보 적용 시 대상 판단 필요.
