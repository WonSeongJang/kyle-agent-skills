# 디자인 스킬 실사용 평가 기록

## Why

design-conductor가 스킬 소개 문구가 아니라 같은 과제의 실제 결과를 보고 제작자·전문 보조·검수자를 고르게 한다.

## 2026-08-12 공통 과제

공통 입력과 화면 크기는 `.staging/design-eval/README.md`에 고정했다. 제작형은 Rottie 랜딩 히어로, Terminal 관제 카드, 스킬 주특기 산출물을 만들었다. 검수형은 같은 대상을 감사했다. HTML 21개를 1440x900과 390x844에서 캡처했고, Chrome CDP 검사 42회에서 가로 넘침 0건, reduced-motion 누락 0건이었다.

| 스킬 | 과제 | 산출물 품질(1-5) | 지시 준수(1-5) | 걸린 느낌 | 이럴 때 쓰라 | 이럴 땐 쓰지 마라 |
|---|---|---:|---:|---|---|---|
| Effective HTML 6종 | 랜딩 히어로 | 4 | 5 | 빠름. 외부 의존 없는 단일 HTML이 바로 열림 | 설명형 제품 히어로를 한 파일로 빨리 비교할 때 | 앱 코드에 바로 넣을 완성 컴포넌트가 필요할 때 |
| Effective HTML 6종 | 다크 관제 카드 | 4 | 5 | 토큰·정보 위계 보존이 안정적 | 독립 검토 가능한 HTML 모형이 필요할 때 | 실제 데이터 연결까지 기대할 때 |
| Effective HTML 6종 | 라우터+아티팩트+와이어프레임+프로토타입+계획+다이어그램 | 5 | 5 | 여섯 역할이 서로 덜 섞여 요구가 복합일수록 편함 | 무엇을 만들지부터 애매한 HTML 기획·설명 작업 | React 구현 하나만 분명한 작은 수정 |
| Taste Skill | 랜딩 히어로 | 5 | 5 | 가장 강한 개성. 흔한 SaaS 느낌을 빠르게 벗어남 | 개성 없는 첫 화면을 새 방향으로 밀 때 | 기존 디자인 시스템을 엄격히 보존해야 할 때 |
| Taste Skill | 다크 관제 카드 | 4 | 4 | 강한 세로 rail이 기억에 남지만 관제보다 스타일이 앞섬 | 브랜드성이 필요한 마케팅형 대시보드 | 촘촘한 운영 도구, 장시간 쓰는 관리 화면 |
| Taste Skill | 편집형 개발자 포트폴리오 | 5 | 5 | 비대칭·색·타이포가 실제로 anti-slop 효과를 냄 | 랜딩·포트폴리오·브랜드 콘셉트 발산 | 보수적인 엔터프라이즈 화면 |
| Emil Design Eng | 랜딩 히어로 | 4 | 5 | 정적인 모양보다 hover/press가 자연스러움 | 이미 구조가 있는 UI의 마지막 10%를 다듬을 때 | 정보 구조를 처음부터 정해야 할 때 |
| Emil Design Eng | 다크 관제 카드 | 4 | 5 | 차분하고 사용성이 좋지만 시각 방향은 보수적 | 카드·버튼·토스트의 상태 피드백 개선 | 포스터나 강한 브랜드 비주얼 |
| Emil Design Eng | 상호작용 상태 연결 | 5 | 5 | rest→hover→press→complete가 가장 명확 | 마이크로 인터랙션, 모션 QA, tactile UI | 정적 문서·인쇄물 |
| Apple Design | 랜딩 히어로 | 4 | 5 | spring과 재질감이 매끄럽지만 밝은 유리 질감은 Rottie와 거리 있음 | 고급 소비자 앱, 제스처 중심 인터페이스 | 데이터 밀도 높은 관제·터미널 UI |
| Apple Design | 다크 관제 카드 | 3 | 4 | 읽히지만 glass·큰 radius가 Terminal 원형을 약하게 만듦 | 공간감 있는 상태 카드 | 원본 토큰 보존이 중요한 운영 카드 |
| Apple Design | 중단 가능한 bottom sheet | 5 | 5 | 열리는 중에도 반전되고 키보드·reduced-motion이 작동 | drag/spring/gesture 기반 웹 상호작용 | 정적 랜딩 한 장 |
| Extract Design System | 랜딩 히어로 | 4 | 5 | 창의성보다 원본 DNA 재사용이 확실 | 기존 사이트·제품의 시각 언어로 새 화면을 만들 때 | 새 브랜드 방향을 발산해야 할 때 |
| Extract Design System | 다크 관제 카드 | 5 | 5 | Terminal 토큰과 상태 의미 보존이 최고 | 리디자인 전에 기존 시스템을 문서화할 때 | 원본이 엉성해 과감히 버려야 할 때 |
| Extract Design System | Terminal 테마 Markdown+JSON 추출 | 5 | 5 | 사람이 읽는 규칙과 기계 토큰이 함께 남아 재사용 쉬움 | URL/코드 기반 디자인 시스템 추출·인수인계 | 결과 이미지 한 장만 급할 때 |
| Canvas Design | 랜딩 히어로 비교용 HTML | 3 | 3 | HTML은 주특기가 아니며 포스터 철학을 억지로 옮긴 느낌 | 정적 방향을 웹에 느슨하게 참고할 때 | 실제 인터랙티브 UI 제작 |
| Canvas Design | 다크 관제 카드 비교용 HTML | 3 | 3 | 상태 정보는 보존했지만 장점이 드러나지 않음 | 정적 구성 썸네일 | 운영 화면 컴포넌트 |
| Canvas Design | Rottie A3 포스터 SVG/PNG/PDF | 5 | 5 | 철학→편집 SVG→PNG/PDF가 명확하고 결과가 강함 | 포스터, 키비주얼, 행사 그래픽, 인쇄물 | 폼·탭·복잡한 앱 흐름 |
| Frontend Design | 랜딩 히어로 | 5 | 5 | 제품 특유 아티팩트와 강한 방향이 균형. 최초 모바일 넘침을 검수에서 찾아 844px 한 화면으로 수정 | 새 웹 UI를 완성도 높게 처음 만들 때 | 기존 시스템의 작은 버그 수정 |
| Frontend Design | 다크 관제 카드 | 4 | 5 | 편집적 개성은 강하지만 초록 banner가 상태보다 먼저 읽힘 | 브랜드가 보이는 웹 대시보드 | 가장 빠른 관제 판독이 목표일 때 |
| Frontend Design | 명령 지도 | 5 | 5 | 주제 맞춤 구성이 가장 좋고 generic 카드 느낌이 적음 | 랜딩·웹 경험의 주 제작자 | 모션 물리나 인쇄 그래픽 전문 작업 |
| Web Design Reviewer | 랜딩 히어로 감사 | 5 | 5 | 모바일 첫 화면과 폰트 재현성까지 구체적으로 잡음 | 구현 후 시각·반응형·접근성 종합 검수 | 첫 콘셉트 발산 |
| Web Design Reviewer | 다크 관제 카드 감사 | 5 | 5 | 스타일보다 정보 우선순위 문제를 정확히 찾음 | PR 전 독립 검수, severity가 필요한 보고 | 한 줄짜리 CSS 수정 |
| Web Design Reviewer | 7축 전체 검수 | 5 | 5 | pass/fail보다 조건과 수정 순서가 남음 | 주 제작자 뒤의 필수 검수자 | 스스로 디자인을 만들어야 할 때 |
| Anti UI Slop | 랜딩 히어로 감사 | 3 | 3 | 흔한 냄새는 찾지만 외부 UIZZE 차단 시 고유 가치가 작음 | 인터넷 허용 상태의 리디자인 전 레퍼런스 선택 | 오프라인·비공개 앱·빠른 코드 검수 |
| Anti UI Slop | 다크 관제 카드 감사 | 3 | 3 | 장르가 정보를 덮는 문제는 찾았으나 기존 검수와 중복 | 템플릿 냄새만 빠르게 점검 | 접근성·반응형까지 종합 검수 |
| Anti UI Slop | UIZZE 없는 의존성 실측 | 2 | 4 | 핵심 카탈로그를 못 열면 독립 편성 이유가 약함 | 외부 사이트 탐색이 명시 허용된 조사 | 네트워크 금지·민감 프로젝트 |
| Slides Grab 7종 | 랜딩 히어로 단일 슬라이드 | 4 | 4 | 메시지 하나로 줄이는 힘은 좋고 웹 반응성은 보조적 | 발표용 한 장 요약 | 실제 랜딩 페이지 구현 |
| Slides Grab 7종 | 관제 카드 단일 슬라이드 | 4 | 4 | 발표 판독성은 좋지만 촘촘한 실사용 UI는 아님 | 상태 보고 슬라이드 | 클릭 가능한 운영 카드 |
| Slides Grab 7종 | 3장 출시 덱+PNG+PDF | 5 | 5 | 개요→HTML→검수→개별 PNG/PDF 흐름이 완결 | 소스가 남는 발표자료·짧은 피치덱 | 한 장 포스터나 앱 컴포넌트 |

