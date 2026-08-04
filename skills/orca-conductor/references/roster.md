# 엔진 카탈로그 + 역할 편성표 (roster)

이 파일은 **실행 명령(엔진)과 역할 편성의 단일 진실**이다. 명령·편성 수정은 여기서만 한다.

## 구조 (2026-07-19 kyle 승인 개편)

기존 `(역할)-(CLI)-(모델)-(강도)` 4단 ID는 같은 실행 명령이 역할 수만큼 중복 등록되는 문제가 있었다
(예: `recon-gjc-sol`/`review-gjc-sol-ultra`/`dev-gjc-sol-ultra`가 전부 `gjc --mpreset codex-pro`).
역할은 실행 명령의 속성이 아니라 **카드(발령문)의 속성**이므로 두 축을 분리한다.

```
[1층 엔진 카탈로그]  cli-모델(-강도)  =  실행 명령     ← 모델당 1행, 역할 없음
[2층 역할 편성표]    역할 × 난이도  =  엔진 ID 체인   ← 역할은 여기에만 존재
```

- 터미널 제목은 사람이 알아보게 `역할-엔진` 형식을 유지한다 (예: `dev-codex-luna`, `review-gjc-codexpro`) — 표기 관습이지 카탈로그 항목이 아니다.
- 새 모델 추가 = 카탈로그 1행. 역할 조정 = 편성표만 수정.

## 1층 — 엔진 카탈로그

엔진 ID = `cli-모델별칭(-강도)`. 강도를 생략하면 그 CLI의 기본값.

**모델 별칭표**

| 별칭 | 정식 모델명 | 위치 | 비고 |
|---|---|---|---|
| luna | gpt-5.6-luna | codex | 가격 인하 뒤 고강도 비용 효율 우수. 중계 high, 구현 xhigh를 기본 시험값으로 사용 |
| sol | gpt-5.6-sol | codex, gjc(codexpro) | GPT 주력 |
| terra | gpt-5.6-terra | codex, gjc(codexpro EXECUTOR) | sol 반값 — 정식 편입(2026-07-20 kyle). codex 직접 호출 기동은 첫 발령 때 실측 |
| glm5.2 | glm-5.2 | codex(opencodex 프록시, zai) | 컨텍스트 1M. gjc(zai)에서 이관 (2026-07-21 kyle 결정) |
| fable | fable (Claude Fable 5) | claude | 퇴역 가능성 — 항상 최후순위 (2026-07-13 kyle 결정) |
| opus5 | opus (Claude Opus 5 최신 별칭) | claude | 고급 독립 검수 후보. Fable 전용 한도와 분리해 사용 |
| kimi | K3 1M (kimi/k3[1m]) | codex(opencodex 프록시, kimi) | 구현 사다리 1단. kimi CLI에서 codex CLI로 이관 (2026-07-21 kyle 결정). 컨텍스트 1M |

**엔진 목록**

| 엔진 ID | 실행 명령 | 강도 스케일 | 상태 |
|---|---|---|---|
| `codex-luna-<강도>` | `codex -p orca-worker --model gpt-5.6-luna -c model_reasoning_effort="<강도>" --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust` | low·medium·high·xhigh·max | 검증됨 |
| `codex-sol-<강도>` | `codex -p orca-worker --model gpt-5.6-sol -c model_reasoning_effort="<강도>" --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust` | low·medium·high·xhigh·max | 검증됨 |
| `codex-terra-<강도>` | `codex -p orca-worker --model gpt-5.6-terra -c model_reasoning_effort="<강도>" --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust` | low·medium·high·xhigh·max | **기동 검증됨 (2026-07-23 실측)** — 상태바 gpt-5.6-terra 확인, opencodex 경유 정상 기동. effort 표시가 "default"로 나오는 현상 있음(플래그 반영 여부 추가 실측 필요) |
| `codex-kimi1m-<강도>` | `codex -p orca-worker --model "kimi/k3[1m]" -c model_reasoning_effort="<강도>" --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust` | low·high·max (카탈로그 실측 2026-07-21 `ocx models` — medium·xhigh·ultra 없음) | **주력 (2026-07-21 kyle 결정 — kimi CLI에서 이관)**. opencodex 프록시 경유. 모델 슬러그에 `[1m]` 대괄호가 있어 셸 글롭 방지용 따옴표 필수. 첫 발령 때 기동 실측 |
| `codex-glm52-<강도>` | `codex -p orca-worker --model "zai/glm-5.2" -c model_reasoning_effort="<강도>" --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust` | low·medium·high·xhigh·max (카탈로그 실측 2026-07-21 `ocx models` — ultra 없음). **구현 기본 강도 = medium (2026-07-21 kyle 결정)** | **주력 (2026-07-21 kyle 결정 — gjc-glm에서 이관)**. opencodex 프록시 경유. gjc의 `--model glm-5.2` 즉사 사고와 별개(codex CLI는 카탈로그 슬러그 직결). 첫 발령 때 기동 실측 |
| `gjc-glm-<eco|medium|pro>` | `gjc --mpreset glm-<eco|medium|pro>` (필요 시 `--thinking` 병용) | 프리셋 3단이 곧 effort 단계 | **비상 대안 (2026-07-21 kyle — codex-glm52로 이관, 프록시 다운 시만)**. glm-pro·glm-eco 검증됨(2026-07-20 기동 실측). **`--model glm-5.2` 금지(2026-07-20 실측): 퍼지 매칭이 API 키 없는 deepinfra 채널을 잡아 "No API key" 즉사** |
| `gjc-codexpro` | `gjc --mpreset codex-pro` | (역할별 자동: DEFAULT sol:medium / EXECUTOR terra:medium / PLANNER sol:high / CRITIC sol:max / ARCHITECT sol:xhigh) | 검증됨 |
| `claude-fable-<강도>` | `claude --model fable --effort <강도> --dangerously-skip-permissions` | low·medium·high·xhigh·max (2026-08-04 실측 — xhigh 기동 응답 확인, 무효값 `ultra`는 경고 후 무시되므로 무경고 통과 = 유효) | 검증됨 · 최후순위 보루 + **검수 실험 후보 등록 (2026-08-04 kyle 결정)** — 라우터에 reviewer medium/high/xhigh 실험 10%씩. 지휘자와 Anthropic 쿼터 공유 주의 |
| `claude-opus5-<강도>` | `claude --model opus --effort <강도> --dangerously-skip-permissions` | low·medium·high·xhigh·max | **기동 검증됨 (2026-07-25 실측)** · 정식 검수 후보. 기본 강도 medium |
| `opencode-glm52` | `opencode` (kyle 설정 기본 프로필 — 내부 모델 zai GLM 5.2, `~/.config/opencode/` 기준) | opencode 내부 설정 따름 | **보조 검수 전용 (2026-07-28 kyle 승인 등록)** — 실전 기동·검수 1회 검증(openapi-prod-prep 최종 독립 검수 PASS). 용도: sol 보안 필터 차단 시, codex 하네스 전체 불능 시, 실행자와 하네스까지 분리한 독립 검수가 필요할 때. **주의**: orca dispatch --inject 미검증 — 발령은 gjc식 수동 배달 절차 사용. 라우터(routing-providers.json) 미등록 — 수동 편성 전용. 쿼터는 zai(glm) 계열 공유 |
| `kimi` | `kimi --yolo` | Low·High·Max — 단 기동 플래그 없음, TUI 내 선택(발령 전 설정, 캐시 무효화 주의) | **비상 대안 (2026-07-21 kyle — codex-kimi1m으로 이관, 프록시 다운 시만)**. 검증됨 |

