# Lemon Squeezy Notes (MoR)

이 문서는 Lemon Squeezy 통합 시 핵심 규칙을 빠르게 확인하기 위한 실행 노트다.

## 1) 정책/비즈니스 적합성

- Lemon Squeezy는 MoR 모델이다. 세금/결제 컴플라이언스 책임 분담 구조를 먼저 이해하고 설계한다. `[LEMON_MOR]`
- 금지 상품/서비스 규정을 먼저 확인한다. 특히 "서비스 판매" 성격이 있는 경우 정책 충돌이 없는지 검증한다. `[LEMON_PROHIBITED_PRODUCTS]`
- 국가 지원은 판매 가능 국가와 정산 가능 국가를 구분해서 확인한다. `[LEMON_SUPPORTED_COUNTRIES]`

## 2) 비용/정산 포인트

- 기본 플랫폼 수수료 외 추가 수수료 조건(국제 거래, PayPal, 구독 등)을 함께 반영해 수익 계산식을 만든다. `[LEMON_FEES]`
- 정산 주기/보류 기간(hold)을 현금흐름 계획에 반영한다. `[LEMON_GETTING_PAID]`

## 3) 체크아웃 구현 포인트

- Checkout 생성은 API 기준으로 서버에서 처리한다.
- 내부 주문 ID를 custom 데이터에 포함시켜 웹훅 상관관계를 유지한다. `[LEMON_CREATE_CHECKOUT]`

## 4) 웹훅 처리 포인트

- `X-Signature` 검증은 raw body + shared secret 기반 HMAC 검증으로 처리한다. `[LEMON_WEBHOOK_SIGNING]`
- 웹훅 실패 재시도 규칙(간격/횟수)을 고려해 이벤트 처리 로직을 멱등하게 설계한다. `[LEMON_WEBHOOK_REQUESTS]`
- 단순 success redirect만으로 결제 성공 처리하지 않는다. 웹훅 확정을 기준으로 원장을 반영한다.