### 점수 근거 파일

각 점수는 아래 실제 파일과 같은 디렉터리의 `desktop.png`, `mobile.png`를 열어 판정했다.

| 스킬 | 랜딩/감사 근거 | 관제 카드/감사 근거 | 주특기 근거 |
|---|---|---|---|
| Effective HTML 6종 | `.staging/design-eval/effective-html/hero/index.html` | `.staging/design-eval/effective-html/dashboard-card/index.html` | `.staging/design-eval/effective-html/specialty/index.html` |
| Taste Skill | `.staging/design-eval/taste-skill/hero/index.html` | `.staging/design-eval/taste-skill/dashboard-card/index.html` | `.staging/design-eval/taste-skill/specialty/index.html` |
| Emil Design Eng | `.staging/design-eval/emil-design-eng/hero/index.html` | `.staging/design-eval/emil-design-eng/dashboard-card/index.html` | `.staging/design-eval/emil-design-eng/specialty/index.html` |
| Apple Design | `.staging/design-eval/apple-design/hero/index.html` | `.staging/design-eval/apple-design/dashboard-card/index.html` | `.staging/design-eval/apple-design/specialty/index.html` |
| Extract Design System | `.staging/design-eval/extract-design-system/hero/index.html` | `.staging/design-eval/extract-design-system/dashboard-card/index.html` | `.staging/design-eval/extract-design-system/specialty/design-system.md`, `design-system.json` |
| Canvas Design | `.staging/design-eval/canvas-design/hero/index.html` | `.staging/design-eval/canvas-design/dashboard-card/index.html` | `.staging/design-eval/canvas-design/specialty/poster.svg`, `poster.png`, `poster.pdf` |
| Frontend Design | `.staging/design-eval/frontend-design/hero/index.html` | `.staging/design-eval/frontend-design/dashboard-card/index.html` | `.staging/design-eval/frontend-design/specialty/index.html` |
| Web Design Reviewer | `.staging/design-eval/web-design-reviewer/hero/audit.md` | `.staging/design-eval/web-design-reviewer/dashboard-card/audit.md` | `.staging/design-eval/web-design-reviewer/specialty/full-review.md` |
| Anti UI Slop | `.staging/design-eval/anti-ui-slop/hero/audit.md` | `.staging/design-eval/anti-ui-slop/dashboard-card/audit.md` | `.staging/design-eval/anti-ui-slop/specialty/dependency-record.md` |
| Slides Grab 7종 | `.staging/design-eval/slides-grab/hero/index.html` | `.staging/design-eval/slides-grab/dashboard-card/index.html` | `.staging/design-eval/slides-grab/specialty/slides.html`, `slide-01.png`~`slide-03.png`, `deck.pdf` |

