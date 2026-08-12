# UTM And Share Links

## Purpose

If the service is shared through KakaoTalk, blogs, X, or communities, the dashboard should not stop at `source` only.

It should show:

- `source`
- `medium`
- `campaign`

## Minimal UTM rules

### source

- `kakaotalk`
- `x`
- `blog`
- `community`
- `direct-share`

### medium

- `share`
- `social`
- `referral`

### campaign

- `launch`
- `wave1`
- `wave2`
- `wave3`

## Short-link rule

Prefer human-friendly redirects like:

- `/go/main`
- `/go/kakao-main`
- `/go/core-feature`

These should redirect to the real destination with full UTM attached.

## Search Console linkage

Recommended rollout:

1. Search Console via CSV import first
2. automate only after real operational pain appears
