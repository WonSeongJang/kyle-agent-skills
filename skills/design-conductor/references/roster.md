# 디자인 스킬 로스터

매번 현재 환경에서 실제 존재 여부를 확인한다. `외부 선정`은 로스터에는 들어왔지만 설치되었다는 뜻이 아니다.

## 주 제작자

| 스킬 | 상태 | 역할 | 선택 조건 |
|---|---|---|---|
| `frontend-skill` | 로컬, Codex | 시각 방향이 강한 웹 UI 제작 | 새 랜딩, 앱 화면, 프로토타입 |
| `omo:frontend` | 플러그인 의존 | 현재 Codex 환경의 UI 작업 흐름 | 노출된 환경에서 도구 어댑터로 사용 |
| `figma-implement-design` | 로컬, Codex | Figma 원본을 코드로 구현 | Figma URL 또는 node ID가 있고 1:1 일치가 목표일 때 |
| `imagegen` | Codex 내장 | 이미지 생성과 편집 | 일반 이미지 요청의 기본값 |
| `excalidraw-diagram` | 로컬, Codex | 흐름과 구조 다이어그램 | 구조, 과정, 개념 관계를 보여줄 때 |
| `md-visual-workflow` | 로컬, Claude | Markdown 기반 시각 문서 제작 | 서비스 설명, 가이드, 구조 문서 |

## 전문 보조

| 스킬 | 상태 | 역할 | 선택 조건 |
|---|---|---|---|
| `figma` | 로컬, Codex | Figma 문맥, 변수, 에셋 수집 | Figma 원본을 읽어야 할 때 |
| `frontend-foundation-playbook` | 로컬, Claude | 모달, 포털, z-index, 스크롤 잠금 같은 공통 기반 문제 | 화면 하나가 아니라 공통 UI 구조 문제일 때 |
| `admin-dashboard-playbook` | 로컬, Claude | 관리자 화면의 필요성과 구조 결정 | 내부 관리자 화면 작업일 때 |
| `gongnyang-prompt-kit` | 외부 선정, 미설치 | 거친 요청을 생산용 이미지 프롬프트로 편집 | 포스터, 화보, 키아트, 만화 프롬프트 |
| `nanobanana2-image-gen` | 로컬, Claude | Gemini 계열 이미지 생성 | [kyle]가 나노바나나, Gemini, Ultra를 명시했을 때만 |

## 조사자와 참고 자료

| 이름 | 상태 | 역할 | 규칙 |
|---|---|---|---|
| [Lazyweb](https://github.com/aboul3ata/lazyweb-skill) | 외부 선정, 미설치 | 실제 제품 스크린샷과 디자인 조사 | hosted MCP와 요금제 제한을 확인하고 필요할 때만 사용 |
| [StyleGallery](https://github.com/changeroa/StyleGallery) | 외부 선정, 참고 전용 | 레이아웃, 모션, 품질 패턴 자료 | 실행 스킬처럼 호출하지 말고 개념만 참고 |
| [Anthropic frontend-design](https://github.com/anthropics/skills/tree/main/skills/frontend-design) | 상류 참고 | 고유한 시각 방향과 자기 비평 | 로컬 `frontend-skill`과 동시에 주 제작자로 사용하지 않음 |
| [ihlamury/design-skills](https://github.com/ihlamury/design-skills) | 선택형 참고 | 회사별 디자인 제약 | 명시한 회사 스타일 하나만 읽음 |

## 슬라이드 제작자

| 이름 | 상태 | 역할 | 선택 조건 |
|---|---|---|---|
| [slides-grab](https://github.com/NomaDamas/slides-grab) | 외부 선정, 미설치 | 편집, 검증, PDF/PNG/PPTX 출력 중심 | 납품과 검증이 중요할 때 |
| [frontend-slides](https://github.com/zarazhangrui/frontend-slides) | 외부 선정, 미설치 | 의존성 없는 단일 HTML 발표 | 빠른 웹 공유와 쉬운 수정이 중요할 때 |

둘을 동시에 주 제작자로 사용하지 않는다.

## UI 품질 시스템

| 이름 | 상태 | 역할 | 선택 조건 |
|---|---|---|---|
| [ui-craft](https://github.com/educlopez/ui-craft) | 외부 선정, 시험 전용 | 제작, 비평, 토큰, 접근성, 품질 게이트 | 실제 화면 하나에서 읽기 전용 분석부터 시험 |
| `web-design-guidelines` | 로컬, Claude와 Codex | 접근성, UX, 성능 코드 검수 | 웹 UI 정적 검수의 기본값 |
| `playwright` | 로컬, Codex | 실제 브라우저 흐름과 스크린샷 | 실행 가능한 웹 UI 검수 |
| `omo:visual-qa` | 플러그인 의존 | 실제 화면 반복 검수 | 현재 환경에 노출될 때 |
| `browser` / `aside-browser` | 로컬 | 로그인된 브라우저 문맥 확인 | 일반 브라우저 자동화로 접근하기 어려울 때 |

## 로스터 편입 원칙

- 역할이 기존 스킬과 겹치면 기본값이 아니라 대안 또는 시험 전용으로 둔다.
- 설치되지 않은 항목은 자동 호출하지 말고 폴백을 사용한다.
- 외부 항목을 실제 설치하려면 설치 범위, 라이선스, 제거 방법, 설정 변경을 다시 확인한다.