**주의 (실측 승계)**:

- **opencodex 이관 후 GPT 직결 엔진(sol/luna/terra) 404 대응 (2026-07-22 실측·복구 확인)**: opencodex가 `codex` 명령을 wrapper shim으로 바꾸고 `~/.codex/config.toml`에 `openai_base_url=http://127.0.0.1:10100/v1`을 자동 주입한다. 프록시에 OpenAI provider가 없거나 **런타임 미반영**이면 sol 호출이 404("No enabled canonical OpenAI provider") 즉사. **정식 복구(권장): `ocx provider add openai` → `ocx restart`(설정만 바꾸고 재시작 안 하면 실행 중 프록시가 옛 상태를 들고 있어 404 지속 — 실사고). 복구 후 일반 `codex --model gpt-5.6-sol`이 프록시 경유로 정상.** 프록시 재시작은 도는 kimi/glm 작업자에 영향을 주니 활성 작업자 없을 때. 임시 우회(재시작 불가 시): 정식 바이너리(`codex.opencodex-real`) + `-c openai_base_url="https://chatgpt.com/backend-api/codex"`로 프록시를 건너뛰어 chatgpt 직결. 폴백 복귀 판정은 `scripts/probe-codex.sh`(발령 전 1회, mechanics 참조) — 유휴 터미널 상태바는 stale이라 판정 근거 금지.

- gjc의 GPT 호출은 반드시 `--mpreset codex-pro`. 접두사 없는 `--model gpt-5.6-sol`은 API 키 없는 채널을 잡아 "No API key" 즉사, `--model codex-pro`는 조용히 무시되고 GLM으로 뜬다(실측). 단일 GPT 모델 강제는 전체 ID `openai-codex/gpt-5.6-sol`. 기동 후 `/model`의 Current 확인이 안전.
- codex 엔진에는 `--dangerously-bypass-hook-trust`를 기본 포함한다 (2026-07-18 훅 게이트 실측 — 훅이 전부 kyle의 omo/Orca 훅이라 소스 검증 전제 충족).
- **codex 엔진에는 경량 프로필을 기본 포함한다 (2026-07-23 메모리 폭주 사고 대응, 실측 5회 검증)**: 전역 설정은 에이전트 1개당 보조 프로세스 5~7개(OMO LSP·CodeGraph+감시자·Playwright·Context7·node_repl·sites server.mjs)를 자동 생성하고, Codex의 MCP 중복 재생성 버그(옛 세트 방치)와 겹치면 수십 배로 증식한다(실측: 관련 프로세스 631개·12GB). 역할별 프로필로 발령한다 — **기본은 `-p orca-worker`(OMO 스킬·규칙·훅·서브에이전트 유지 + LSP만 켬, 자식 1개)**:

  | 역할 | 발령 플래그 | 자식 프로세스 |
  |---|---|---|
  | 일반 구현자·검수자 (기본) | `-p orca-worker` | LSP 1개 |
  | 코드 구조 분석 전담 | `-p orca-analyst` | LSP + CodeGraph |
  | 브라우저 QA | `-p orca-worker -c mcp_servers.playwright.enabled=true` | LSP + Playwright |
  | 데스크톱 QA | `-p orca-worker -c mcp_servers.node_repl.enabled=true` | LSP + node_repl |
  | 문서 조사 (라이브러리 최신 문서) | `-p orca-worker -c mcp_servers.context7.enabled=true` | LSP만 (context7은 원격 url 방식이라 프로세스 0 — 2026-07-23 전역 전환) |
  | 최소형 (문서 잡일 — OMO 자체 불필요) | `-p orca-lean` | 0개 (주의: OMO 훅까지 꺼짐) |

  프로필 파일은 `~/.codex/orca-{worker,analyst,lean}.config.toml` (신형 문법 — 별도 파일 필수, config.toml 안 `[profiles.X]` 테이블은 `-p` 사용 시 에러). **`-c`로는 플러그인 MCP를 못 끄고**(`plugins.*` -c 전달 무효 — 실측 2회) **전역 `mcp_servers.*`는 -c가 프로필을 이긴다**(재켜기 실측) — 그래서 켜기는 -c, 플러그인 끄기는 프로필 담당이다. 동시 실행 codex 일꾼은 **8개 이하**를 기본 상한으로 한다.
