---
name: rottie-gui-qa
description: Rottie(Tauri 데스크톱 앱) GUI를 CLI로 자동 QA한다. tauri-dev-screen-cli + tauri-plugin-mcp-bridge(dev 전용)로 dev 앱의 화면을 스크린샷·DOM 스냅샷·JS 실행·클릭/입력으로 검증. 팝오버·패널·리사이즈·렌더 정합과 xterm 완성 문자열 입력은 자동 실측하고, 종료 팝업·한글 IME 조합 과정은 육안으로 확인한다. kyle이 "로티 QA", "GUI QA", "화면 검증", "/rottie-gui-qa"라고 할 때 사용.
metadata:
  type: reference
---

# Rottie GUI 자동 QA (tauri-dev-screen)

## Why

Rottie는 Tauri 데스크톱 앱이라 프론트 단위 테스트(vitest)·Rust 테스트로는 **실제 창 안에서 렌더·상호작용이 맞는지** 못 잡는다. 브랜치를 master 머지하기 전 "실기동 QA"가 늘 사람 몫이었는데, `tauri-dev-screen-cli`(johunsang) + `tauri-plugin-mcp-bridge`(hypothesi, crates.io 정식·18만 다운로드)로 **화면 안을 CLI로 직접 검증**한다. 2026-07-22 데몬 2차 통합본 QA에서 실측 정립.

## 전제 — dev 빌드에 브리지 플러그인이 있어야 함

WebSocket(127.0.0.1:9223)을 여는 플러그인이 **dev 빌드에 통합**돼 있어야 CLI가 붙는다. 없으면 아래를 dev 전용으로 추가(release 제외):

Rottie `master`에는 2026-07-22부터 브리지와 `window.__rottieQA` 터미널 입력 훅이 반영돼 있다. 보통은 별도 QA 브랜치를 만들지 않고 현재 `master` 기반 `npm run tauri:dev`에 바로 연결하면 된다. 아래 코드는 다른 브랜치나 오래된 체크아웃에서 브리지가 없을 때만 참고한다.

```toml
# src-tauri/Cargo.toml
[dependencies]
tauri-plugin-mcp-bridge = "0.12"
```

```rust
// src-tauri/src/lib.rs — tauri::Builder 체인
let builder = tauri::Builder::default()
    .manage(AppState::default())
    .plugin(tauri_plugin_clipboard_manager::init())
    .plugin(tauri_plugin_dialog::init());

#[cfg(debug_assertions)]  // dev 빌드에만. release엔 안 들어간다.
let builder = builder.plugin(
    tauri_plugin_mcp_bridge::Builder::new()
        .bind_address("127.0.0.1")  // 기본 0.0.0.0 → 로컬만 허용
        .build(),
);

let app = builder.setup(|app| { /* ... */ });
```

- **격리 원칙**: 현재 `master`는 플러그인 등록을 `#[cfg(debug_assertions)]`로 제한하고 `127.0.0.1`에만 바인딩한다. release 앱에는 브리지가 열리지 않아야 하며, 이 제한을 약화하거나 외부 주소에 노출하면 안 된다.

## 셋업

```bash
# 1) CLI 설치 (1회)
npm install -g github:johunsang/tauri-dev-screen-cli   # → `tauri-dev-screen` 명령

# 2) dev 앱 실행 (플러그인 포함 브랜치에서)
cd <워크트리>
npm run tauri:dev > /tmp/rottie-tauri-dev.log 2>&1 &   # Rottie Dev, com.wonseongjang.rottie.dev

# 3) 9223 열림 대기 (dev 빌드 컴파일+창 기동, 시한 5분 — mechanics 부팅 대기 규칙)
until nc -z 127.0.0.1 9223 2>/dev/null || [ $SECONDS -ge 300 ]; do sleep 5; done

# 4) 연결 확인
export TAURI_DEV_HOST=127.0.0.1 TAURI_DEV_PORT=9223
tauri-dev-screen status   # {"ok":true, "app":{"identifier":"com.wonseongjang.rottie.dev"...}}
```

## 명령

| 명령 | 용도 |
|---|---|
| `tauri-dev-screen status` | 연결·앱 identifier 확인 |
| `screenshot --file X.png` | PNG 캡처 → **Read 도구로 화면을 직접 본다** |
| `snapshot --file X.txt` | AI가 읽는 DOM 텍스트 스냅샷 |
| `js --code "..."` | WebView에서 JS 실행(마지막 표현식 반환). DOM 조회·요소 클릭·상태 확인 |
| `click --selector "..."` | CSS 선택자 클릭 |
| `type --selector "..." --text "..."` | 입력 요소에 텍스트 |
| `key --key Enter` | 키 이벤트 |
| `resize --width W --height H` | 창 크기 → 반응형 레이아웃 정합 확인 |

## 외부 키보드 입력 안전 계약 (2026-07-24 실사고)

`tauri-dev-screen`의 `click`·`type`·`key`와 dev 전용 JS 훅을 우선한다. 파일 선택기처럼 macOS `System Events` 키 입력이 불가피할 때는 아래 계약을 전부 지킨다.

