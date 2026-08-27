# Polar Notes (MoR)

이 문서는 Polar 통합 시 실수하기 쉬운 포인트를 모아둔 실행 노트다.

## 1) 정책/비즈니스 적합성

- 수수료 구조는 `4% + 40¢` 기본, 추가 조건(구독/국제카드 등)이 있을 수 있다. `[POLAR_MOR_FEES]`
- 판매 가능/정산 가능 국가는 정책 문서를 우선 기준으로 본다. 한국(ROK) 포함 여부는 해당 문서의 최신 상태를 확인한다. `[POLAR_SUPPORTED_COUNTRIES]`
- 허용/금지 비즈니스는 결제 구현 전에 먼저 검토한다. 특히 디지털 상품/서비스 fulfilment 방식이 정책과 맞는지 확인한다. `[POLAR_ACCEPTABLE_USE]`

## 2) 체크아웃 구현 포인트

- Polar 체크아웃 통합은 서버에서 세션을 만들고 URL을 반환하는 흐름으로 설계한다. `[POLAR_CHECKOUT_OVERVIEW]`
- Checkout Session API를 사용할 때 내부 주문 ID를 metadata에 넣어 웹훅 상관관계를 안정적으로 만든다. `[POLAR_CHECKOUT_SESSION]`
- API 스펙은 반드시 공식 API 레퍼런스를 기준으로 맞춘다. `[POLAR_CREATE_CHECKOUT_API]`

## 3) 웹훅 처리 포인트

- 웹훅 엔드포인트 등록/관리 규칙은 Dashboard 설정값과 코드 설정을 일치시킨다. `[POLAR_WEBHOOK_ENDPOINTS]`
- 전송 실패/재시도 정책을 전제로 멱등 처리를 반드시 구현한다. `[POLAR_WEBHOOK_DELIVERY]`
- 서명 검증은 raw body 기준으로 수행하고, secret 관리 규칙을 코드/런북에 명시한다. `[POLAR_WEBHOOK_SIGNATURE]`

## 4) 변경 대응 포인트

- Polar는 API 변경 이력을 공개하므로 정기적으로 changelog를 확인한다. `[POLAR_API_CHANGELOG]`
- 변경 감지 시 아래 순서로 대응한다.
1. 영향받는 태그 식별
2. 어댑터 입력/출력 타입 수정
3. 웹훅 이벤트 매핑 테스트 갱신
4. 운영 체크리스트 업데이트