- **opencodex 경유 프리셋(`codex-kimi1m-*`, `codex-glm52-*`)은 프록시가 떠 있어야 작동한다 (2026-07-21 등록)**: 이 모델들은 opencodex 카탈로그 슬러그로만 존재하며, 로컬 프록시(`http://127.0.0.1:10100`)가 꺼져 있으면 기동이 실패한다. 이 프리셋 계열로 첫 발령하기 전에 지휘자가 `ocx ensure`를 한 번 실행해 프록시 기동과 카탈로그 동기화를 확인한다 (응답이 안 나오면 `ocx status` → `ocx start`).
- **Codex 하네스 OAuth 장애는 provider 장애와 분리한다 (2026-07-24 실측)**: `auth.openai.com/oauth/token` 오류는 Kimi·GLM 모델 로그인이 아니라 그 모델을 감싼 Codex CLI의 ChatGPT OAuth 갱신 실패다. 프롬프트는 입력되지만 ocx와 실제 provider에 도달하기 전에 턴이 끝날 수 있다. `ocx ensure`는 프록시 복구, `ocx account refresh <provider>`는 사용량 보고 갱신이므로 이 오류의 직접 복구가 아니다. 같은 Codex 하네스의 Terra·Sol로 모델만 바꾸는 것도 복구로 인정하지 않는다. 표준 복구는 살아 있는 같은 터미널에서 30초→90초→180초 점증 간격으로 최대 3회 진행한다. 각 시도 전 `codex login status`와 `ocx doctor`를 확인하고 둘이 정상이면 즉시 `이어서 진행`을 보낸다. 3회 모두 같은 OAuth 오류면 자동 재시도를 멈추고 `codex login` 재인증 또는 Codex가 아닌 하네스 전환을 decision gate로 올린다. 반대로 Kimi 자체 인증 오류는 Kimi API/provider 근거가 있을 때만 `ocx login kimi`, 429는 해당 provider만 불능 처리한다.
- **gjc는 Codex가 아니라 별도 설치된 독립 CLI다** (`~/.bun/bin/gjc`). 사용량은 `gjc stats`, Codex 쿼터와 별개. 단 `gjc stats`가 2분+ 무응답이면 불능으로 판정하고 폴백한다 (2026-07-19 실측).
- 전권 플래그는 Orca 순정 실행과 동일한 수준이다. 통제는 플래그가 아니라 안전 규칙과 결정 관문에서 잡는다.
- Orca 설정 → 에이전트에 커스텀 에이전트로 등록하면 GUI 콤보박스에서도 쓸 수 있다(선택). 등록 이름은 `역할-엔진` 관습을 따른다.

## 지휘자에 대하여 (엔진 아님)

지휘자는 **kyle이 말 걸고 있는 세션 그 자체**다 — Orca 안이든 밖이든. 모델·강도는 그 세션의 설정을 따르며 roster가 정하지 않는다. 지휘 역할은 Fable 세션에서 수행한다 (카드 설계 품질 때문).

## 운용 모드 (kyle 수동 온오프 — 이 줄만 바꾸면 됨)

**현재 모드: `토큰최적화`**   ← `토큰최적화` | `토큰맥싱`

- **토큰최적화**: 쿼터를 아껴야 할 때. 난이도에 맞춰 저렴한 엔진부터.
- **토큰맥싱**: 쿼터 여유 있을 때. low라도 싼 엔진 안 쓰고 전 난이도 상위 엔진.

## 강도 운용 원칙 (2026-07-20 kyle v4)

**기본 구현은 Low/medium으로 빠르게 돌리고, 검수는 sol-medium을 기본 품질 기준으로 둔다. Luna는 2026-07-31 가격 인하와 DeepSWE 고강도 성능을 근거로 구현 xhigh를 제한적 실제 탐색 후보로 다시 연다. 중계·순찰은 high를 기본으로 쓴다. Luna max는 2026-08-03 kyle 결정으로 동적 라우터에 다시 등록하되, 과거 서브에이전트 폭주·정체 위험 때문에 개발자는 안전한 카드의 10% 실험 슬롯, 검수자는 Sol·Opus보다 낮은 폴백 후보로만 사용한다.** terra 구현은 medium/high 2단을 유지한다.

## 2층 — 역할 편성표

이 층은 **"누가 하나"(엔진 선택·effort·폴백·쿼터)만** 정한다. 왕복 절차·라운드 사다리·검수 규칙(LIGHT/HEAVY 합격 기준, 재검수 범위, 래칫, 배틀 오프닝)의 원본은 `tiki-taka.md`다 (2026-07-21 kyle 구조 개편).

### 구현 엔진

편성은 고정 폴백 사다리가 아니라 **현재 사용 가능 여부 + 주간/5시간 할당량 + 역할 품질 + 작업자/검수자 분리**를 함께 점수화한다. 라운드 불합격 대응(수정→재설계→에스컬레이션)은 `tiki-taka.md` 라운드 사다리이고, provider 불능은 품질 승급과 별개다. (근거: rally-log `rottie-m10`)

