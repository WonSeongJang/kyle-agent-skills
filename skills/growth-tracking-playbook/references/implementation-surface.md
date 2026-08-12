# Implementation Surface

## Typical architecture

- Search Console for search inflow
- client analytics script for page and action events
- serverless collector endpoint
- Supabase tables for event storage
- admin dashboard page
- optional CSV import for Search Console exports
- optional short-link redirects

## Minimum files

### Search

- `robots.txt`
- `sitemap.xml`
- Search Console verification tag or file

### Internal analytics

- analytics client script
- collector function
- summary function
- admin dashboard page
- DB migration

### Share attribution

- redirect rules file such as `/_redirects`
- internal share-link hub page if the team needs copyable links

## Minimum event set

- `landing_view`
- `tool_open`
- `tool_run_success`
- `tool_run_failure`
- `result_copy`
- `share_click`

## Minimum common fields

- `session_id`
- `page_path`
- `tool_slug`
- `site_lang`
- `referrer_host`
- `utm_source`
- `utm_medium`
- `utm_campaign`
- `device_type`

## Environment variables

Typical examples:

- Supabase URL
- Supabase service role key
- events table name
- search-console table name
- summary view name
- admin password
- admin session secret

## Dashboard sections

- KPI cards
- landing pages
- traffic breakdown
- tool performance
- failure events
- search import status

The traffic breakdown should show:

- `source`
- `medium`
- `campaign`
- sessions
- tool runs
