# UTM And Short Links

## UTM principles

Use only three core fields unless there is a very good reason to add more.

- `utm_source`
- `utm_medium`
- `utm_campaign`

## Naming rules

### source

Use the channel name.

Examples:

- `kakaotalk`
- `x`
- `blog`
- `community`
- `direct-share`

### medium

Use the traffic type.

Examples:

- `share`
- `social`
- `referral`

### campaign

Use the experiment or rollout bundle name, not the full post title.

Examples:

- `ja_hub`
- `ja_wave1`
- `ja_wave2`
- `ja_wave3`

## Short-link rule

Expose short links to humans, but send them to full URLs with UTM.

Example:

- human link: `/go/kakao-era`
- redirect target: `/ja/japanese-era-converter/?utm_source=kakaotalk&utm_medium=share&utm_campaign=ja_wave1`

## Redirect behavior

Prefer temporary redirects like `302` while the campaign structure is still evolving.

Use separate short links per channel only when attribution clarity matters.

## Recommended bundle

- `/go/ja`
- `/go/kakao-ja`
- `/go/era`
- `/go/kakao-era`
- `/go/bizday`
- `/go/kakao-bizday`

Scale from there only when needed.