**동적 편성 선택기 (2026-07-24 kyle 결정)**: 구현·검수 발령 직전에 `scripts/select-routing-pair.sh`를 실행한다. 이 래퍼가 PEP 723 의존성을 `uv run`으로 준비하므로 `select_routing_pair.py`를 시스템 `python3`로 직접 실행하거나 Typer를 전역 설치하지 않는다. 먼저 429·반복 기동 실패 provider를 후보에서 제외하고, 남은 작업자+검수자 조합을 전부 다시 점수화한다. 주간/5시간 잔여량이 예약선 아래로 내려가는 조합은 금지하지 않고 `last_resort`로 뒤로 보낸다. 같은 provider 계열 조합(Terra→Sol 포함)도 금지가 아니라 감점 대상이며, 다른 정상 조합이 없을 때 선택할 수 있다. Kimi 검수는 신뢰도가 낮아 Sol보다 낮은 품질 점수로 등록한다. 새 provider는 `references/routing-providers.json`에 모델·역할·품질·예약선만 추가하면 코드 변경 없이 후보가 된다. `quality`는 실행 원장으로 계산된 실적값이 생기기 전까지 **초기 임시값**이며, Opus 5의 최초 값 97도 동일하다.

**작업 성격 그림자 점수 (2026-07-31 kyle 결정)**: `select-routing-pair.sh`에 반드시 `--task-class <분류>`를 넘긴다. 실제 stdout과 발령 모델은 기존 선택 결과를 그대로 유지하고, 자동 원장의 `payload.shadow`에만 `기존 점수 + 작업자 taskClassPrior + 검수자 taskClassPrior` 순위를 최대 10개 기록한다. `taskClassPrior`는 실적이 아니라 roster 관찰로 시작한 임시 가설이며 운영 선택에 사용하지 않는다. 같은 이벤트의 실제 선택과 그림자 선택을 비교해 표본을 모은 뒤에만 안전한 작업의 제한적 탐색으로 승격한다.

**모델·하네스 등록 계약 (2026-07-31 kyle 결정)**: 모델은 `provider + model id + role + effort + harness` 조합으로 식별한다. `routing-providers.json`의 모든 모델은 `harness`와 `taskClassPrior`를 명시한다. 현재 하네스 값은 `codex`, `claude-code`이며 이후 `kiro`, `gjc`, `lm-studio` 같은 연결기를 같은 필드에 추가한다. 새 값은 먼저 그림자 기록으로만 평가하고, 실행 명령·상태 확인·사용량 수집·중단 계약이 검증되기 전에는 실제 후보로 켜지 않는다. 로컬 모델은 자동 탐색하지 않으며 LM Studio 연결기를 명시적으로 등록한 경우만 후보가 된다.

**Luna 고강도 재편입 (2026-07-31 시작, 2026-08-03 max 후보 추가 kyle 결정)**: Datacurve DeepSWE v1.1 공식 리더보드의 `gpt-5.6-luna[max]`는 67%±4%, 평균 비용 $0.61, 출력 73k, 102 steps로 보고됐다. 이 외부 수치는 모델 선택의 출발 가설일 뿐 우리 하네스 실적은 아니므로, 자동 기본 편성은 `luna-xhigh` 품질 84의 임시값으로 유지한다. `luna-max` 개발자는 품질 86·10% 실험 슬롯·Anthropic 독립 검수 조건으로 등록하고, `luna-max` 검수자는 품질 96의 폴백 후보로 등록한다. 둘 다 `research`·`docs_config`·`qa` 가산점과 `security`·`concurrency` 감점을 두며, 실제 합격률·왕복·시간·사용량을 모은 뒤 품질값과 기본 선택 승격 여부를 다시 정한다. 출처: https://deepswe.datacurve.ai/

**Opus 작업자 실험 (2026-07-25 kyle 결정)**: 복잡한 카드에서 Terra 대비 성과를 측정하기 위해 Opus medium을 실험 작업자로 등록한다. `--experiment-key '[판]:카드명'`처럼 같은 카드에서 변하지 않는 키를 반드시 넣으며, SHA-256 기반 고정 버킷의 20%에서만 Opus 작업자 후보가 열린다. 같은 키는 재실행해도 같은 군에 속하므로 라우터 재조회가 실험 비율을 왜곡하지 않는다. Opus 실험군의 검수자는 OpenAI 계열로 제한해 현재는 `Opus medium → Sol medium`만 허용한다. 키가 없거나 실험 슬롯 밖이거나 Anthropic 예약선을 침범하면 Opus 작업자는 닫히고 기존 후보를 다시 점수화한다. `reasons`의 `experiment_bucket`, `experiment_share`와 기존 `.orca/routing-events/<판>.jsonl` 결과를 함께 기록해 첫 합격률·왕복·시간·사용량을 비교한다.

**사용량 원장 (2026-07-25)**: Rottie 하단 사용량 수집기가 Claude·Codex·Kimi·GLM 값을 `~/.cache/rottie/routing-usage.json`에 비밀 정보 없이 내보내며, 선택기는 20분 이내의 제공자별 최신값을 우선 사용한다. OpenCodex `/api/provider-quotas`는 Rottie가 꺼졌거나 특정 제공자 값이 없거나 오래된 경우에만 보조 입력으로 자동 합친다. 따라서 Opus 5는 Claude의 `모든 모델` 주간 값을 자동으로 공유하며 별도 화면 판독이 필요 없다. Fable 전용 한도가 소진되어도 Opus 자체가 살아 있고 `모든 모델` 잔여가 있으면 Anthropic 전체를 불능 처리하지 않는다.

