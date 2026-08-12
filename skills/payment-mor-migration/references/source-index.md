# Payment MoR Migration Sources

기준일: 2026-02-26 (America/Los_Angeles 세션 기준)

목적:

- 마이그레이션 중 정책/수치/제약 판단의 근거를 단일 문서로 관리한다.
- 변경점 추적 시 태그 단위로 역추적 가능하게 만든다.

## Source Table

| Tag | Provider | Topic | URL | Last Checked |
| --- | --- | --- | --- | --- |
| `POLAR_MOR_FEES` | Polar | MoR 수수료 | https://polar.sh/docs/merchant-of-record/fees | 2026-02-26 |
| `POLAR_SUPPORTED_COUNTRIES` | Polar | 판매/정산 가능 국가 | https://polar.sh/docs/merchant-of-record/supported-countries | 2026-02-26 |
| `POLAR_ACCEPTABLE_USE` | Polar | 허용/금지 비즈니스 | https://polar.sh/docs/merchant-of-record/acceptable-use | 2026-02-26 |
| `POLAR_CHECKOUT_SESSION` | Polar | 체크아웃 세션 생성 가이드 | https://polar.sh/docs/features/checkout/session | 2026-02-26 |
| `POLAR_WEBHOOK_SIGNATURE` | Polar | 웹훅 서명 검증 | https://docs.polar.sh/integrate/webhooks | 2026-02-26 |
| `POLAR_WEBHOOK_DELIVERY` | Polar | 웹훅 재시도/전송 정책 | https://polar.sh/docs/integrate/webhooks/delivery | 2026-02-26 |
| `POLAR_API_CHANGELOG` | Polar | API 변경 이력 | https://docs.polar.sh/changelog/api | 2026-02-26 |
| `LEMON_MOR` | Lemon Squeezy | Merchant of Record 정의 | https://docs.lemonsqueezy.com/help/payments/merchant-of-record | 2026-02-26 |
| `LEMON_CREATE_CHECKOUT` | Lemon Squeezy | Checkout 생성 API | https://docs.lemonsqueezy.com/api/checkouts/create-checkout | 2026-02-26 |
| `LEMON_WEBHOOK_SIGNING` | Lemon Squeezy | 웹훅 서명 검증 | https://docs.lemonsqueezy.com/help/webhooks/signing-requests | 2026-02-26 |
| `LEMON_WEBHOOK_REQUESTS` | Lemon Squeezy | 웹훅 재시도 정책 | https://docs.lemonsqueezy.com/help/webhooks/webhook-requests | 2026-02-26 |
| `LEMON_FEES` | Lemon Squeezy | 플랫폼/추가 수수료 | https://docs.lemonsqueezy.com/help/getting-started/fees | 2026-02-26 |
| `LEMON_GETTING_PAID` | Lemon Squeezy | 정산 주기/홀드 | https://docs.lemonsqueezy.com/help/getting-started/getting-paid | 2026-02-26 |
| `LEMON_SUPPORTED_COUNTRIES` | Lemon Squeezy | 판매/정산 가능 국가 | https://docs.lemonsqueezy.com/help/getting-started/supported-countries | 2026-02-26 |
| `LEMON_PROHIBITED_PRODUCTS` | Lemon Squeezy | 금지 상품/서비스 | https://docs.lemonsqueezy.com/help/getting-started/prohibited-products | 2026-02-26 |

## 점검 커맨드

```bash
bash scripts/verify_source_links.sh
```
