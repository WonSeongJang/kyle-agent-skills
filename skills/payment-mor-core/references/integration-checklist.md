# Zero-Base Integration Checklist

## A. 설계 단계

1. 비즈니스 모델을 확정한다: 일회성 크레딧/구독/혼합.
2. 내부 결제 상태 모델을 고정한다: `created | pending | paid | failed | refunded | canceled`.
3. 공급자별 제한 정책을 출처 태그로 확인한다. `[POLAR_ACCEPTABLE_USE]`, `[LEMON_PROHIBITED_PRODUCTS]`

## B. API 단계

1. `/api/payments/create-order` 같은 내부 주문 생성 API를 만든다.
2. 서버에서만 가격/상품 매핑을 수행한다.
3. 공급자 체크아웃 생성 실패 시 내부 주문 상태를 `failed`로 전환한다.

## C. 웹훅 단계

1. raw body를 그대로 읽는다.
2. 서명을 검증한다. `[POLAR_WEBHOOK_SIGNATURE]`, `[LEMON_WEBHOOK_SIGNING]`
3. `event_id` 단위로 중복 이벤트를 막는다.
4. 이벤트를 내부 상태로 매핑한다.
5. `paid` 확정 시 원장 반영(크레딧/권한 지급)을 실행한다.

## D. 테스트 단계

1. 정상 결제 -> `paid` 반영 검증
2. 서명 오류 -> 거절 검증
3. 동일 웹훅 2회 -> 단일 지급 검증
4. 실패/환불 이벤트 -> 상태 전이 검증

## E. 운영 단계

1. 모니터링 지표를 정의한다:
- 웹훅 처리 성공률
- 결제 성공률
- 서명 검증 실패 수
- 중복 웹훅 감지 수
2. 출처 링크 상태를 정기 점검한다: `bash scripts/verify_source_links.sh`
3. 공급자 정책 변경 시 `source-index.md`와 운영 문서를 함께 갱신한다.