**리셋 시각 연동 예약량·우선 사용 (2026-07-27 kyle 결정)**: 예약량을 고정해서 리셋 때 버리지 않는다. OpenAI 주간 잔여 20%는 Sol 검수 여유, Kimi 주간 잔여 10%는 GLM 장애 폴백 여유로 잡되, 주간 리셋 24시간 전부터 남은 시간에 비례해 0%까지 선형 해제한다. 예: 12시간 남으면 OpenAI 10%, Kimi 5%만 예약한다. 같은 24시간 구간에서는 리셋이 가까울수록 최대 `+15점`의 `weekly_reset_urgency` 가산점을 선형으로 부여한다(24시간 전 0점, 12시간 전 +7.5점, 직전 최대 +15점). 이는 임박한 할당량을 먼저 쓰게 하는 우선 신호일 뿐이며, 이미 소진됐거나 카드 예상량조차 남지 않은 provider를 되살리지 않는다. 5시간 창은 현재 카드 예상 사용량의 1.5배를 요구하되, 리셋 1시간 전부터 1.0배까지 선형 완화한다. 예: 30분 남으면 1.25배다. 선택 결과 `reasons`의 `weekly_reserve`, `weekly_reset_urgency`, `five_hour_headroom`으로 실제 적용값을 확인한다.

```bash
~/.claude/skills/orca-conductor/scripts/select-routing-pair.sh \
  --task-size heavy --task-class targeted_implementation --experiment-key '[판]:카드명'

# Rottie 값이 없을 때 OpenCodex를 보조 입력으로 함께 사용
curl -s http://127.0.0.1:10100/api/provider-quotas \
  | ~/.claude/skills/orca-conductor/scripts/select-routing-pair.sh \
      --quota-file - --task-size heavy --task-class security --unavailable-provider zai
```

선택 결과(`developer`, `reviewer`, `score`, `last_resort`, `same_family`, `reasons`, 상위 대안)는 래퍼가 라우팅 원장에 **자동 기록**하므로 수기로 옮겨 적지 않는다 (2026-07-27 자동화). `--unavailable-provider`는 같은 발령 시점에서 실측한 429·quota/limit 오류·반복 기동 실패에만 붙이고, 다음 발령에서는 다시 가용 여부를 확인한다.

**kimi/glm 균형 배분 (2026-07-22 kyle 결정 — kimi 소진 분산)**: kimi(opencodex kimi provider)·glm(zai provider)·sol(ChatGPT)이 **완전히 별개 쿼터**라, kimi에 몰빵하지 않고 나누면 kimi 소진이 크게 늦춰진다. 기본 배분 원칙:

- **배분 단위는 랠리** — 단일 랠리 안에서 라운드마다 kimi↔glm 교체는 금지(같은 편성 유지 원칙). **단 가용성 폴백(아래 폴백 규칙)·쿼터 계열 분리 전환(검수가 kimi로 넘어가면 dev→glm 즉시 전환, fable 과도기 1라운드 종료 후 dev→glm 전환)은 이 금지의 예외다 — 그 경우 기존 규칙이 우선한다.** 병렬 랠리는 kimi/glm에 나눠 배정하거나 판마다 교대.
- **작업 성격으로 배분**: **방향이 선명한 표적 구현·프론트·구조 변경은 `codex-glm52`** (rally-log 관찰: glm이 이 부류에 강함 — popover·xterm훅 1라운드 합격, TOCTOU는 high 승급 후 완결). 그렇게 몰면 kimi를 아끼면서 품질도 유지된다. **kimi는 그 외 + 1M 컨텍스트가 필요한 대규모 읽기·조사**에.
- **kimi 쿼터 실측 후 동적 라우팅 (pace 기준, 2026-07-22 개정 — 고정 임계값 폐기)**: 발령 전 `curl -s http://127.0.0.1:10100/api/provider-quotas`로 kimi의 `weeklyPercent`(쓴 비율)와 `weeklyResetAt`(리셋 시각, epoch ms)을 읽는다. **판정식: 주간 사용률% > 주간 경과율% 이면 과속 → 그 판은 glm 우선.** 경과율% = (1 − (weeklyResetAt − 현재시각ms) ÷ 604,800,000) × 100 (주간 창 7일). 사유: 고정 임계값(구 "주간 70%+")은 리셋까지 남은 시간을 무시한다 — 리셋 1시간 전 70%는 안전이고 리셋 5일 전 65%는 이미 위험인데 같은 판정이 나온다 (2026-07-22 실측: 사용 65% vs 경과 30% = 균등 페이스의 2.2배 과속으로 약 1.1일 뒤 소진 궤도였는데, 구 규칙은 "kimi 유지" 판정). 보조 기준: (1) 과속이 2배 이상이면 kimi 몫이던 대규모 읽기·조사까지 glm으로 넘긴다. (2) `fiveHourPercent`는 5시간마다 회복되니 참고만 — 80%+면 그 발령 1건만 glm으로 비끼고 페이스 판정에는 안 쓴다. glm(zai)은 이 조회 미지원이지만 **주간 한도 자체가 없다(5시간 한도만 존재 — kyle 플랜 특성, 2026-07-22 kyle 확인)**. 따라서 glm 배정은 희소 자원 소모가 아니므로 **판정이 경계선이면 glm 쪽으로 기운다.** glm 5시간 한도가 그 판에서 소진되면 가용성 폴백 규칙(아래)대로 처리하고, 5시간 회복 후 복귀.
- **미묘한 보안 완결·첫 설계 불확실 국면은 glm-medium 주의** (rally-log: glm-medium이 TOCTOU 3라운드 헤맴 → high 필요, kimi-low도 보안 Debug 누출 2라운드 놓침). 보안 카드는 effort 승급 또는 상위 검수 왕복을 미리 잡는다.

