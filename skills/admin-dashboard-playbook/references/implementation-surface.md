# Implementation Surface

## Minimum building blocks

- admin page
- event collector
- summary endpoint
- CSV export
- optional Search Console CSV import
- event table
- search-console table
- summary view

## Minimum fields

- `session_id`
- `page_path`
- `tool_slug` or equivalent
- `referrer_host`
- `utm_source`
- `utm_medium`
- `utm_campaign`
- `success`
- `error_code`

## Search Console strategy

Default:

1. start with CSV import
2. only automate later when import becomes real operational overhead

This keeps the kit light and broadly reusable.

## Privacy

Do not store raw:

- passwords
- names
- addresses
- freeform bodies

Store only metadata needed for attribution and aggregate behavior.