1. QA 시작 시 대상 앱의 정확한 process name과 PID를 기록한다.
2. 키 입력 직전에 같은 PID가 살아 있고 process name이 일치하며 그 프로세스가 `frontmost=true`인지 다시 확인한다.
3. 세 조건 중 하나라도 다르면 키를 보내지 않고 QA를 실패로 종료한다. 앱을 다시 활성화했더라도 입력 직전 재검증을 생략하지 않는다.
4. `first process whose frontmost is true`, `frontmost application`, 이름 없는 `System Events` 대상처럼 현재 맨 앞 앱에 보내는 fallback은 금지한다.
5. 대상이 Rottie QA 앱인지 Codex·Orca·터미널·브라우저 등 사용자의 다른 앱인지 구분할 수 없으면 중단한다.
6. 경로·명령·비밀값을 클립보드나 키보드로 보내기 전에도 같은 검증을 반복한다.

금지 예시:

```applescript
tell application "System Events" to tell (first process whose frontmost is true) to keystroke qaPath
```

허용 예시는 process name만 믿지 않고 시작 때 기록한 PID까지 대조한 뒤, 불일치 시 입력 없이 실패하는 좁은 스크립트다. QA 도중 다른 앱이 앞으로 올라오는 것은 정상적인 사용자 행동이므로, 자동화가 포커스를 추측해서는 안 된다.

## 검증 레시피 (실측)

- **렌더 정합**: `screenshot` → Read로 육안. 겹침·잘림·빈 패널 확인. `resize`로 좁은 폭(900px 등) 정합도.
- **팝오버가 안 닫히는지** (popover-fix류): 팝오버 열고 → xterm 스크롤 강제 발생 → 여전히 열렸는지.
  ```bash
  tauri-dev-screen click --selector "[aria-label='리소스 관리자 열기']"
  tauri-dev-screen js --code "const vp=document.querySelector('.xterm-viewport'); vp.scrollTop=vp.scrollHeight-100; vp.dispatchEvent(new Event('scroll',{bubbles:false})); return {popoverStillOpen: !!document.querySelector('[class*=resource-manager]')}"
  ```
- **패널/탭 전환**: `js`로 텍스트 매칭 클릭 — `[...document.querySelectorAll('button,[role=tab]')].find(b=>/작업/.test(b.textContent)).click()`.
- **버튼 label 파악**: `js --code "[...document.querySelectorAll('button[aria-label]')].map(b=>b.getAttribute('aria-label'))"`.
- **상태바 메시지 소스**: `.status-bar__status` 텍스트로 오류/알림 문구 확인.
- **사용량 표시**: 상단 사용량 버튼 aria-label에 `Claude 5시간 %/주간 % · Codex 주간 % · Kimi/GLM ...` 실수치.

## xterm 터미널 입력 — `window.__rottieQA` 훅으로 해결 (2026-07-22 실증)

xterm은 canvas 렌더 + 숨은 `.xterm-helper-textarea`가 입력받는데, xterm core는 **브라우저 신뢰 이벤트(isTrusted)만** 받아 CLI/JS 시뮬레이션(`type`·`dispatchEvent`)을 무시한다. **해결**: dev 전용 훅 `window.__rottieQA`가 xterm을 우회해 백엔드 write_terminal 경로로 직접 주입한다(TerminalPanel의 `import.meta.env.DEV` 게이트, release 정적 제거). 이 훅이 있는 dev 빌드에서:

```bash
tauri-dev-screen js --code "JSON.stringify(window.__rottieQA.sessions())"   # {ids:[...], active:"..."}
tauri-dev-screen js --code "window.__rottieQA.write('echo hi\n')"           # 활성 세션에 명령 주입·실행
tauri-dev-screen js --code "window.__rottieQA.write(sessionId, 'ls\n')"     # 특정 세션에
```

실증(2026-07-22): `write('echo QA_HOOK_WORKS\n')` → 터미널에 명령 입력·실행·출력까지 확인. **한글 IME 조합**은 이 write가 완성 문자열을 보내는 것이라 조합 과정(preedit) 자체는 재현 못 하므로, IME 조합 버그는 여전히 육안. 완성 텍스트 입력·명령 실행·붙여넣기류는 훅으로 자동화된다. (훅이 없는 브랜치/빌드면 이 절 불가 — `window.__rottieQA`가 undefined.)

## 한계 — 육안 필수 (자동 불가)

- **한글 IME 조합**(preedit·조합 중 백스페이스): write는 완성 문자열만 보냄 → 조합 과정 버그는 육안.
- **종료 팝업**: 트리거하려면 창 close를 걸어야 하는데 selector가 어긋나면 **dev 앱이 닫힌다** → 육안 권장.
- **TUI 마우스**: 육안.

## 정리

- QA 끝나면 dev 앱 종료(`npm run tauri:dev` 백그라운드 PID kill 또는 창 닫기), 스크린샷 임시파일은 staging/삭제 원칙(kyle 안전수칙).
- QA 브랜치의 dev-screen 플러그인은 QA 전용이라 **프로덕션 머지에 섞지 않는다**.