| 구분 | 엔진 |
|---|---|
| 잡일 (문서·문구·설정 등 틀릴 수 없는 것) | `codex-glm52-medium` |
| 표적 구현·프론트·구조 변경 | `codex-glm52` (glm 강점 + kimi 절약) |
| 대규모 읽기·조사·그 외 기본 | `codex-kimi1m` (단 kimi 과속 판정이면 glm으로 — 위 pace 기준 동적 라우팅) |
| 가용성 폴백 (쿼터 소진·불능 시) | 고정 순서 없음. 불능 provider를 제외하고 `select-routing-pair.sh`로 전체 조합 재점수화 |

**effort 라우팅 (2026-07-20 kyle v2 — dev는 빠르게 여러 번, 품질은 검수 관문이 잡는다)**. terra-max가 필요할 정도면 sol로 모델 승급이 낫다:

| 난이도 판단 | codex-kimi1m(effort) | codex-glm52(effort) | luna(codex effort) | terra(codex effort) |
|---|---|---|---|---|
| 전 난이도 공통 | **Low (통일)** | **medium (통일, 2026-07-21 kyle 결정)** | 중계 high / 안전한 구현 탐색 **xhigh** | 단순 medium / 보통·까다로움 **high** |

- **kimi·glm effort 설정법 (2026-07-21 개정 — codex CLI 이관)**: 이제 기동 시 `-c model_reasoning_effort` 플래그로 한 번에 정한다. 구 kimi CLI의 TUI 수동 `/effort` 설정·캐시 무효화 주의는 더 이상 해당 없음. kimi(k3[1m]) 지원 단계 = low·high·max, glm(5.2) 지원 단계 = low·medium·high·xhigh·max (2026-07-21 `ocx models` 카탈로그 실측 — 두 모델 모두 ultra 없음).
- **effort 상향 실험 (2026-08-04 kyle 결정 — "추론 좀 올려보려고")**: 기본 강도는 위 표 그대로 두고, 추론 강도를 올린 **실험 항목**을 `routing-providers.json`에 추가 등록했다. dev: `codex-glm52-max`·`codex-kimi1m-max` (각 20%, 검수는 openai·anthropic 계열만 허용). 검수: `codex-sol-high/xhigh/max` (각 20%, **medium 기준선 항목은 그대로 유지** — 원장의 effort 필드로 A/B 비교), `claude-fable-medium/high/xhigh` (각 10% — 지휘자와 Anthropic 쿼터를 공유해 보수적), `codex-glm52-max` 검수 (20%). 선택기의 실험 게이트는 developer뿐 아니라 **reviewer에도 적용**되며(2026-08-04 코드 반영), 실험 버킷은 `모델 id + effort` 단위로 독립이라 같은 모델의 단계별 실험이 서로 다른 카드에서 열린다. 예상 노출(sol 검수): max 20% / xhigh 16% / high 12.8% / medium 51.2%.
- terra는 sol 반값으로 확인돼 **정식 편입** (2026-07-20 kyle 결정). 단 codex CLI의 `gpt-5.6-terra` 직접 호출은 아직 기동 실측 전 — 첫 발령 때 결과를 테스트 대장에 기록하고, 즉사하면 `codex-sol-high`로 임시 폴백 후 kyle에게 보고한다.
- **kimi 잔여 낮음 + Codex 널널 → terra-high 우선 (2026-07-23 kyle 결정)**: 폴백·배분에서 kimi 차례인데 kimi 주간 잔여가 낮고(기준: 잔여 30% 이하) ChatGPT/Codex 주간이 널널하면(사용률 30% 미만, probe-codex.sh 또는 상태바로 확인) kimi를 아끼고 `codex-terra-high`를 우선 선택한다 — terra는 sol 반값이라 널널할 때 태우기 좋은 쿼터. sol(검수 전담) 쿼터와 같은 계열이므로 dev·검수 동시 대량 사용 시에는 소진 속도를 한 번 더 확인.
- **세션 내 모델 전환 폴백 (2026-07-23 kyle 등록, opencodex 기능 — 첫 사용 시 실측해 여기 갱신)**: opencodex 경유 codex 터미널은 **세션 안에서 모델 전환이 가능**하다. 가용성 폴백 시 기본값은 새 터미널 재발령이 아니라 **같은 터미널에서 모델만 바꿔 이어서 진행** — 턴 맥락·워크트리 파악·dispatch 컨텍스트(같은 handle이라 worker_done 유효)가 전부 보존되고, task-update ready → 재발령 절차도 불필요. 절차: 오류로 턴이 죽으면 → 모델 전환 → effort 단계 재확인 → "이어서 진행" 지시. **1차 실측 (2026-07-23, codex 0.145)**: `terminal send --text "/model gpt-5.6-terra"` + enter는 **전환 실패** — 상태바 불변, 텍스트가 프롬프트로 소비되어 죽은 모델로 턴 재시작. /model 인터랙티브 피커의 자동화 절차를 확보하기 전까지는 구 절차(새 터미널 재발령)가 기본. **2차 실측 (2026-07-23, 별도 지휘 세션)**: `/model`+enter로 인터랙티브 픽커는 정상 개방(카탈로그 전 모델 표시 — luna/sol/terra/kimi/k3[1m]/glm-5.2), 필터 입력·선택도 진행되나 **선택 확정 시 codex가 기본 모델을 설정에 저장하다 `-p orca-worker` 프로필의 mcp_servers enabled=false 항목이 검증에 걸려 실패**(config/batchWrite: invalid transport in mcp_servers.playwright) → **전환 통째 무산**(상태바 원래 모델 유지 실측). **3차 실측 — 해결·활성화 (2026-07-23 kyle 승인 테스트)**: 프로필 3종(orca-worker/analyst/lean)의 mcp_servers 항목에 transport를 명시해 해소 — stdio형(playwright·node_repl)은 `command = "true"` 더미, url형(context7·openaiDeveloperDocs)은 전역과 같은 `url` (주의: url형에 command를 주면 기동부터 거부 — "url is not supported for stdio"). 수정 후 본 프로필에서 `Model changed to kimi/k3` 실측, 저장 오류 0. **확정 전환 절차**: `/model`+enter → 픽커에서 **화살표 키로 선택**(필터 타이핑은 무효 — 실측) → enter(모델) → enter(effort) → 화면에 `Model changed to <모델>` 확인 → "이어서 진행" 지시. 이제 가용성 폴백의 기본값은 세션 내 전환이며, 전환 실패 확인 시에만 새 터미널 절차. 전환이 안 되는 경우(비 opencodex 터미널, 전환 미지원 확인)에만 구 절차(새 터미널 + 인수인계 보충 지시)로 간다.
- **가용성 폴백 (품질 승급과 별개, 2026-07-20 kyle 결정)**: 아래 사유면 그 단을 건너뛰고 다음 단으로 간다 — 품질 문제가 아니므로 승급 트리거 기록에는 안 세고, 복구되면 다음 랠리부터 원래 단으로 복귀한다.
  - kimi 할당량 소진 (opencodex 프록시의 kimi provider 오류, 또는 화면의 quota/limit 오류 문구). 잔여량 사전 확인(선택): `curl -s http://127.0.0.1:10100/api/provider-quotas` — `fiveHourPercent`/`weeklyPercent`는 **쓴 비율**(100 근접 = 소진), 2026-07-21 실측·소스 확인. zai(glm)는 이 조회 미지원
  - glm 할당량 소진 (opencodex 프록시의 zai provider 오류, 또는 화면의 quota/limit 오류 문구. 비상 gjc CLI로 전환 시 `gjc stats` 2분+ 무응답 = 불능 판정 포함)
  - API 호출 불가 — 서버 과부하·5xx·overloaded·타임아웃 반복 (2~3회 재시도 후에도 같은 오류면 폴백)
  - CLI 기동 즉사·세션 자연사 반복 (같은 터미널 2회 연속)
  - **opencodex 프록시 다운 — 이때만 폴백 목적지가 다르다 (2026-07-21 등록)**: `ocx status` → `ocx start`로도 미복구면 다음 단(codex-terra)으로 건너뛰지 않고 **비상 대안으로 대체**한다 — kimi 자리는 `kimi`(kimi CLI, TUI /effort 수동 설정 주의), glm 자리는 `gjc-glm-medium`. 사유: 프록시 다운은 kimi/zai 쿼터 문제가 아니므로 ChatGPT 쿼터(terra)를 태울 이유가 없다. 프록시 복구 확인 후 다음 발령부터 원 편성 복귀.

