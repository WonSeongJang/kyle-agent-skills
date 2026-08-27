# MomPick Baseline Map

현재 MomPick 코드베이스에서 마이그레이션 시작 시 가장 먼저 확인할 파일 목록이다.

## API Layer

- `api/_lib/payment-provider.ts`
- `api/_lib/payapp.ts`
- `api/_lib/payup.ts`
- `api/payments/create-order.ts`
- `api/payments/confirm.ts`
- `api/payments/webhook.ts`
- `api/payments/balance.ts`

## Frontend Layer

- `src/features/payments/constants.ts`
- `src/features/payments/services/paymentService.ts`
- `src/features/payments/components/CreditCheckoutPage.tsx`
- `src/features/payments/components/PaymentSuccessPage.tsx`
- `src/features/payments/components/PaymentFailPage.tsx`

## Data Layer

- `supabase/migrations/*payment*`
- `supabase/migrations/*credit*`
- `public.finalize_toss_payment(...)` 함수 정의가 포함된 마이그레이션

## Docs Layer

- `docs/PAYMENTS.md`
- `docs/ADR_002_PAYMENT_PROVIDER_POLICY_2026-02-26.md`
- `README.md` (운영 기준 설명)

## 조사 커맨드

```bash
bash scripts/find_payment_touchpoints.sh /Users/fw_m1/Dev/mompick_ai
```
