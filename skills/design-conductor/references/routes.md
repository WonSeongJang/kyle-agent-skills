# 작업별 라우팅

## 빠른 선택표

| 상황 | 자료 조사 | 주 제작 | 전문 보조 | 검수 |
|---|---|---|---|---|
| 새 랜딩 페이지 | 필요하면 Lazyweb | `frontend-skill` | 없음 | `web-design-guidelines` + 실제 화면 |
| 기존 UI가 AI처럼 보임 | 실제 화면 먼저 | `frontend-skill` 또는 `ui-craft` 시험 중 하나 | 없음 | 변경 전후 스크린샷 |
| Figma와 똑같이 구현 | 없음 | `figma-implement-design` | `figma` | Figma와 실제 화면 비교 |
| 납품용 슬라이드 | 필요하면 일반 조사 | `slides-grab` | 필요하면 `imagegen` | validate + PDF/PNG 직접 확인 |
| 가벼운 웹 발표 | 없음 | `frontend-slides` | 없음 | 여러 화면 크기에서 확인 |
| 포스터·키아트 | 참고 이미지 | `imagegen` | `gongnyang-prompt-kit` | 결과 이미지 직접 확인 |
| 구조·흐름 설명 | 없음 | `excalidraw-diagram` | 복잡한 문서면 `md-visual-workflow` | 글자 겹침과 읽는 순서 |
| 디자인 감사만 | 필요하면 Lazyweb | 제작자 없음 | 없음 | `web-design-guidelines` + 실제 화면 |
| 모달·포털·z-index 문제 | 없음 | 기존 프로젝트 구현 | `frontend-foundation-playbook` | 재현 흐름 + 모바일 |
| 관리자 대시보드 | 필요하면 실제 사례 | `frontend-skill` | `admin-dashboard-playbook` | 권한별 흐름 + 반응형 |

## 선택 기준

### slides-grab과 frontend-slides

- PDF, PNG, PPTX, 편집기, 검증 흐름이 중요하면 `slides-grab`을 고른다.
- 설치 부담이 적은 단일 HTML과 빠른 웹 공유가 중요하면 `frontend-slides`를 고른다.
- PPTX와 Figma 출력은 실험적일 수 있으므로 납품 전에 직접 연다.

### frontend-skill과 ui-craft

- 새 시각 방향과 구현이 목적이면 `frontend-skill`을 고른다.
- 기존 화면의 토큰, 반슬롭, 접근성, 마무리 기준을 체계적으로 감사하려면 `ui-craft`를 시험한다.
- 둘을 같은 패스의 주 제작자로 사용하지 않는다.

### imagegen과 gongnyang-prompt-kit

- `gongnyang-prompt-kit`은 프롬프트를 편집하고 `imagegen`은 이미지를 만든다.
- 조합할 때 `프롬프트 편집 -> 이미지 생성 -> 결과 검수` 순서로 실행한다.

## 원본 우선순위

1. 프로젝트 규칙과 기존 디자인 토큰
2. [kyle]가 제공한 Figma, 참고 이미지, 브랜드 규칙
3. 실제 실행 화면과 사용자 흐름
4. 선택한 전문 스킬의 규칙
5. 일반적인 디자인 취향