### 보안 코드 배정 예외 — sol(OpenAI) 회피 (2026-07-22 실사고 박제)

**보안 성격 코드도 sol을 1회 시도한다 — 차단되면 즉시 백엔드 교체 (2026-07-22 kyle: "될 수도 있잖아").** 대상: 권한·토큰·크리덴셜·해시·심볼릭 링크·TOCTOU·권한 상승·셸 자동화·익스플로잇/스캐너/패킷 분석·CTF/리버스/침투. OpenAI가 이런 요청을 "cybersecurity"로 분류해 **정당한 방어 코드도 차단할 때가 있다**("This content can't be shown... Trusted Access", 쿼터 무관 콘텐츠 필터, 오탐 잦지만 통과도 함). 정책: (1) sol 배정을 미리 피하지 않는다 — 통과하면 그대로 진행. (2) 차단 화면이 뜨면 **순화·재시도 금지**(검수 순화는 공격 시나리오 실측을 빼 검수를 무력화, 재시도는 콘텐츠 기반이라 재발) → 즉시 백엔드 교체(task-update ready → kimi/glm 재발령, 저자 분리 유지). kimi/glm 계열은 이 필터가 없다. 근거: incident-log 2026-07-22(카드4 7라운드 sol 차단 → kimi-high 재발령 합격).

### 검수 엔진 — 동적 선택, Sol·Opus 5 품질 기준

기본 품질 기준은 `codex-sol-medium`이며 검수 강도 medium 고정이다(LIGHT/HEAVY 공통 — 무게별 합격 기준·재검수 범위 규칙은 `tiki-taka.md`). `claude-opus5-medium`은 Anthropic 독립 계열의 고급 검수 후보로 함께 점수화한다. Sol과 Terra는 같은 OpenAI 계열이므로 Terra→Sol은 독립 검수보다 감점되지만 금지하지 않으며, Opus 5는 Kimi·GLM·OpenAI 작업물의 저자 계열을 분리할 때 우선 가치가 있다. 실제 편성은 선택기가 현재 쿼터와 작업자 계열을 함께 보고 정한다.

