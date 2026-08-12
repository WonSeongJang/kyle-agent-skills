# 디자인 레퍼런스 라이브러리

## Why

설치할 스킬은 아니지만 실제 디자인을 고르고 비교할 때 반복해서 열 가치가 있는 사이트와 목록을 한곳에 둔다.

2026-08-12에 각 URL을 직접 열거나, 차단된 경우 검색 결과와 공개 저장소 설명으로 정체를 확인했다.

| 이름 | URL | 뭐가 좋은가 | 벤치마킹 용도(언제 열어보나) |
|---|---|---|---|
| 404s.design | https://www.404s.design/ | 404 오류 화면만 모은 좁고 선명한 갤러리. dark/light/animated/typographic 같은 비교가 쉽다. | 오류 페이지가 막다른 길이 아니라 복구·브랜드 경험이 되게 만들 때 |
| GDWEB | https://www.gdweb.co.kr/main/ | 2005년부터 이어진 국내 웹·모바일 수상작과 에이전시 포트폴리오 맥락 | 한국 사용자 대상 웹의 현재 완성도와 산업별 표현을 볼 때 |
| Superdesign | https://superdesign.dev/ | 에디터 안에서 여러 UI 방향을 병렬 생성·비교하는 오픈 디자인 에이전트와 공개 prompt library | 한 요구에서 여러 화면 방향을 빨리 비교하거나 프롬프트 예시가 필요할 때 |
| Reicon | https://reicon.dev/icons | 24×24 정밀 격자의 수천 개 SVG 아이콘, outline/filled/duotone, MIT, 여러 프레임워크·AI용 참조 | 앱 아이콘 세트의 무게·격자·프레임워크 지원을 통일할 때 |
| Framer | https://www.framer.com/ | 실제 반응형 사이트를 빠르게 만드는 도구이자 템플릿·애니메이션 구현 사례가 풍부 | 랜딩 인터랙션, 전환, 반응형 프로토타입의 실현 가능성을 볼 때 |
| DeviantArt | https://www.deviantart.com/ | UI에 한정되지 않은 방대한 일러스트·캐릭터·팬아트·재료 질감 | 캐릭터, 키비주얼, 비정형 스타일 무드보드가 필요할 때. UI 관행 근거로는 쓰지 않는다. |
| StyleGallery | https://github.com/changeroa/StyleGallery | portable layout, motion, design-engineering, platform reference를 근거·소유 경계별로 분리한 저장소 | CSS 레이아웃 패턴과 플랫폼별 참고를 코드 가까이에서 찾을 때 |
| Awesome UI | https://github.com/kevindeasis/awesome-ui | UI/UX·디자인 리소스를 넓게 묶은 탐색형 curated list | 어떤 레퍼런스 분야를 찾아야 할지 아직 모를 때 첫 색인으로 |
| Awesome Web Design | https://github.com/nicolesaidy/awesome-web-design | Awwwards, One Page Love, mobile patterns, Behance, UI Movement 등 검증된 갤러리 입구 | 랜딩·모바일·모션 레퍼런스 사이트를 목적별로 골라 들어갈 때 |
| Awesome Design | https://github.com/brandonhimpfen/awesome-design | UI·UX·product·interaction까지 도구, 책, 커뮤니티를 넓게 정리 | 제작보다 학습·도구 선정·커뮤니티 탐색이 필요할 때 |
| PptxGenJS | https://github.com/gitbrent/PptxGenJS | JavaScript로 PowerPoint를 만들고 차트·이미지·테이블을 코드로 제어 | HTML이 아니라 편집 가능한 `.pptx`가 최종 납품 형식일 때 |
| UIZZE | https://ui.zef.dev/ | Anti UI Slop이 요구하는 실제 웹 UI 레퍼런스 카탈로그 | 인터넷 탐색이 허용된 리디자인 전, AI 템플릿 대신 실재 사이트 비교가 필요할 때 |

## 사용 원칙

- 갤러리의 겉모양을 그대로 복사하지 않고 문제, 구조, 상호작용 단위로 비교한다.
- DeviantArt처럼 저작권과 출처가 제각각인 곳은 무드보드로만 쓰고 자산을 가져오지 않는다.
- awesome 목록은 최종 근거가 아니라 다음 원본 사이트를 찾는 색인이다.
- 비공개 제품 화면이나 사용자 데이터를 외부 레퍼런스 서비스에 올리지 않는다.