## 보류

| 스킬 | 판정 | 근거 |
|---|---|---|
| Impeccable | 설치·실사용 보류 | `registry/design-skill-safety-review-2026-08-12.md`에 기록. 기본 경로에 외부 업데이트 조회, 선택 결과 텔레메트리 POST, 홈 폴더 캐시 쓰기, 프로젝트 편집 훅과 재귀 임시 정리가 함께 있어 전역 설치 전에 비전송 기본값 결정이 필요하다. |

## 중복쌍 승자

| 중복쌍 | 승자 | 같은 과제에서의 근거 |
|---|---|---|
| `frontend-design` vs 기존 `frontend-skill` | `frontend-design`을 주 제작자로, 기존 `frontend-skill`을 성능·접근성 보조로 분리 | 신규 히어로·명령 지도의 주제 맞춤 구성은 강했다. 기존 frontend-skill은 Lighthouse·WCAG·브라우저 QA까지 넓지만 제작 미감 한 가지로는 덜 집중적이다. |
| `frontend-design` vs 기존 `hallmark` | 새 웹 화면은 `frontend-design`, URL 연구·다문서 디자인 시스템은 `hallmark` | 같은 Terminal 공통 과제에서 frontend-design은 바로 강한 HTML을 냈다. Hallmark는 100개 넘는 레퍼런스로 연구·추출 범위가 더 넓지만 작은 제작에는 무겁다. |
| `taste-skill` vs 기존 `hallmark` | 빠른 anti-slop 발산은 `taste-skill`, 근거 있는 장르 연구는 `hallmark` | taste-skill 히어로·포트폴리오는 가장 즉시 개성이 났다. Hallmark는 URL/스크린샷 기반 연구와 DESIGN.md 전달이 필요할 때 우세하다. |
| `web-design-reviewer` vs 기존 `visual-qa` | 코드·디자인 finding은 `web-design-reviewer`, 실제 캡처·픽셀·CJK 판정은 `visual-qa` | reviewer는 우선순위와 수정안을 더 잘 썼고, visual-qa는 도구 실행과 시각 증거 수집이 더 강하다. 경쟁보다 직렬 편성이 맞다. |
| `anti-ui-slop` vs 기존 `hallmark`/`web-design-reviewer` | 기존 조합 승 | UIZZE가 막히자 신규 스킬 점수가 2~3점으로 내려갔고 나머지 체크가 기존 스킬과 겹쳤다. |
| `extract-design-system` vs 기존 `hallmark study` | 좁고 빠른 추출은 `extract-design-system`, 재설계까지 가면 `hallmark` | Terminal Markdown+JSON 추출은 짧고 재사용 가능했다. Hallmark는 브랜드 연구와 구현 방향까지 더 넓다. |
| `canvas-design` vs 기존 `md-visual-workflow` | 단일 아트워크는 `canvas-design`, 설명 문서·다이어그램 묶음은 `md-visual-workflow` | 포스터 PNG/PDF 품질은 canvas-design이 우세. 여러 산출 형식의 설명 자료는 md-visual-workflow가 우세하다. |
| `slides-grab` vs 기존 `md-visual-workflow` | 실제 발표 덱 내보내기는 `slides-grab`, 문서 중심 시각화는 `md-visual-workflow` | 3장 덱의 개별 PNG와 PDF까지 한 흐름으로 남겼다. |
| `emil-design-eng` vs `apple-design` | 일반 UI polish는 `emil-design-eng`, gesture/spring 특수 작업은 `apple-design` | Emil 카드가 Terminal 문맥을 더 잘 보존했고 Apple은 중단 가능한 bottom sheet에서만 확실히 앞섰다. |

### 직접 비교에 쓴 기존 산출물

- Hallmark: `skills/orca-conductor/scripts/board-dashboard.py`와 같은 Terminal 테마 실전 커밋 `da8390964a9730a0733b5087656dadb091cd6bfc`. 신규 관제 카드 8개가 이 토큰과 같은 내용으로 만들어져 직접 비교했다.
- 기존 `frontend-skill`: 신규 `frontend-design` 산출물 3개를 기존 frontend-skill의 브라우저·접근성·반응형 게이트로 검사했다. 제작 미감은 신규가 이겼지만 42회 실측·캡처는 기존 스킬이 맡아 역할을 분리했다.
- 기존 `visual-qa`: 신규 HTML 21개를 2개 화면 크기로 42회 캡처하고 Chrome CDP로 가로 넘침·reduced-motion을 전수 검사했다. `web-design-reviewer`의 문서 finding과 같은 대상에서 비교했다.