- **Fable 검수 정식 등록 (2026-08-04 kyle 결정)**: `claude-fable-medium/high/xhigh`가 `routing-providers.json`의 실험 검수자(각 10%)로 등록됐다. 평상시 Kimi/Sol 검수 순서는 고정하지 않고 선택기 점수로 정한다. 등록된 조합이 모두 불능일 때 사람이 `claude-fable-medium`을 최후 보루로 고르는 규칙은 그대로 유지한다.
- **독립 계열 우선, 같은 계열 허용**: 선택기는 작업자와 검수자 provider가 다르면 가산하고, 같으면 감점한다. 하지만 Terra→Sol처럼 같은 계열 조합을 금지하지 않는다. 모든 독립 계열 조합이 불능·예약선 침범이면 같은 계열 조합도 선택한다.
- **폴백 검수의 저자 분리 원칙 (2026-07-21 kyle 결정)**: 폴백 검수 모델은 **검수 대상 라운드의 구현 모델과 겹치지 않게** 고른다 — 대상이 kimi 작업물이면 검수는 `claude-fable-medium`, glm 작업물이면 `codex-kimi1m-high`. 사유: "검수가 kimi로 전환되는 그 라운드"는 직전 구현이 이미 kimi인 과도기라 자기 검수(맹점 겹침 최대)가 생기는데, 이 케이스는 드물어 fable 소모가 미미하므로 fable 아끼기 방침과 충돌 없이 분리를 산다.
- **fable 과도기는 정확히 1라운드 (2026-07-21 kyle 명시 — 실사고 기반)**: Fable 비상 검수는 "이미 만들어진 작업물"을 검수하는 그 한 라운드에만 쓴다. 다음 수정 라운드는 선택기를 다시 실행해 등록된 정상 조합으로 복귀한다. 맥락은 터미널 머리가 아니라 카드의 발견 전문에 있으므로 Fable 편성을 반복 유지하지 않는다.
- **쿼터는 상시 추적하지 않는다 — 발령 순간 판정 (2026-07-21 kyle 확인)**: 폴백 진입은 발령 시 한도 오류(429/limit 문구) 또는 codex 상태바 `weekly % left` 0 확인으로, 복귀는 폴백 상태에서 **다음 발령 때 원 편성 1회 재시도(probe)**로 정한다 — 되면 복귀, 안 되면 폴백 유지. 판 중간 억지 복귀 불필요(검수자는 라운드 경계에서 자연 복귀). 별도 감시 프로세스 없음 — 기존 "배분 전 사용량 확인"(안전 규칙 4)에 이 분기만 얹는 것이다.

### 조사 (읽기 전용, 검수 루프 없음 — 지휘자 대조로 종결)

조사 카드도 고정 폴백 순서를 쓰지 않는다. `select-routing-pair.sh` 결과의 developer를 조사자로 사용하되, 검수 카드가 없는 읽기 전용 조사이므로 reviewer 결과는 소비하지 않는다. effort는 등록값을 따른다. 조사 전용 모델을 추가하면 `routing-providers.json`에 역할을 확장하기 전까지 developer 후보로 등록한다.

외부 사례·표준을 찾는 선행 조사는 `research-flow.md` 계약을 추가 적용한다. 기본은 Terra-low 또는 Kimi-low이며, 큰 표준이나 여러 원본 저장소를 비교할 때만 high로 올린다. Luna는 최종 비교 판단자가 아니라 링크 수집 보조로만 쓴다.

## 미검증 엔진 테스트 대장 (kyle 실측 예정)

테스트 방법: 조사 카드 1장(읽기 전용)을 해당 엔진으로 발령해 기동/발령 수신/worker_done 보고까지 한 바퀴 확인.

| 엔진 | 확인할 것 | 상태 | 메모 |
|---|---|---|---|
| `codex-luna-xhigh` | 안전한 구현·조사 품질과 실제 비용 | 탐색 등록 | 가격 인하 뒤 신규 기본 작업자 후보. security·concurrency 제외 후 제한적 탐색 |
| `codex-glm52-high` | medium 대비 속도/품질 | 미측정 | 조사용 후보 (구 `gjc-glm5.2-high`에서 이관) |
| `codex-sol-max` | xhigh 대비 체감 차이 | 미측정·저우선 | 외부 조언: high↔xhigh 벤치 격차가 가격 격차보다 작음 |
| `codex-terra-max` | 기동(모델 ID 유효)·구현 품질 | **정식 편입** (2026-07-20 kyle — sol 반값). 기동 실측은 첫 발령 때 기록 | 구현 사다리 3단 |
| `codex-terra-medium` | 〃 | 미측정 | terra-max 시험 결과에 따라 |
| `codex-terra-high` | 〃 | 미측정 | 〃 |

당일 실측으로 이미 확정 (별도 테스트 불필요):

- `codex-luna-high` (조사): 원인 추적 1방 정답 — 합격 (2026-07-19)
- `codex-luna-max` (구현·검수): 작동은 하나 구현은 race 놓침 4라운드, 검수는 서브에이전트 폭주·정체 이력이 있다. **2026-08-03 kyle 결정으로 개발 10% 실험·검수 폴백 후보에 한정해 재등록**했으며, 기본 승격 전 새 실측이 필요하다.

## 구 프리셋 ID 대응표 (다른 문서·기억이 옛 ID를 참조할 때)

| 구 ID | 새 표기 |
|---|---|
| `dev-codex-luna-high` / `recon-codex-luna-high` | `codex-luna-high` |
| `dev-codex-luna-max` | `codex-luna-max` (비권장) |
| `dev-codex-sol-high` | `codex-sol-high` |
| `dev-codex-sol-xhigh` / `review-codex-sol-xhigh` | `codex-sol-xhigh` |
| `dev-gjc-glm5.2-ultra` | `codex-glm52-max` (glm 카탈로그 최고 강도가 max — ultra 없음, 2026-07-21 실측. 구 `gjc-glm5.2-ultra`은 비상 대안) |
| `dev-gjc-sol-ultra` / `review-gjc-sol-ultra`(가재) / `review-gjc-sol-high` / `recon-gjc-sol` | `gjc-codexpro` |
| `dev-claude-fable-medium` | `claude-fable-medium` |
| `review-claude-fable-high` | `claude-fable-high` |
| `dev-kimi` | `codex-kimi1m-low` (구 `kimi` CLI은 비상 대안) |
